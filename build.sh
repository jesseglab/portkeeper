#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

python3 scripts/check-release-privacy.py

DIST="$PWD/dist"
BUILD_DIR=$(mktemp -d "${TMPDIR:-/private/tmp}/portkeeper-build.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT
APP="$BUILD_DIR/Portkeeper.app"
ICONSET="$BUILD_DIR/icon.iconset"
mkdir -p "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$ICONSET"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/.module-cache"
export SWIFT_MODULE_CACHE_PATH="$BUILD_DIR/.module-cache"

cp Sources/Info.plist "$APP/Contents/Info.plist"
cp Sources/Portkeeper-setup.md "$APP/Contents/Resources/Portkeeper-setup.md"
source scripts/notchwork-dependency.sh
prepare_notchwork "$BUILD_DIR"
mkdir -p "$BUILD_DIR/project"
cp Package.swift "$BUILD_DIR/project/"
ditto --norsrc Sources "$BUILD_DIR/project/Sources"
swift build -c release --product Portkeeper --package-path "$BUILD_DIR/project" --scratch-path "$BUILD_DIR/build"
BIN_DIR=$(swift build -c release --package-path "$BUILD_DIR/project" --scratch-path "$BUILD_DIR/build" --show-bin-path)
cp "$BIN_DIR/Portkeeper" "$APP/Contents/MacOS/Portkeeper"
NOTCHWORK_RESOLVED="${NOTCHWORK_PACKAGE_PATH:-$BUILD_DIR/build/checkouts/notchwork}"
mkdir -p "$APP/Contents/Resources/Notchwork"
cp "$NOTCHWORK_RESOLVED/LICENSE" "$NOTCHWORK_RESOLVED/NOTICE" "$APP/Contents/Resources/Notchwork/"
sips -s format png -z 64 64 Assets/Porty/porty-icon-v2.png --out "$APP/Contents/Resources/Porty.png" >/dev/null
clang -O2 Sources/runner.c -o "$APP/Contents/Resources/portkeeper-runner"

for dimension in 16 32 128 256 512; do
  sips -s format png -z "$dimension" "$dimension" Assets/Porty/porty-icon-v2.png \
    --out "$ICONSET/icon_${dimension}x${dimension}.png" >/dev/null
  doubled=$((dimension * 2))
  sips -s format png -z "$doubled" "$doubled" Assets/Porty/porty-icon-v2.png \
    --out "$ICONSET/icon_${dimension}x${dimension}@2x.png" >/dev/null
done
python3 scripts/make-icns.py "$ICONSET" "$APP/Contents/Resources/AppIcon.icns"
python3 scripts/check-release-privacy.py "$APP"
xattr -cr "$APP"
codesign --force --deep --sign - "$APP" >/dev/null
codesign --verify --deep --strict "$APP"
rm -f "$DIST/Portkeeper.zip"
(cd "$BUILD_DIR" && zip -qr -X "$DIST/Portkeeper.zip" Portkeeper.app)
rm -rf "$DIST/Portkeeper.app"
ditto --norsrc "$APP" "$DIST/Portkeeper.app"
xattr -cr "$DIST/Portkeeper.app"
codesign --verify --deep --strict "$DIST/Portkeeper.app"
echo "$DIST/Portkeeper.zip"
