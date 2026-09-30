#!/bin/sh
# Installs or updates PortGlimpse from its latest GitHub release.
#   curl -fsSL https://zewify.com/portglimpse/install.sh | sh
# Run it again to update. It never uses sudo, and it only replaces the installed app
# once the new one has been downloaded and its SHA-256 checked.
set -eu

API="${PORTGLIMPSE_API:-https://api.github.com/repos/zewify/portglimpse/releases/latest}"
APP="PortGlimpse.app"

say() { printf 'PortGlimpse: %s\n' "$1"; }
fail() { printf 'PortGlimpse: %s\n' "$1" >&2; exit 1; }

# /Applications when this user can write to it (admin accounts can, without sudo), otherwise ~/Applications.
install_dir() {
  if [ -n "${PORTGLIMPSE_INSTALL_DIR:-}" ]; then echo "$PORTGLIMPSE_INSTALL_DIR"; return; fi
  system="${PORTGLIMPSE_APPLICATIONS:-/Applications}"
  if [ -w "$system" ]; then echo "$system"; else echo "$HOME/Applications"; fi
}

# Tests source this file for install_dir alone (PORTGLIMPSE_SOURCE_ONLY=1), so main does not run.
if [ "${PORTGLIMPSE_SOURCE_ONLY:-}" = "1" ]; then return 0; fi

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
  curl -fsSL -H "Accept: application/vnd.github+json" "$API" -o "$tmp/release.json" 2>/dev/null \
    || fail "couldn't reach GitHub. Check your connection and try again."
  zip_url=$(grep -o '"browser_download_url": *"[^"]*/PortGlimpse-[^"/]*\.zip"' "$tmp/release.json" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
  sum_url=$(grep -o '"browser_download_url": *"[^"]*/PortGlimpse-[^"/]*\.zip\.sha256"' "$tmp/release.json" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
  version=$(grep -o '"tag_name": *"[^"]*"' "$tmp/release.json" | head -n 1 | sed 's/.*"v\{0,1\}\([^"]*\)"$/\1/')
  [ -n "$zip_url" ] && [ -n "$sum_url" ] || fail "the latest release has no download yet. Try again in a few minutes."

  say "downloading PortGlimpse $version"
  curl -fsSL "$zip_url" -o "$tmp/app.zip" || fail "the download failed. Try again."
  curl -fsSL "$sum_url" -o "$tmp/app.zip.sha256" || fail "the checksum download failed. Try again."
  expected=$(cut -d' ' -f1 "$tmp/app.zip.sha256")
  actual=$(shasum -a 256 "$tmp/app.zip" | cut -d' ' -f1)
  [ "$expected" = "$actual" ] || fail "the download's checksum does not match, so nothing was installed. Try again."

  ditto -x -k "$tmp/app.zip" "$tmp/unpacked" || fail "the download could not be unpacked."
  [ -d "$tmp/unpacked/$APP" ] || fail "the download does not contain $APP."

  dest=$(install_dir)
  mkdir -p "$dest"
  if [ "${PORTGLIMPSE_NO_LAUNCH:-}" != "1" ]; then
    osascript -e 'quit app "PortGlimpse"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -xu "$(id -u)" PortGlimpse >/dev/null 2>&1 || break; sleep 0.5; done
    ! pgrep -xu "$(id -u)" PortGlimpse >/dev/null 2>&1 || fail "PortGlimpse didn't quit. Quit it from its panel, then run this again."
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
    open "$dest/$APP"
    say "it's in your menu bar. Run the same command again to update."
  fi
}

main "$@"
