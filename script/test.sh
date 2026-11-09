#!/bin/bash
# Run the XCTest suite with Xcode 27's toolchain (xcode-select may point elsewhere).
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.0.0.app/Contents/Developer}"
exec swift test "$@"
