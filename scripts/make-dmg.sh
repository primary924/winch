#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-release}"
APP_NAME="Winch.app"
BUILD_DIR=".build/${CONFIG}"
APP_PATH="${BUILD_DIR}/${APP_NAME}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: $APP_PATH not found. Run 'make app' first." >&2
    exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DMG_NAME="Winch-${VERSION}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"

STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR"' EXIT

echo "Staging DMG contents..."
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

echo "Building ${DMG_NAME}..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "Winch" \
    -srcfolder "$STAGE_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

echo "Done: ${DMG_PATH}"
