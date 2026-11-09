#!/bin/bash
# Run the XCTest suite with the newest Xcode's toolchain (xcode-select may
# point elsewhere; see script/xcode-env.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
source script/xcode-env.sh
exec swift test "$@"
