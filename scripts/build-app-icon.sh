#!/usr/bin/env bash
set -euo pipefail

BUILD_DIR=".build"
ICONSET="${BUILD_DIR}/AppIcon.iconset"
SOURCE_PNG="${BUILD_DIR}/AppIcon-1024.png"
OUTPUT="Resources/AppIcon.icns"

echo "Rendering source 1024 PNG..."
mkdir -p "$BUILD_DIR"
swift scripts/render-app-icon.swift "$SOURCE_PNG"

echo "Building iconset..."
rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# Apple's required filenames for iconutil:
sips -z 16   16   "$SOURCE_PNG" --out "$ICONSET/icon_16x16.png"        >/dev/null
sips -z 32   32   "$SOURCE_PNG" --out "$ICONSET/icon_16x16@2x.png"     >/dev/null
sips -z 32   32   "$SOURCE_PNG" --out "$ICONSET/icon_32x32.png"        >/dev/null
sips -z 64   64   "$SOURCE_PNG" --out "$ICONSET/icon_32x32@2x.png"     >/dev/null
sips -z 128  128  "$SOURCE_PNG" --out "$ICONSET/icon_128x128.png"      >/dev/null
sips -z 256  256  "$SOURCE_PNG" --out "$ICONSET/icon_128x128@2x.png"   >/dev/null
sips -z 256  256  "$SOURCE_PNG" --out "$ICONSET/icon_256x256.png"      >/dev/null
sips -z 512  512  "$SOURCE_PNG" --out "$ICONSET/icon_256x256@2x.png"   >/dev/null
sips -z 512  512  "$SOURCE_PNG" --out "$ICONSET/icon_512x512.png"      >/dev/null
sips -z 1024 1024 "$SOURCE_PNG" --out "$ICONSET/icon_512x512@2x.png"   >/dev/null

echo "Packaging .icns..."
mkdir -p Resources
iconutil --convert icns "$ICONSET" --output "$OUTPUT"

echo "Done: $OUTPUT"
