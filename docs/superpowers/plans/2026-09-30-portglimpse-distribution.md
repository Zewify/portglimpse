# PortGlimpse Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Anyone on macOS 14+ can install and update PortGlimpse with `curl -fsSL https://zewify.com/portglimpse/install.sh | sh`, from an ad hoc signed release on GitHub, and read about it at `zewify.com/portglimpse/`.

**Architecture:** The portglimpse repo owns the installer (`scripts/install.sh`, tested against a fake release on localhost), packaging, and two GitHub Actions workflows (tests on push; release on a `v*` tag).
The web server that serves zewify.com redirects `zewify.com/portglimpse/install.sh` to the installer's raw copy on `main`, so there is one copy.
The zewify repo gains `/portglimpse/` and `/portglimpse/privacy/` in TickThock's look, with every printed fact in `src/portglimpse/data.ts` and `latestVersion` as the launch switch.

**Tech Stack:** POSIX `sh`, `curl`, `ditto`, `shasum`; GitHub Actions on a macOS runner with XcodeGen; Caddy; Astro 7 (zewify), `sharp` and headless Chrome for its images.

**Spec:** `docs/superpowers/specs/2026-09-30-portglimpse-design.md`, sections "Distribution" and "Identity". The zewify repo's own rules are in its `CLAUDE.md`; read it before Tasks 6 and 7.

## Global Constraints

- Releases are signed ad hoc; no Developer ID, no notarization, no Apple credentials anywhere.
- The site offers the `curl` command only — never a download button or a link to the zip.
- Release assets are exactly `PortGlimpse-<version>.zip` and `PortGlimpse-<version>.zip.sha256`; the tag is `v<version>` and must equal `MARKETING_VERSION` in `project.yml`.
- `install.sh` is POSIX `sh`, never uses `sudo`, never leaves a half-installed app, and verifies SHA-256 before touching the installed copy.
- The installer's only network endpoints are `api.github.com` and the release's own download URLs.
- Identity: nothing names a person — code, commits, workflow files, the site, share images, screenshots. Screenshots come from the demo mode only. Commits are authored `Zewify <dev@zewify.com>` (each repo's configured author); no co-author trailers.
- zewify: every printed fact lives in `src/portglimpse/data.ts`; no `<style>`, inline `<script>`, `style=` or `on*=` in the output; sizes in rem; the dist tests stay green and are never weakened.
- Markdown docs put each full sentence on its own line.
- Outward actions need the owner's go-ahead before they run: creating and pushing the public repo, pushing a tag, changing the web server's configuration, and pushing zewify `main` (which deploys to production).

Every `gh`, `git push` and server command in Tasks 5, 6 and 7 runs as the owner's personal accounts; the exact account switch, server access and server layout live in the owner's private notes, never in this public repo.

## Review Focus

1. A checksum mismatch or a truncated download must leave an existing `PortGlimpse.app` exactly as it was — Task 2 pins it.
2. A release that has no zip yet (published without assets, or assets still uploading) must fail with a clear message, not install garbage — Task 2 pins it.
3. `install.sh` run by a non-admin user (no write access to `/Applications`) must install to `~/Applications` — Task 2 pins it with an override.
4. A tag that does not match `MARKETING_VERSION` must stop the release before anything is published — Task 3 pins it.
5. No screenshot or page may show a real folder, host or user name — Task 4 builds demo data, Task 7's identity test covers the pages.

---

## File Structure

```
portglimpse/
  scripts/install.sh                 the installer (Task 2)
  scripts/test-install.sh            its tests, against a fake release on localhost (Task 2)
  scripts/test.sh                    gains the installer tests (Task 2)
  scripts/check-version.sh           tag == MARKETING_VERSION (Task 3)
  scripts/package.sh                 Release build -> zip + .sha256 + notes (Task 3)
  scripts/capture-shots.sh           demo-mode screenshots for the site (Task 4)
  scripts/window-id.swift            finds PortGlimpse's window ids for screencapture (Task 4)
  .github/workflows/ci.yml           tests on push to main (Task 3)
  .github/workflows/release.yml      release on a v* tag (Task 3)
  App/Sources/DemoRows.swift         DEBUG-only made-up rows (Task 4)
  App/Sources/PanelModel.swift       uses them under -PortGlimpseDemo YES (Task 4)
zewify.com web server config         redirect for /portglimpse/install.sh (Task 6)
zewify/
  src/portglimpse/data.ts            every printed fact, launch switch (Task 7)
  src/portglimpse/layouts/Base.astro, Doc.astro, components/Logo.astro, Shot.astro, InstallCommand.astro
  src/portglimpse/styles/portglimpse.css   small additions on top of TickThock's stylesheet
  src/pages/portglimpse/index.astro, privacy.astro
  public/portglimpse/favicon.svg, favicon-32.png, apple-touch-icon.png, og.png, shots/*.png
  public/products/portglimpse.png
  src/data/site.ts, src/pages/{index,privacy,terms,contact}.astro   product list and prose
  scripts/make-icons.mjs, scripts/make-og.mjs, tests/dist.test.mjs
```

---

### Task 1: Record the distribution decisions

The spec's Distribution section was rewritten for ad hoc signing on 2026-09-30 (commit it with this plan).

- [ ] **Step 1: Commit the spec and this plan**

```bash
cd ~/Developer/personal/portglimpse
git add docs/superpowers/specs/2026-09-30-portglimpse-design.md docs/superpowers/plans/2026-09-30-portglimpse-distribution.md
git commit -m "Plan distribution: ad hoc signed releases installed with curl"
```

---

### Task 2: The installer and its tests

**Files:**
- Create: `scripts/install.sh`, `scripts/test-install.sh`
- Modify: `scripts/test.sh`

**Interfaces:**
- Produces: `install.sh` honouring test overrides — `PORTGLIMPSE_API` (release JSON URL), `PORTGLIMPSE_INSTALL_DIR` (skip the /Applications choice), `PORTGLIMPSE_APPLICATIONS` (stand-in for /Applications), `PORTGLIMPSE_NO_LAUNCH=1` (never quit or open the real app), `PORTGLIMPSE_SOURCE_ONLY=1` (define functions only). Exit 0 on success, 1 with a `PortGlimpse: …` message on stderr otherwise.

- [ ] **Step 1: Write the failing tests**

`scripts/test-install.sh` (make executable):

```bash
#!/usr/bin/env bash
# Tests scripts/install.sh against a fake GitHub release served from localhost.
# It never touches /Applications or a running PortGlimpse (PORTGLIMPSE_INSTALL_DIR, PORTGLIMPSE_NO_LAUNCH).
set -euo pipefail
cd "$(dirname "$0")/.."
INSTALL="$PWD/scripts/install.sh"
work=$(mktemp -d)
server_pid=""
cleanup() { [ -n "$server_pid" ] && kill "$server_pid" 2>/dev/null || true; rm -rf "$work"; }
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
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `chmod +x scripts/test-install.sh && ./scripts/test-install.sh`
Expected: failures, because `scripts/install.sh` does not exist yet.

- [ ] **Step 3: Write the installer**

`scripts/install.sh` (make executable):

```sh
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
  trap 'rm -rf "$tmp"' EXIT INT TERM

  say "finding the latest release"
  curl -fsSL -H "Accept: application/vnd.github+json" "$API" -o "$tmp/release.json" 2>/dev/null \
    || fail "couldn't reach GitHub. Check your connection and try again."
  zip_url=$(grep -o '"browser_download_url": *"[^"]*\.zip"' "$tmp/release.json" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
  sum_url=$(grep -o '"browser_download_url": *"[^"]*\.zip\.sha256"' "$tmp/release.json" | head -n 1 | sed 's/.*"\([^"]*\)"$/\1/')
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
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x PortGlimpse >/dev/null 2>&1 || break; sleep 0.5; done
  fi
  # Copy beside the old app first, then swap, so a failure never leaves no app at all.
  rm -rf "$dest/.$APP.new"
  ditto "$tmp/unpacked/$APP" "$dest/.$APP.new" || fail "couldn't write to $dest."
  rm -rf "$dest/$APP"
  mv "$dest/.$APP.new" "$dest/$APP"

  say "installed $version in $dest"
  if [ "${PORTGLIMPSE_NO_LAUNCH:-}" != "1" ]; then
    open "$dest/$APP"
    say "it's in your menu bar. Run the same command again to update."
  fi
}

main "$@"
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `./scripts/test-install.sh`
Expected: six `ok` lines and `installer: all tests passed`.

- [ ] **Step 5: Add the installer tests to the gate and commit**

In `scripts/test.sh`, add the line `./scripts/test-install.sh` after the core tests (before the app build).
Run `./scripts/test.sh` (exit 0), then:

```bash
git add scripts/install.sh scripts/test-install.sh scripts/test.sh
git commit -m "Add the curl installer, tested against a fake release"
```

---

### Task 3: Packaging and the two workflows

**Files:**
- Create: `scripts/check-version.sh`, `scripts/package.sh`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `scripts/build.sh Release` (prints the app path), `scripts/test.sh`.
- Produces: `build/release/PortGlimpse-<version>.zip`, `.zip.sha256`, `notes.md`.

- [ ] **Step 1: Write the version check and packaging scripts**

`scripts/check-version.sh`:

```bash
#!/usr/bin/env bash
# Fails unless the tag (v1.2.3) equals MARKETING_VERSION in project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."
tag="${1:?usage: check-version.sh v<version>}"
version=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml | head -n 1)
[ "$tag" = "v$version" ] || { echo "Tag $tag does not match MARKETING_VERSION $version in project.yml" >&2; exit 1; }
echo "$version"
```

`scripts/package.sh`:

```bash
#!/usr/bin/env bash
# Builds Release (universal, ad hoc signed) and writes the release assets to build/release/.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml | head -n 1)
app="$(./scripts/build.sh Release | tail -1)"
lipo -archs "$app/Contents/MacOS/PortGlimpse" | grep -q x86_64 || { echo "Not a universal binary" >&2; exit 1; }
out=build/release
rm -rf "$out"; mkdir -p "$out"
zip="PortGlimpse-$version.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$out/$zip"
(cd "$out" && shasum -a 256 "$zip" > "$zip.sha256")
cat > "$out/notes.md" <<EOF
Install or update:

\`\`\`
curl -fsSL https://zewify.com/portglimpse/install.sh | sh
\`\`\`

Needs macOS 14 or later.
This build is signed ad hoc, so it is meant to be installed with the command above rather than opened from a browser download.
EOF
echo "$out/$zip"
```

Run: `chmod +x scripts/check-version.sh scripts/package.sh && ./scripts/check-version.sh v1.0.0 && ./scripts/check-version.sh v9.9.9; echo "exit $?"`
Expected: `1.0.0`, then the mismatch message and `exit 1` (Review Focus 4).
Run: `./scripts/package.sh && cat build/release/*.sha256 && unzip -l build/release/*.zip | tail -1`
Expected: the zip path, a `hash  PortGlimpse-1.0.0.zip` line, and a file count.

- [ ] **Step 2: Write the workflows**

`.github/workflows/ci.yml`:

```yaml
name: Tests
on:
  push:
    branches: [main]
permissions:
  contents: read
jobs:
  test:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Use the newest Xcode
        run: sudo xcode-select -s "$(ls -d /Applications/Xcode_*.app | sort -V | tail -n 1)"
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Test
        run: ./scripts/test.sh
```

`.github/workflows/release.yml`:

```yaml
name: Release
on:
  push:
    tags: ['v*']
permissions:
  contents: write
jobs:
  release:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4
      - name: Check the tag matches the app version
        run: ./scripts/check-version.sh "$GITHUB_REF_NAME"
      - name: Use the newest Xcode
        run: sudo xcode-select -s "$(ls -d /Applications/Xcode_*.app | sort -V | tail -n 1)"
      - name: Install XcodeGen
        run: brew install xcodegen
      - name: Test
        run: ./scripts/test.sh
      - name: Package
        run: ./scripts/package.sh
      - name: Publish the release
        env:
          GH_TOKEN: ${{ github.token }}
        run: gh release create "$GITHUB_REF_NAME" build/release/PortGlimpse-*.zip build/release/PortGlimpse-*.zip.sha256 --title "PortGlimpse ${GITHUB_REF_NAME#v}" --notes-file build/release/notes.md --verify-tag
```

`build/` is already gitignored.
The runner label `macos-26` and the Xcode path are checked on the first real run in Task 5; if the label does not exist, use the newest `macos-*` label GitHub lists whose Xcode is 26 or later.

- [ ] **Step 3: Commit**

```bash
git add scripts/check-version.sh scripts/package.sh .github/workflows/ci.yml .github/workflows/release.yml
git commit -m "Add packaging, a tests workflow and a tag-driven release workflow"
```

---

### Task 4: Demo mode and screenshots for the site

Real screenshots would show real folders, so the site's shots come from made-up rows in a DEBUG build.

**Files:**
- Create: `App/Sources/DemoRows.swift`, `scripts/window-id.swift`, `scripts/capture-shots.sh`
- Modify: `App/Sources/PanelModel.swift`

- [ ] **Step 1: Add the demo rows**

`App/Sources/DemoRows.swift`:

```swift
#if DEBUG
import PortGlimpseCore

/// Made-up rows for the website's screenshots (`-PortGlimpseDemo YES` on a Debug build).
/// The PIDs are far above any real one, so the Terminator refuses them as already exited.
enum DemoRows {
    static let enabled = UserDefaults.standard.bool(forKey: "PortGlimpseDemo")

    static let rows: [Row] = [
        Row(pid: 990_001, ports: [3000], command: "next dev", folder: "~/Developer/shop/web", owner: nil, section: .dev, executablePath: "/opt/homebrew/bin/node"),
        Row(pid: 990_002, ports: [5173], command: "vite", folder: "~/Developer/shop/admin", owner: nil, section: .dev, executablePath: "/opt/homebrew/bin/node"),
        Row(pid: 990_003, ports: [8000], command: "granian asgi", folder: "~/Developer/shop/api", owner: nil, section: .dev, executablePath: "/opt/homebrew/bin/python3", workerPIDs: [990_004, 990_005]),
        Row(pid: 990_006, ports: [5432], command: "postgres", folder: "/opt/homebrew/var/postgresql@17", owner: nil, section: .dev, executablePath: "/opt/homebrew/bin/postgres"),
        Row(pid: 990_007, ports: [6379], command: "redis-server", folder: "/opt/homebrew/var/db/redis", owner: nil, section: .dev, executablePath: "/opt/homebrew/bin/redis-server"),
        Row(pid: 990_008, ports: [5000, 7000], command: "ControlCenter", folder: nil, owner: nil, section: .appsAndSystem, executablePath: "/System/Library/CoreServices/ControlCenter.app/Contents/MacOS/ControlCenter"),
        Row(pid: 990_009, ports: [49152], command: "rapportd", folder: nil, owner: nil, section: .appsAndSystem, executablePath: "/usr/libexec/rapportd"),
    ]
}
#endif
```

In `PanelModel.refresh()`, before the detached scan, add:

```swift
        #if DEBUG
        if DemoRows.enabled {
            rows = DemoRows.rows
            problem = nil
            otherUsersProblem = nil
            return
        }
        #endif
```

(Keep the generation counter consistent: take the generation number first as today, and apply demo rows only if it is still the newest, exactly as a scan result would be.)

- [ ] **Step 2: Write the capture tooling**

`scripts/window-id.swift` prints `<id> <width>x<height>` for each on-screen PortGlimpse window, largest last:

```swift
// Prints the CGWindowID and size of every on-screen PortGlimpse window, for `screencapture -l`.
import CoreGraphics
import Foundation

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows where (window[kCGWindowOwnerName as String] as? String) == "PortGlimpse" {
    guard let id = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Double],
          let layer = window[kCGWindowLayer as String] as? Int, layer != 25 else { continue } // 25 = the status item
    print("\(id) \(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0))")
}
```

`scripts/capture-shots.sh` writes `build/shots/panel.png` and `build/shots/window.png`:

```bash
#!/usr/bin/env bash
# Captures the website's screenshots from a Debug build in demo mode (made-up projects only).
# Needs the Accessibility permission for the terminal (System Events clicks). Output: build/shots/.
set -euo pipefail
cd "$(dirname "$0")/.."
out=build/shots; mkdir -p "$out"
osascript -e 'quit app "PortGlimpse"' >/dev/null 2>&1 || true; sleep 1
app="$(./scripts/build.sh Debug | tail -1)"
defaults delete com.zewify.portglimpse "NSWindow Frame PortGlimpseWindow" >/dev/null 2>&1 || true
open -n "$app" --args -PortGlimpseDemo YES
for _ in $(seq 1 40); do osascript -e 'tell application "System Events" to exists menu bar 2 of process "PortGlimpse"' 2>/dev/null | grep -q true && break; sleep 0.25; done
osascript -e 'tell application "System Events" to tell process "PortGlimpse" to click menu bar item 1 of menu bar 2' >/dev/null
sleep 1.5
panel=$(swift scripts/window-id.swift | tail -n 1 | cut -d' ' -f1)
screencapture -x -o -l "$panel" "$out/panel.png"
echo "Now click the panel's pop-out button, then press return here."; read -r _
sleep 1
win=$(swift scripts/window-id.swift | sort -t' ' -k2 | tail -n 1 | cut -d' ' -f1)
screencapture -x -o -l "$win" "$out/window.png"
osascript -e 'quit app "PortGlimpse"' >/dev/null 2>&1 || true
sips -g pixelWidth -g pixelHeight "$out"/*.png
```

- [ ] **Step 3: Capture and check**

Run: `./scripts/capture-shots.sh` (click the pop-out button when asked).
Open both PNGs and check: only the made-up rows appear (`~/Developer/shop/...`, postgres, redis), granian reads "2 workers", and nothing from the real Mac shows.
If the display is Retina (2x), halve the sizes the site declares; this Mac is 1x.

- [ ] **Step 4: Commit**

```bash
./scripts/test.sh
git add App/Sources/DemoRows.swift App/Sources/PanelModel.swift scripts/window-id.swift scripts/capture-shots.sh
git commit -m "Add a debug-only demo mode and the website screenshot script"
```

---

### Task 5: Publish the repo and the first release (outward — owner's go-ahead)

- [ ] **Step 1: Merge the branch to main and check identity**

Merge the branch locally (fast-forward) and run the denylist check from the app plan over the whole history:
`grep -v '^#' ~/.config/zewify/identity-denylist | git grep -niEf /dev/stdin -- . ':!*.ttf' || echo clean` and `git log --format='%an <%ae>' | sort -u` (only `Zewify <dev@zewify.com>`).

- [ ] **Step 2: Create the repo and push**

```bash
gh repo create Zewify/portglimpse --public --description "See what's listening on your Mac's ports, by project, and stop it after asking." --homepage "https://zewify.com/portglimpse/" --disable-issues --disable-wiki
git remote add origin git@github.com:Zewify/portglimpse.git
git push -u origin main
```

Then check the Tests workflow: `gh run list --repo Zewify/portglimpse --limit 3` until it completes green; fix the runner label if it failed to start.

- [ ] **Step 3: Tag and release 1.0.0**

```bash
git tag v1.0.0 && git push origin v1.0.0
```

Watch the Release run, then check: `gh release view v1.0.0 --repo Zewify/portglimpse` lists the zip and `.sha256`, the author is `github-actions[bot]`.

- [ ] **Step 4: Install from the real release, into a scratch folder**

`PORTGLIMPSE_INSTALL_DIR=$(mktemp -d) PORTGLIMPSE_NO_LAUNCH=1 sh scripts/install.sh` — expect "installed 1.0.0", and `codesign -dv` on the result shows `Signature=adhoc` and no identity.

---

### Task 6: The install URL (outward — owner's go-ahead)

- [ ] **Step 1: Add the redirect on the web server**

In the zewify.com site's configuration on the web server (its location and how to reload it are in the owner's private notes), add a temporary redirect for `/portglimpse/install.sh` to `https://raw.githubusercontent.com/Zewify/portglimpse/main/scripts/install.sh`, placed before the site's static file serving.
Validate the configuration and reload it gracefully; never restart the server for this.

- [ ] **Step 2: Check it end to end**

`curl -fsSL https://zewify.com/portglimpse/install.sh | head -3` prints the installer's first lines.
`curl -fsSL https://zewify.com/portglimpse/install.sh | PORTGLIMPSE_INSTALL_DIR=$(mktemp -d) PORTGLIMPSE_NO_LAUNCH=1 sh` installs 1.0.0 into a scratch folder.

---

### Task 7: The PortGlimpse pages on zewify.com

Work in `~/Developer/personal/zewify` on a `feat/portglimpse` branch. Read its `CLAUDE.md` first.

**Files:** as listed under File Structure (zewify).

- [ ] **Step 1: Assets**

- `public/portglimpse/favicon.svg` — the app icon's tile as a vector, from `scripts/make-icon.swift` in the portglimpse repo (CG y-up geometry converted to SVG y-down):

```svg
<svg xmlns="http://www.w3.org/2000/svg" viewBox="100 100 824 824">
  <defs><linearGradient id="face" x1="0" y1="266" x2="0" y2="734" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#FFB067"/><stop offset="1" stop-color="#EE8237"/></linearGradient></defs>
  <rect x="100" y="100" width="824" height="824" rx="186" fill="#221E1B"/>
  <rect x="262" y="266" width="500" height="520" rx="110" fill="#B9531A"/>
  <rect x="262" y="266" width="500" height="468" rx="110" fill="url(#face)"/>
  <circle cx="512" cy="410" r="44" fill="#1B1815"/>
  <circle cx="512" cy="590" r="44" fill="#1B1815"/>
</svg>
```

- `scripts/source/portglimpse-icon-1024.png` — copy of the portglimpse repo's `App/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png`.
- `scripts/make-icons.mjs` — add, beside TickThock's: `products/portglimpse.png` (extract 100,100,824,824 from the 1024 source, resize 136), `portglimpse/favicon-32.png` and `portglimpse/apple-touch-icon.png` (from the SVG, with `rx="186"` → `rx="0"` for the touch icon).
- `scripts/make-og.mjs` — add a PortGlimpse share image in TickThock's style (same charcoal and amber glow, Bricolage), headline "See what's listening on your Mac's ports.", subline `zewify.com/portglimpse`, written to `public/portglimpse/og.png`.
- `public/portglimpse/shots/panel.png` and `window.png` — from Task 4's `build/shots/`.

Run `npm run icons`, and look at every output.

- [ ] **Step 2: Facts — `src/portglimpse/data.ts`**

```ts
/**
 * Facts for PortGlimpse's pages at zewify.com/portglimpse/.
 * Everything here describes the app as built in the portglimpse repo:
 *   behaviour  -> docs/superpowers/specs/2026-09-30-portglimpse-design.md, README.md
 *   install    -> scripts/install.sh; version -> project.yml MARKETING_VERSION
 *   storage    -> App/Sources (UserDefaults domain), Core OverrideStore.defaultURL
 *   network    -> App/Sources/UpdateChecker.swift (the only request the app makes)
 * `latestVersion` is the launch switch: null prints "Coming soon" and no install command.
 */
export const portglimpse = {
  name: 'PortGlimpse',
  tagline: 'See what’s listening on your Mac’s ports.',
  url: 'https://zewify.com',
  home: '/portglimpse/',
  latestVersion: '1.0.0' as string | null,
  pendingLabel: 'Coming soon',
  requirement: 'macOS 14 or later',
  installCommand: 'curl -fsSL https://zewify.com/portglimpse/install.sh | sh',
  repoUrl: 'https://github.com/Zewify/portglimpse',
  preferences: 'com.zewify.portglimpse',
  supportFolder: '~/Library/Application Support/PortGlimpse/',
  updateHost: 'api.github.com',
  policyUpdated: '30 September 2026',
} as const;

export const nav = [
  { href: '/portglimpse/', label: 'Overview' },
  { href: '/portglimpse/#install', label: 'Install' },
  { href: '/portglimpse/privacy/', label: 'Privacy' },
] as const;
```

- [ ] **Step 3: Layout and components**

- `src/portglimpse/layouts/Base.astro` — TickThock's `Base.astro` with PortGlimpse's data, favicon, og image, `<title>` suffix "PortGlimpse by Zewify", nav from `data.ts`, a masthead call to action `<a class="btn btn--small masthead__cta" href="/portglimpse/#install">Install</a>` (or the pending label when `latestVersion` is null), and footer note "Every port on your Mac, by project, for {requirement}. Made by <a href="/">Zewify</a>. Source on <a href={repoUrl}>GitHub</a>." It imports `../../tickthock/styles/global.css` (the shared look) and then `../styles/portglimpse.css`.
- `src/portglimpse/layouts/Doc.astro` — TickThock's `Doc.astro`, importing PortGlimpse's Base.
- `src/portglimpse/components/Logo.astro` — TickThock's Logo with `/portglimpse/favicon.svg`, "PortGlimpse", href `/portglimpse/`.
- `src/portglimpse/components/Shot.astro` — TickThock's Shot with names `panel` and `window` and their true pixel sizes from Task 4, images under `/portglimpse/shots/`.
- `src/portglimpse/components/InstallCommand.astro` — a `<figure class="install">` with the command in `<pre><code>` (selectable; no copy button, since the site has no inline scripts), and a caption "Run it again to update. Needs {requirement}." While `latestVersion` is null it renders `<p class="install install--pending">Coming soon</p>` instead.
- `src/portglimpse/styles/portglimpse.css` — only the `.install` block (mono, charcoal panel, amber prompt), in rem, with the reduced-motion and colour-scheme conventions of TickThock's stylesheet.
- zewify `CLAUDE.md` — add a "PortGlimpse at /portglimpse/" section: it reuses TickThock's stylesheet on purpose (shared design language), `data.ts` is the launch switch, screenshots come only from the app's demo mode via `scripts/capture-shots.sh` in the portglimpse repo, and `install.sh` is a Caddy redirect to the portglimpse repo, never a copy here.

- [ ] **Step 4: Pages**

`src/pages/portglimpse/index.astro` (TickThock's section classes: `hero`, `strip`, `section`, `feature`, `band`, `band--cta`):

- Hero: eyebrow "A menu bar app for Mac"; h1 = tagline; lead "PortGlimpse lists every server listening on your Mac, with the command that started it and the project folder it runs in. Stop one in two clicks, always after it asks."; `<InstallCommand />`; note "Free and open source, for {requirement}."; the panel shot, alt "PortGlimpse's panel: Dev servers next dev on :3000 in ~/Developer/shop/web, vite on :5173, granian asgi on :8000 with 2 workers, postgres on :5432 and redis-server on :6379, with Apps & system collapsed."
- Strip (3): "By project" / "Each port shows its command and folder, not just node."; "Asks before it stops anything" / "Kill always confirms, and a stubborn server gets Force kill."; "Always on top, if you like" / "Pop the list out into a small window that floats over your editor."
- Section "Every server, by project" (feature with the panel shot): Dev servers first; apps and macOS services collapsed under Apps & system; ports owned by root or other users view only, under Show all users' ports; a server's workers fold into its row ("1 worker"); right-click to always show a program as a dev server or hide it.
- Section "Stopping a server": Kill asks "Kill next dev on :3000?"; it sends a graceful stop and waits 3 seconds; if the server is still running, Force kill, which asks again; other users' processes can never be stopped.
- Section "A window that stays on top" (feature with the window shot): stays over other apps, on every desktop and over full-screen apps; drag it by its header, resize it; narrower than 360 points the rows go compact; it remembers where you left it.
- Section `id="install"` "Install, update, uninstall": `<InstallCommand />`; it installs to /Applications, or ~/Applications when your account cannot write there, and never asks for your password; run it again to update, and the menu tells you when an update is out; to uninstall: turn off Settings → Launch at login, quit PortGlimpse, delete the app, `{supportFolder}` and `~/Library/Preferences/{preferences}.plist`. A short note: PortGlimpse is installed with this command, not from a download link, and "the app is open source on GitHub" linking `repoUrl`.
- Band "Privacy": it reads the list of listening ports and process details from macOS, on your Mac; it sends none of it anywhere; the only network request is an optional daily check for a newer release at {updateHost}, which you can turn off in Settings; link to `/portglimpse/privacy/`.
- CTA band with the icon, "Know what's on your ports", `<InstallCommand />`.

`src/pages/portglimpse/privacy.astro` (Doc): sections In short; What it reads (ports and process details from the kernel, for the panel only, never stored); The network (one optional daily request to `https://{updateHost}/repos/Zewify/portglimpse/releases/latest`; GitHub sees an IP address and a user agent under its own privacy policy; turn off in Settings → Check for updates; the installer contacts the same host); What stays on your Mac (preferences `{preferences}`, overrides in `{supportFolder}overrides.json`); Deleting everything (the uninstall steps); Changes; Contact (`company.supportEmail`). Dated `{policyUpdated}`.

- [ ] **Step 5: The rest of the site**

- `src/data/site.ts` — add `'portglimpse'` to `Product['slug']` and a product entry after TickThock: name, url `home`, status and label from `latestVersion` ("Available now" / "Coming soon"), oneLiner = tagline, facts ["Each port shown with the command and project folder behind it", "Stop a server in two clicks, always after asking", "Free and open source, installed with one command"], platforms "macOS menu bar", icon `/products/portglimpse.png`, privacyUrl `/portglimpse/privacy/`, supportUrl `null`; list it in the header comment.
- `src/pages/index.astro` description, `terms.astro`, `contact.astro` and `privacy.astro` — add PortGlimpse wherever the products are listed; `privacy.astro` gets a short PortGlimpse section in the style of TickThock's, linking its policy; `contact.astro` says PortGlimpse questions go to the support address.
- `tests/dist.test.mjs` — add `PORTGLIMPSE_ROUTES = ['portglimpse/index.html', 'portglimpse/privacy/index.html']` and the assets (`products/portglimpse.png`, `portglimpse/og.png`, `portglimpse/favicon.svg`) to the build test; allow `^https:\/\/github\.com\/Zewify\/portglimpse\/?$` in `ALLOWED_EXTERNAL`; exclude `portglimpse/` from the Zewify-stylesheet test the way `tickthock/` is; add a test that the overview prints the exact install command when `latestVersion` is set and never links a `.zip`; extend the true-size `<img>` test to `/portglimpse/shots/`.

- [ ] **Step 6: Verify and look**

Run `npm run verify` (exit 0). Run `npm run dev` and check `/portglimpse/`, `/portglimpse/privacy/` and the home page at 2560 and 390 wide, light and dark: masthead, install box, both shots at true size, the home card with PortGlimpse's icon, and every anchor (`#install`) landing clear of the masthead.

- [ ] **Step 7: Commit, merge, deploy (outward — owner's go-ahead)**

```bash
git add -A && git commit -m "Add PortGlimpse's pages and home card"
git switch main && git merge --ff-only feat/portglimpse && git branch -d feat/portglimpse
git push origin main
gh run list --limit 3   # confirm the deploy run for this SHA succeeded
```

Then `curl -fsSI https://zewify.com/portglimpse/` is 200, and the page shows the install command.

---

### Task 8: End to end

- [ ] **Step 1: Install like a visitor**

Quit PortGlimpse, then run exactly `curl -fsSL https://zewify.com/portglimpse/install.sh | sh` on this Mac.
Expect "installed 1.0.0 in /Applications", the app launching, and the menu bar icon.
`codesign -dv /Applications/PortGlimpse.app 2>&1 | grep Signature` shows `adhoc`.

- [ ] **Step 2: Record what is now true**

Update `~/Developer/personal/CLAUDE.md`'s portglimpse section (published, released, how to release: bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, merge, tag `v<version>`, push the tag) and the server table (the `/portglimpse/install.sh` redirect).
