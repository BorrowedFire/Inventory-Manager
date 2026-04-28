#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$(mktemp -d /tmp/inventory-manager-notarized.XXXXXX)}"
DIST_DIR="$ROOT/dist"
APP_NAME="Inventory Manager.app"
ZIP_NAME="InventoryManager-macOS.zip"
NOTARY_SUBMISSION_ZIP="$BUILD_DIR/InventoryManager-notary-submission.zip"

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION, e.g. Developer ID Application: Name (TEAMID)}"

if ! security find-identity -v -p codesigning | grep -Fq "\"$DEVELOPER_ID_APPLICATION\""; then
  echo "error: Developer ID Application identity not found in the current keychain search list: $DEVELOPER_ID_APPLICATION" >&2
  exit 1
fi

if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
  : "${APPLE_ID:?Set APPLE_ID for notarytool, or set NOTARYTOOL_PROFILE}"
  : "${APP_SPECIFIC_PASSWORD:?Set APP_SPECIFIC_PASSWORD for notarytool, or set NOTARYTOOL_PROFILE}"
  : "${TEAM_ID:?Set TEAM_ID for notarytool, or set NOTARYTOOL_PROFILE}"
fi

cd "$ROOT"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

clean_extended_attributes() {
  local path="$1"
  /usr/bin/xattr -cr "$path" 2>/dev/null || true
  /usr/bin/xattr -crs "$path" 2>/dev/null || true
  /usr/bin/find "$path" -exec /usr/bin/xattr -c {} \; 2>/dev/null || true
}

xcodegen generate
xcodebuild \
  -project InventoryManager.xcodeproj \
  -scheme InventoryManager \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  ENABLE_HARDENED_RUNTIME=YES \
  build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME"
clean_extended_attributes "$APP_PATH"
codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP_PATH"
codesign --verify --deep --strict --verbose=4 "$APP_PATH"

rm -f "$NOTARY_SUBMISSION_ZIP" "$DIST_DIR/$ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_SUBMISSION_ZIP"
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  xcrun notarytool submit "$NOTARY_SUBMISSION_ZIP" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
else
  xcrun notarytool submit "$NOTARY_SUBMISSION_ZIP" --apple-id "$APPLE_ID" --password "$APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID" --wait
fi
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=4 "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$DIST_DIR/$ZIP_NAME"

echo "Notarized app: $APP_PATH"
echo "Notarized zip: $DIST_DIR/$ZIP_NAME"
