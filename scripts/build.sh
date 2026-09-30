#!/usr/bin/env bash
# Generates the Xcode project and builds PortGlimpse.app; prints the app's path.
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-Debug}"
xcodegen generate --quiet
xcodebuild -project PortGlimpse.xcodeproj -scheme PortGlimpse -configuration "$configuration" \
  -derivedDataPath build/DerivedData -quiet build
echo "build/DerivedData/Build/Products/$configuration/PortGlimpse.app"
