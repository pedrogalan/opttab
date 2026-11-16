#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="CmdTab"
APP_BUNDLE="dist/${APP_NAME}.app"

echo "Building release binary…"
swift build -c release

echo "Creating ${APP_BUNDLE}…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/release/${APP_NAME}" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Ad-hoc sign so macOS treats the bundle consistently for permissions.
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "Done: ${APP_BUNDLE}"
echo "Run it from Finder, or: open ${APP_BUNDLE}"
