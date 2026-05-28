#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-release}"
APP_NAME="Winch.app"
BUILD_DIR=".build/${CONFIG}"
APP_DIR="${BUILD_DIR}/${APP_NAME}"

echo "Building winch ($CONFIG)..."
swift build -c "$CONFIG"

echo "Assembling ${APP_NAME}..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "${BUILD_DIR}/winch" "$APP_DIR/Contents/MacOS/winch"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "Done: ${APP_DIR}"
