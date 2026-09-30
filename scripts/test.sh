#!/usr/bin/env bash
# Runs the core tests and the installer tests, then builds the app so a compile error anywhere fails the run.
set -euo pipefail
cd "$(dirname "$0")/.."
(cd Core && swift test --quiet)
./scripts/test-install.sh
./scripts/build.sh Debug >/dev/null
