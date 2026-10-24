#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
APP_NAME="Portkeeper"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw Sources/Info.plist)"
ARCH="$(uname -m)"
INPUT="${1:-$PWD/dist/$APP_NAME.zip}"
OUTPUT="${2:-$PWD/dist/$APP_NAME-$VERSION-$ARCH-development.dmg}"
[[ -f "$INPUT" ]] || { print -u2 "Build the app first: zsh build.sh"; exit 1; }
INPUT="${INPUT:A}"
OUTPUT="${OUTPUT:A}"
[[ ! -e "$OUTPUT" ]] || { print -u2 "Output already exists: $OUTPUT"; exit 1; }
TASK_DMG=$(mktemp -d "${TMPDIR:-/private/tmp}/installer-build.XXXXXX")
trap 'rm -rf "$TASK_DMG"' EXIT
# Unpack the release ZIP to preserve the already-reviewed app and its signature.
ditto -xk "$INPUT" "$TASK_DMG/input"
APP="$TASK_DMG/input/$APP_NAME.app"
[[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")" == "$VERSION" ]] || { print -u2 "Archive version does not match the release version"; exit 1; }
codesign --verify --deep --strict "$APP"
DMGBUILD="${DMGBUILD:-}"
if [[ -z "$DMGBUILD" ]]; then
  python3 -m venv "$TASK_DMG/tools"
  "$TASK_DMG/tools/bin/python" -m pip install --disable-pip-version-check -r scripts/dmg-requirements.txt
  DMGBUILD="$TASK_DMG/tools/bin/dmgbuild"
fi
mkdir -p "${OUTPUT:h}"
"$DMGBUILD" -s scripts/dmg-settings.py -D "root=$PWD" -D "app=$APP" "$APP_NAME Installer" "$OUTPUT"
hdiutil verify "$OUTPUT"
"${DMGBUILD:h}/python" scripts/check-dmg.py "$OUTPUT" "$INPUT" "$APP_NAME"
print "Created $OUTPUT"
