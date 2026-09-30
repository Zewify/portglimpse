#!/usr/bin/env bash
# Fails unless the tag (v1.2.3) equals MARKETING_VERSION in project.yml.
set -euo pipefail
cd "$(dirname "$0")/.."
tag="${1:?usage: check-version.sh v<version>}"
version=$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' project.yml | head -n 1)
[ "$tag" = "v$version" ] || { echo "Tag $tag does not match MARKETING_VERSION $version in project.yml" >&2; exit 1; }
echo "$version"
