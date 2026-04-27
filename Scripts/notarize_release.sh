#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/notarized"
DIST_DIR="$ROOT/dist"
APP_NAME="Inventory Manager.app"
ZIP_NAME="InventoryManager-macOS-notarized.zip"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION, e.g. Developer ID Application: Name (TEAMID)}"
: "${APPLE_ID:?Set APPLE_ID for notarytool}"
: "${APP_SPECIFIC_PASSWORD:?Set APP_SPECIFIC_PASSWORD for notarytool}"
: "${TEAM_ID:?Set TEAM_ID for notarytool}"

cd "$ROOT"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

xcodegen generate
xcodebuild \
  -project InventoryManager.xcodeproj \
  -scheme InventoryManager \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="$DEVELOPER_ID_APPLICATION" \
  build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME"
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"

rm -f "$DIST_DIR/$ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$DIST_DIR/$ZIP_NAME"
xcrun notarytool submit "$DIST_DIR/$ZIP_NAME" --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID" --wait
xcrun stapler staple "$APP_PATH"

echo "Notarized app: $APP_PATH"
echo "Notarized zip: $DIST_DIR/$ZIP_NAME"
