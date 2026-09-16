#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

DIST="$PWD/dist"
BUILD_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/portkeeper-build.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/Portkeeper.app"
ICONSET="$BUILD_DIR/icon.iconset"
mkdir -p "$DIST"
rm -rf "$DIST/Portkeeper.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/.module-cache"
export SWIFT_MODULE_CACHE_PATH="$BUILD_DIR/.module-cache"

cp Sources/Info.plist "$APP/Contents/Info.plist"
cp Sources/Portkeeper-setup.md "$APP/Contents/Resources/Portkeeper-setup.md"
swiftc -swift-version 5 -target arm64-apple-macos14.0 -O \
  Sources/PortkeeperApp.swift Sources/PortkeeperModel.swift Sources/ProjectHandoff.swift \
  Sources/PortkeeperAlerts.swift Sources/PortkeeperIdentity.swift \
  Sources/PortkeeperMenuBar.swift Sources/PortkeeperPages.swift \
  -o "$APP/Contents/MacOS/Portkeeper"
clang -O2 Sources/runner.c -o "$APP/Contents/Resources/portkeeper-runner"
swift scripts/draw-menubar.swift "$APP/Contents/Resources/MenuBarIcon.png"

for dimension in 16 32 128 256 512; do
  sips -s format png -z "$dimension" "$dimension" Assets/harbour-signal-icon.png \
    --out "$ICONSET/icon_${dimension}x${dimension}.png" >/dev/null
  doubled=$((dimension * 2))
  sips -s format png -z "$doubled" "$doubled" Assets/harbour-signal-icon.png \
    --out "$ICONSET/icon_${dimension}x${dimension}@2x.png" >/dev/null
done
python3 scripts/make-icns.py "$ICONSET" "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP"
rm -f "$DIST/Portkeeper.zip"
(cd "$BUILD_DIR" && zip -qr -X "$DIST/Portkeeper.zip" Portkeeper.app)
echo "$DIST/Portkeeper.zip"
