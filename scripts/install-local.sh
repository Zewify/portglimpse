#!/usr/bin/env bash
# Builds Release, replaces /Applications/PortGlimpse.app with it, and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."
app="$(./scripts/build.sh Release | tail -1)"
osascript -e 'quit app "PortGlimpse"' >/dev/null 2>&1 || true
rm -rf "/Applications/PortGlimpse.app"
ditto "$app" "/Applications/PortGlimpse.app"
open "/Applications/PortGlimpse.app"
echo "Installed /Applications/PortGlimpse.app"
