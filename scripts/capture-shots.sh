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
