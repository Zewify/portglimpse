#!/usr/bin/env bash
# Builds Release (universal, ad hoc signed) and writes the release assets to build/release/.
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml | head -n 1)
app="$(./scripts/build.sh Release | tail -1)"
archs=$(lipo -archs "$app/Contents/MacOS/PortGlimpse")
for arch in arm64 x86_64; do echo "$archs" | grep -qw "$arch" || { echo "Not a universal binary: $archs" >&2; exit 1; }; done
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
# What's new, when this version has notes of its own.
if [ -f "docs/releases/$version.md" ]; then
  { printf '\n## What'"'"'s new\n\n'; cat "docs/releases/$version.md"; } >> "$out/notes.md"
fi
echo "$out/$zip"
