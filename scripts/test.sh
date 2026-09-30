#!/usr/bin/env bash
# Runs the core tests. Task 9 adds the app build.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd Core && swift test --quiet)
