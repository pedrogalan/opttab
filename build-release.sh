#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="OptTab"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' App/Info.plist)
# The bundle is always named OptTab.app; the version lives in Info.plist (shown in
# About) and in the archive filename, never in the bundle name that macOS displays.
APP_BUNDLE="dist/${APP_NAME}.app"
ARCHIVE="dist/${APP_NAME}-${VERSION}-macos-universal.zip"
BUILD_DIR=".build/release-universal"

echo "Building arm64 release binary…"
swift build -c release --triple arm64-apple-macosx13.0 --scratch-path .build/release-arm64

echo "Building x86_64 release binary…"
swift build -c release --triple x86_64-apple-macosx13.0 --scratch-path .build/release-x86_64

mkdir -p "$BUILD_DIR" dist
lipo -create \
  .build/release-arm64/out/Products/Release/"$APP_NAME" \
  .build/release-x86_64/out/Products/Release/"$APP_NAME" \
  -output "$BUILD_DIR/$APP_NAME"

OPTTAB_BINARY="$BUILD_DIR/$APP_NAME" ./build-app.sh "$APP_BUNDLE"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"

echo "Created universal app: $APP_BUNDLE"
echo "Created release archive: $ARCHIVE"
