#!/bin/bash
# Run the XCTest suite. Prefers `swift test`; if SwiftPM can't use XCTest
# (e.g. the Xcode license hasn't been accepted), builds the tests and runs
# them with a small in-process runner instead.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-27.0.0.app/Contents/Developer}"

if out=$(swift test "$@" 2>&1); then
  echo "$out" | tail -5
  exit 0
elif ! grep -q "XCTest not available" <<<"$out"; then
  echo "$out"
  exit 1
fi

echo "swift test can't launch XCTest here; using script/testrunner." >&2
swift build --build-tests >/dev/null
PLATFORM="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer"
RUNNER=.build/testrunner
if [[ ! -x $RUNNER || script/testrunner/main.swift -nt $RUNNER ]]; then
  "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" -O -sdk "$PLATFORM/SDKs/MacOSX.sdk" -F "$PLATFORM/Library/Frameworks" -framework XCTest \
    -Xlinker -rpath -Xlinker "$PLATFORM/Library/Frameworks" \
    -Xlinker -rpath -Xlinker "$PLATFORM/usr/lib" \
    script/testrunner/main.swift -o "$RUNNER"
fi
"$RUNNER" .build/debug/GlanceCoreTests.xctest "${1:-}"
