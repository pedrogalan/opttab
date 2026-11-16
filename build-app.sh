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
cp "App/menu-bar-icon.png" "$APP_BUNDLE/Contents/Resources/menu-bar-icon.png"

# Build the app icon (Finder, Dock, About) from the source PNG.
if [ -f "App/AppIcon.png" ]; then
  ICONSET_DIR="$(mktemp -d)"
  ICONSET="${ICONSET_DIR}/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "App/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "App/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET_DIR"
fi

# Ad-hoc sign so macOS treats the bundle consistently for permissions.
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "Done: ${APP_BUNDLE}"
echo "Run it from Finder, or: open ${APP_BUNDLE}"
