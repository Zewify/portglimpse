#!/usr/bin/env bash
# Tests scripts/install.sh against a fake GitHub release served from localhost.
# It never touches /Applications or a running PortGlimpse (PORTGLIMPSE_INSTALL_DIR, PORTGLIMPSE_NO_LAUNCH).
set -euo pipefail
cd "$(dirname "$0")/.."
INSTALL="$PWD/scripts/install.sh"
work=$(mktemp -d)
server_pid=""
cleanup() { if [ -n "$server_pid" ]; then kill "$server_pid" 2>/dev/null || true; wait "$server_pid" 2>/dev/null || true; fi; rm -rf "$work"; }
trap cleanup EXIT

port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
mkdir -p "$work/site"
(cd "$work/site" && exec python3 -m http.server "$port" --bind 127.0.0.1 >/dev/null 2>&1) &
server_pid=$!
for _ in $(seq 1 50); do curl -fs "http://127.0.0.1:$port/" >/dev/null 2>&1 && break; sleep 0.1; done

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; failures=$((failures + 1)); }

# A fake release: a minimal PortGlimpse.app whose Info.plist carries the version.
release() { # version [bad-sum] [no-assets]
  local version=$1 dir="$work/build-$1"
  rm -rf "$dir"; mkdir -p "$dir/PortGlimpse.app/Contents"
  printf '<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>CFBundleShortVersionString</key><string>%s</string></dict></plist>' "$version" > "$dir/PortGlimpse.app/Contents/Info.plist"
  (cd "$dir" && ditto -c -k --keepParent PortGlimpse.app "$work/site/PortGlimpse-$version.zip")
  local sum; sum=$(shasum -a 256 "$work/site/PortGlimpse-$version.zip" | cut -d' ' -f1)
  [ "${2:-}" = bad-sum ] && sum=0000000000000000000000000000000000000000000000000000000000000000
  printf '%s  PortGlimpse-%s.zip\n' "$sum" "$version" > "$work/site/PortGlimpse-$version.zip.sha256"
  local assets="[{\"name\":\"PortGlimpse-$version.zip\",\"browser_download_url\":\"http://127.0.0.1:$port/PortGlimpse-$version.zip\"},{\"name\":\"PortGlimpse-$version.zip.sha256\",\"browser_download_url\":\"http://127.0.0.1:$port/PortGlimpse-$version.zip.sha256\"}]"
  [ "${3:-}" = no-assets ] && assets="[]"
  printf '{"tag_name":"v%s","name":"PortGlimpse %s","assets":%s}' "$version" "$version" "$assets" > "$work/site/release.json"
}

run_install() { PORTGLIMPSE_API="http://127.0.0.1:$port/release.json" PORTGLIMPSE_INSTALL_DIR="$work/Apps" PORTGLIMPSE_NO_LAUNCH=1 sh "$INSTALL" >"$work/out.txt" 2>&1; }
installed_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$work/Apps/PortGlimpse.app/Contents/Info.plist" 2>/dev/null || echo none; }

release 1.0.0
if run_install && [ "$(installed_version)" = 1.0.0 ]; then pass "fresh install"; else fail "fresh install: $(cat "$work/out.txt")"; fi

release 1.0.1
if run_install && [ "$(installed_version)" = 1.0.1 ]; then pass "running it again updates"; else fail "update: $(cat "$work/out.txt")"; fi

# Review Focus 1: a bad checksum fails and leaves the installed copy as it was.
release 1.0.2 bad-sum
if ! run_install && [ "$(installed_version)" = 1.0.1 ] && grep -q "checksum" "$work/out.txt"; then pass "bad checksum refused, app untouched"; else fail "bad checksum: $(cat "$work/out.txt")"; fi

# Review Focus 2: a release without assets fails clearly.
release 1.0.3 "" no-assets
if ! run_install && [ "$(installed_version)" = 1.0.1 ] && grep -q "no download" "$work/out.txt"; then pass "release without assets refused"; else fail "no assets: $(cat "$work/out.txt")"; fi

# An unreachable API fails clearly.
if ! PORTGLIMPSE_API="http://127.0.0.1:1/nothing" PORTGLIMPSE_INSTALL_DIR="$work/Apps" PORTGLIMPSE_NO_LAUNCH=1 sh "$INSTALL" >"$work/out.txt" 2>&1 && grep -q "couldn't reach" "$work/out.txt"; then pass "unreachable API refused"; else fail "unreachable: $(cat "$work/out.txt")"; fi

# Review Focus 3: without an override and without write access to /Applications, it picks ~/Applications.
# Checked through the script's own choice function, so nothing is installed for real.
mkdir -p "$work/readonly"; chmod 555 "$work/readonly"
choice=$(HOME="$work/home" PORTGLIMPSE_APPLICATIONS="$work/readonly" PORTGLIMPSE_SOURCE_ONLY=1 sh -c ". '$INSTALL'; install_dir")
chmod 755 "$work/readonly"
if [ "$choice" = "$work/home/Applications" ]; then pass "non-admin falls back to ~/Applications"; else fail "fallback chose $choice"; fi

[ "$failures" -eq 0 ] || { echo "$failures installer test(s) failed"; exit 1; }
echo "installer: all tests passed"
