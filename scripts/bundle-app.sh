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

# Ad-hoc sign the assembled bundle. `swift build` linker-signs the bare
# executable, which then expects sealed bundle resources; copying it into the
# .app without re-signing leaves an INVALID signature (no _CodeSignature) that
# fails `codesign --verify`. That broken signature breaks Gatekeeper (download
# shows "damaged") AND Accessibility/TCC matching (permission granted in System
# Settings never applies to the running process). A bundle-level ad-hoc sign
# produces a valid, consistent identity (Identifier from CFBundleIdentifier).
# Note: ad-hoc is not notarized — downloaded DMGs still need notarization or the
# `xattr -dr com.apple.quarantine` workaround to clear Gatekeeper.
echo "Signing ${APP_NAME} (ad-hoc)..."
codesign --force --sign - "$APP_DIR"

echo "Done: ${APP_DIR}"
