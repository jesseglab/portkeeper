#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
TEST_BUILD="$PWD/dist/TerminalTests.app"
TEST_SOURCE=$(mktemp -d "${TMPDIR:-/private/tmp}/portkeeper-test-source.XXXXXX")
trap 'rm -rf "$TEST_SOURCE"' EXIT
ditto --norsrc Sources "$TEST_SOURCE/Sources"
ditto --norsrc Tests "$TEST_SOURCE/Tests"
mkdir -p "$TEST_BUILD/Contents/MacOS" "$TEST_BUILD/Contents/Resources"
cat > "$TEST_BUILD/Contents/Info.plist" <<'PLIST'
<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>ai.portkeeper.terminal-tests</string><key>CFBundleName</key><string>Portkeeper Terminal Tests</string><key>CFBundleExecutable</key><string>TerminalTests</string><key>CFBundlePackageType</key><string>APPL</string></dict></plist>
PLIST
source scripts/notchwork-dependency.sh
prepare_notchwork "$TEST_SOURCE"
if [[ -z "${NOTCHWORK_PACKAGE_PATH:-}" ]]; then
  cp Package.swift "$TEST_SOURCE/"
  swift package --package-path "$TEST_SOURCE" resolve
  export NOTCHWORK_PACKAGE_PATH="$TEST_SOURCE/.build/checkouts/notchwork"
fi
swift build -c debug --product NotchworkKit --package-path "$NOTCHWORK_PACKAGE_PATH" --scratch-path "$TEST_SOURCE/sdk-build" -Xswiftc -enable-testing
SDK_BIN=$(swift build -c debug --package-path "$NOTCHWORK_PACKAGE_PATH" --scratch-path "$TEST_SOURCE/sdk-build" --show-bin-path)
swiftc -I "$SDK_BIN/Modules" -L "$SDK_BIN" -lNotchworkKit -O -D PORTKEEPER_TEST -swift-version 5 -target arm64-apple-macos14.0 -module-cache-path /tmp/portkeeper-test-module-cache "$TEST_SOURCE"/Sources/*.swift "$TEST_SOURCE"/Tests/*.swift -o "$TEST_BUILD/Contents/MacOS/TerminalTests"
if [[ -f dist/Portkeeper.app/Contents/Resources/AppIcon.icns ]]; then
  cp dist/Portkeeper.app/Contents/Resources/AppIcon.icns "$TEST_BUILD/Contents/Resources/AppIcon.icns"
fi
clang -DPORTKEEPER_TEST -O2 Sources/runner.c -o "$TEST_BUILD/Contents/Resources/portkeeper-runner"
if [[ "${1:-}" == "--build-only" ]]; then
  exit 0
elif [[ "${1:-}" == "--preview" ]]; then
  open -n "$TEST_BUILD" --args --preview
else
  "$TEST_BUILD/Contents/MacOS/TerminalTests"
fi
