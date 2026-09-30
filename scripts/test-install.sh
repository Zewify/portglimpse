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
# A static server that can also play GitHub refusing the API call: a file named
# "api-status" in the site makes /release.json answer with that status, and 403
# carries GitHub's rate-limit message and reset time (half an hour from now).
cat > "$work/server.py" <<'PY'
import http.server, json, os, sys, time
class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        flag = os.path.join(os.getcwd(), "api-status")
        if self.path == "/release.json" and os.path.exists(flag):
            status = int(open(flag).read().strip())
            body = json.dumps({"message": "API rate limit exceeded for 127.0.0.1." if status == 403 else "Server Error"}).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            if status == 403:
                self.send_header("x-ratelimit-remaining", "0")
                self.send_header("x-ratelimit-reset", str(int(time.time()) + 1800))
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super().do_GET()
http.server.ThreadingHTTPServer(("127.0.0.1", int(sys.argv[1])), Handler).serve_forever()
PY
(cd "$work/site" && exec python3 "$work/server.py" "$port" >/dev/null 2>&1) &
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
  # Pretty-printed like GitHub's real response, with the checksum listed before the zip.
  local assets
  assets=$(printf '[\n    {\n      "name": "PortGlimpse-%s.zip.sha256",\n      "browser_download_url": "http://127.0.0.1:%s/PortGlimpse-%s.zip.sha256"\n    },\n    {\n      "name": "PortGlimpse-%s.zip",\n      "browser_download_url": "http://127.0.0.1:%s/PortGlimpse-%s.zip"\n    }\n  ]' "$version" "$port" "$version" "$version" "$port" "$version")
  [ "${3:-}" = no-assets ] && assets="[]"
  printf '{\n  "tag_name": "v%s",\n  "name": "PortGlimpse %s",\n  "assets": %s\n}\n' "$version" "$version" "$assets" > "$work/site/release.json"
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

# Review Focus 1: a download cut short, served with the full file's checksum, is refused.
release 1.0.4
full=$(wc -c < "$work/site/PortGlimpse-1.0.4.zip"); head -c $((full / 2)) "$work/site/PortGlimpse-1.0.4.zip" > "$work/site/cut.zip" && mv "$work/site/cut.zip" "$work/site/PortGlimpse-1.0.4.zip"
if ! run_install && [ "$(installed_version)" = 1.0.1 ]; then pass "truncated download refused, app untouched"; else fail "truncated: $(cat "$work/out.txt")"; fi

# An old copy that cannot be fully deleted still gets replaced, and the run says what it left behind.
chmod 555 "$work/Apps/PortGlimpse.app/Contents"
release 1.0.5
if run_install && [ "$(installed_version)" = 1.0.5 ]; then pass "stubborn old copy replaced"; else fail "stubborn old copy: $(cat "$work/out.txt")"; fi
chmod -R 755 "$work/Apps" 2>/dev/null || true
rm -rf "$work/Apps/.PortGlimpse.app.old"

# An unreachable API fails clearly.
if ! PORTGLIMPSE_API="http://127.0.0.1:1/nothing" PORTGLIMPSE_INSTALL_DIR="$work/Apps" PORTGLIMPSE_NO_LAUNCH=1 sh "$INSTALL" >"$work/out.txt" 2>&1 && grep -q "couldn't reach" "$work/out.txt"; then pass "unreachable API refused"; else fail "unreachable: $(cat "$work/out.txt")"; fi

# Review Focus 3: without an override and without write access to /Applications, it picks ~/Applications.
# Checked through the script's own choice function, so nothing is installed for real.
mkdir -p "$work/readonly"; chmod 555 "$work/readonly"
choice=$(HOME="$work/home" PORTGLIMPSE_APPLICATIONS="$work/readonly" PORTGLIMPSE_SOURCE_ONLY=1 sh -c ". '$INSTALL'; install_dir")
chmod 755 "$work/readonly"
if [ "$choice" = "$work/home/Applications" ]; then pass "non-admin falls back to ~/Applications"; else fail "fallback chose $choice"; fi

# GitHub's rate limit is named as such, with the wait, not reported as a lost connection.
echo 403 > "$work/site/api-status"
if ! run_install && [ "$(installed_version)" = 1.0.5 ] && grep -q "limit has been reached. Try again in about 30 minutes" "$work/out.txt"; then pass "rate limit explained, app untouched"; else fail "rate limit: $(cat "$work/out.txt")"; fi
echo 500 > "$work/site/api-status"
if ! run_install && grep -q "HTTP 500" "$work/out.txt"; then pass "server error reported with its status"; else fail "server error: $(cat "$work/out.txt")"; fi
rm "$work/site/api-status"

# An update goes where the app already is. Checked through the script's own choice function,
# with the running copy's folder supplied, so nothing real is inspected or installed.
choose() { # home applications running-dir
  HOME="$1" PORTGLIMPSE_APPLICATIONS="$2" PORTGLIMPSE_SOURCE_ONLY=1 RUNNING="$3" sh -c ". '$INSTALL'; running_app_dir() { echo \"\$RUNNING\"; }; install_dir"
}
mkdir -p "$work/sys" "$work/home/Applications/PortGlimpse.app"
choice=$(choose "$work/home" "$work/sys" "")
if [ "$choice" = "$work/home/Applications" ]; then pass "existing copy in ~/Applications is updated there"; else fail "existing ~/Applications copy: chose $choice"; fi
choice=$(choose "$work/home" "$work/sys" "$work/sys/Utilities")
if [ "$choice" = "$work/sys/Utilities" ]; then pass "running copy's folder is updated in place"; else fail "running copy: chose $choice"; fi
choice=$(choose "$work/nohome" "$work/sys" "$work/DerivedData/Build/Products/Debug")
if [ "$choice" = "$work/sys" ]; then pass "a copy running from a build folder is not replaced"; else fail "build folder: chose $choice"; fi

# Quitting and relaunching: the running app is quit before the swap and the new one opened after.
# is_running, quit_app and launch_app are replaced, so the real PortGlimpse is never touched.
quit_run() { # seconds-until-it-quits ("never" to keep running)
  PORTGLIMPSE_API="http://127.0.0.1:$port/release.json" PORTGLIMPSE_INSTALL_DIR="$work/Apps" PORTGLIMPSE_SOURCE_ONLY=1 \
    LOG="$work/calls.txt" STATE="$work/state" QUITS_AFTER="$1" sh -c "
      . '$INSTALL'
      is_running() { [ -e \"\$STATE/running\" ]; }
      quit_app() {
        echo \"quit, installed \$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '$work/Apps/PortGlimpse.app/Contents/Info.plist')\" >> \"\$LOG\"
        [ \"\$QUITS_AFTER\" = never ] || (sleep \"\$QUITS_AFTER\"; rm -f \"\$STATE/running\") &
      }
      launch_app() { echo \"launch \$1, installed \$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \"\$1/Contents/Info.plist\")\" >> \"\$LOG\"; }
      main" >"$work/out.txt" 2>&1
}
mkdir -p "$work/state"; : > "$work/calls.txt"; touch "$work/state/running"
release 1.0.6
if quit_run 1 && [ "$(installed_version)" = 1.0.6 ] \
  && [ "$(cat "$work/calls.txt")" = "$(printf 'quit, installed 1.0.5\nlaunch %s, installed 1.0.6' "$work/Apps/PortGlimpse.app")" ]; then
  pass "running app quit before the swap, new one launched after"
else fail "quit and relaunch: $(cat "$work/out.txt") / $(cat "$work/calls.txt")"; fi
: > "$work/calls.txt"; touch "$work/state/running"
release 1.0.7
if ! quit_run never && [ "$(installed_version)" = 1.0.6 ] && grep -q "didn't quit" "$work/out.txt" && ! grep -q launch "$work/calls.txt"; then
  pass "an app that won't quit is left alone"
else fail "won't quit: $(cat "$work/out.txt") / $(cat "$work/calls.txt")"; fi
rm -f "$work/state/running"; : > "$work/calls.txt"
release 1.0.8
if quit_run 1 && [ "$(installed_version)" = 1.0.8 ] && [ "$(cat "$work/calls.txt")" = "$(printf 'launch %s, installed 1.0.8' "$work/Apps/PortGlimpse.app")" ]; then
  pass "an app that isn't running is not asked to quit"
else fail "not running: $(cat "$work/out.txt") / $(cat "$work/calls.txt")"; fi

# The documented form: the script arrives on standard input, as with curl … | sh.
release 1.0.9
if curl -fsSL "file://$INSTALL" | PORTGLIMPSE_API="http://127.0.0.1:$port/release.json" PORTGLIMPSE_INSTALL_DIR="$work/Apps" PORTGLIMPSE_NO_LAUNCH=1 sh >"$work/out.txt" 2>&1 \
  && [ "$(installed_version)" = 1.0.9 ] && grep -q "installed 1.0.9" "$work/out.txt"; then
  pass "piped into sh, as documented"
else fail "piped: $(cat "$work/out.txt")"; fi

[ "$failures" -eq 0 ] || { echo "$failures installer test(s) failed"; exit 1; }
echo "installer: all tests passed"
