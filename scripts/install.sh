#!/bin/sh
# Installs or updates PortGlimpse from its latest GitHub release.
#   curl -fsSL https://zewify.com/portglimpse/install.sh | sh
# Run it again to update. It never uses sudo, and it only replaces the installed app
# once the new one has been downloaded and its SHA-256 checked.
set -eu

API="${PORTGLIMPSE_API:-https://api.github.com/repos/zewify/portglimpse/releases/latest}"
APP="PortGlimpse.app"
BUNDLE_ID="com.zewify.portglimpse"

say() { printf 'PortGlimpse: %s\n' "$1"; }
fail() { printf 'PortGlimpse: %s\n' "$1" >&2; exit 1; }

# This user's running PortGlimpse, if any. Tests replace these three after sourcing the file.
is_running() { pgrep -xu "$(id -u)" PortGlimpse >/dev/null 2>&1; }
quit_app() { osascript -e "quit app id \"$BUNDLE_ID\"" >/dev/null 2>&1 || true; }
launch_app() { open "$1"; }

# The folder the running copy was opened from, or nothing.
running_app_dir() {
  ps -xo comm= -u "$(id -u)" 2>/dev/null | sed -n 's|^\(.*\)/PortGlimpse\.app/Contents/MacOS/PortGlimpse$|\1|p' | head -n 1
}

# Where to install. An update goes where the app already is: the running copy's folder when it is
# inside an Applications folder (a build run from Xcode is not), else an existing copy in
# /Applications or ~/Applications. A first install goes to /Applications when this user can write
# to it (admin accounts can, without sudo), otherwise ~/Applications.
install_dir() {
  if [ -n "${PORTGLIMPSE_INSTALL_DIR:-}" ]; then echo "$PORTGLIMPSE_INSTALL_DIR"; return; fi
  system="${PORTGLIMPSE_APPLICATIONS:-/Applications}"
  running=$(running_app_dir)
  case "$running" in
    "$system" | "$system"/* | "$HOME/Applications" | "$HOME/Applications"/*) echo "$running"; return ;;
  esac
  if [ -d "$system/$APP" ]; then echo "$system"; return; fi
  if [ -d "$HOME/Applications/$APP" ]; then echo "$HOME/Applications"; return; fi
  if [ -w "$system" ]; then echo "$system"; else echo "$HOME/Applications"; fi
}

# Asks GitHub for the latest release into $1, and turns every failure into a plain sentence.
fetch_release() {
  code=$(curl -sSL -H "Accept: application/vnd.github+json" -D "$1.headers" -o "$1" -w '%{http_code}' "$API" 2>/dev/null) || code=000
  case "$code" in
    200) return 0 ;;
    000) fail "couldn't reach GitHub. Check your connection and try again." ;;
    403 | 429)
      # Unsigned requests to GitHub's API are limited to 60 an hour per network.
      if grep -qi 'rate limit' "$1" 2>/dev/null; then
        reset=$(tr -d '\r' < "$1.headers" | sed -n 's/^[Xx]-[Rr]ate[Ll]imit-[Rr]eset: *\([0-9][0-9]*\).*/\1/p' | tail -n 1)
        if [ -n "$reset" ]; then
          minutes=$(( (reset - $(date +%s) + 59) / 60 ))
          [ "$minutes" -ge 1 ] || minutes=1
          fail "GitHub limits how often one network can check for releases, and that limit has been reached. Try again in about $minutes minute$([ "$minutes" -eq 1 ] || echo s)."
        fi
        fail "GitHub limits how often one network can check for releases, and that limit has been reached. Try again within the hour."
      fi
      fail "GitHub refused the request (HTTP $code). Try again later." ;;
    *) fail "GitHub answered with an error (HTTP $code). Try again later." ;;
  esac
}

main() {
  [ "$(uname -s)" = "Darwin" ] || fail "this installer is for macOS."
  major=$(sw_vers -productVersion | cut -d. -f1)
  [ "$major" -ge 14 ] || fail "PortGlimpse needs macOS 14 or later."

  tmp=$(mktemp -d)
  # Clean up on every exit, and make Ctrl-C or a kill actually stop the script.
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM

  say "finding the latest release"
  fetch_release "$tmp/release.json"
  zip_url=$(grep -o '"browser_download_url": *"[^"]*/PortGlimpse-[^"/]*\.zip"' "$tmp/release.json" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
  sum_url=$(grep -o '"browser_download_url": *"[^"]*/PortGlimpse-[^"/]*\.zip\.sha256"' "$tmp/release.json" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
  version=$(grep -o '"tag_name": *"[^"]*"' "$tmp/release.json" | head -n 1 | sed 's/.*"v\{0,1\}\([^"]*\)"$/\1/')
  [ -n "$zip_url" ] && [ -n "$sum_url" ] || fail "the latest release has no download yet. Try again in a few minutes."

  dest=$(install_dir)
  installed=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$dest/$APP/Contents/Info.plist" 2>/dev/null || true)
  if [ -n "$version" ] && [ "$installed" = "$version" ]; then
    say "$version is already installed in $dest, so there is nothing to update."
    if [ "${PORTGLIMPSE_NO_LAUNCH:-}" != "1" ] && ! is_running; then launch_app "$dest/$APP"; fi
    return 0
  fi

  say "downloading PortGlimpse $version"
  curl -fsSL "$zip_url" -o "$tmp/app.zip" || fail "the download failed. Try again."
  curl -fsSL "$sum_url" -o "$tmp/app.zip.sha256" || fail "the checksum download failed. Try again."
  expected=$(cut -d' ' -f1 "$tmp/app.zip.sha256")
  actual=$(shasum -a 256 "$tmp/app.zip" | cut -d' ' -f1)
  [ "$expected" = "$actual" ] || fail "the download's checksum does not match, so nothing was installed. Try again."

  ditto -x -k "$tmp/app.zip" "$tmp/unpacked" || fail "the download could not be unpacked."
  [ -d "$tmp/unpacked/$APP" ] || fail "the download does not contain $APP."

  mkdir -p "$dest"
  if [ "${PORTGLIMPSE_NO_LAUNCH:-}" != "1" ] && is_running; then
    say "quitting PortGlimpse to update it"
    quit_app
    for _ in 1 2 3 4 5 6 7 8 9 10; do is_running || break; sleep 0.5; done
    ! is_running || fail "PortGlimpse didn't quit. Quit it from its panel, then run this again."
  fi
  # Copy the new app in beside the old one, move the old one aside, then move the new one into place.
  # Each step is a rename within one folder, and a failure puts the old copy back, so there is always an app.
  new="$dest/.$APP.new"
  old="$dest/.$APP.old"
  rm -rf "$new" "$old" 2>/dev/null || true
  ditto "$tmp/unpacked/$APP" "$new" || { rm -rf "$new" 2>/dev/null; fail "couldn't write to $dest."; }
  if [ -e "$dest/$APP" ]; then
    mv "$dest/$APP" "$old" || { rm -rf "$new" 2>/dev/null; fail "couldn't move the installed copy aside in $dest, so nothing changed."; }
  fi
  if ! mv "$new" "$dest/$APP"; then
    [ -e "$old" ] && mv "$old" "$dest/$APP"
    fail "couldn't finish installing in $dest; the previous copy is back in place."
  fi
  if [ -e "$old" ]; then
    rm -rf "$old" 2>/dev/null || say "the previous copy couldn't be fully removed; delete $old when you like."
  fi

  say "installed $version in $dest"
  if [ "${PORTGLIMPSE_NO_LAUNCH:-}" != "1" ]; then
    launch_app "$dest/$APP"
    say "it's in your menu bar. Run the same command again to update."
  fi
}

# Tests source this file (PORTGLIMPSE_SOURCE_ONLY=1) to call its functions, so main does not run.
if [ "${PORTGLIMPSE_SOURCE_ONLY:-}" = "1" ]; then return 0; fi
main "$@"
