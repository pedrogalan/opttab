#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="OptTab"
APP_BUNDLE="${1:-dist/${APP_NAME}.app}"
APP_BINARY="${OPTTAB_BINARY:-.build/release/${APP_NAME}}"

if [ -z "${OPTTAB_BINARY:-}" ]; then
  echo "Building release binary…"
  swift build -c release
fi

echo "Creating ${APP_BUNDLE}…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$APP_BINARY" "$APP_BUNDLE/Contents/MacOS/${APP_NAME}"
cp "App/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "App/menu-bar-icon.png" "$APP_BUNDLE/Contents/Resources/menu-bar-icon.png"

# Include the ready-to-use ICNS asset so packaging does not depend on iconutil.
if [ ! -s "App/AppIcon.icns" ]; then
  echo "Error: App/AppIcon.icns is missing; cannot build an app without its icon." >&2
  exit 1
fi
cp "App/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Ad-hoc sign so macOS treats the bundle consistently for permissions.
codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true

echo "Done: ${APP_BUNDLE}"
echo "Run it from Finder, or: open ${APP_BUNDLE}"
