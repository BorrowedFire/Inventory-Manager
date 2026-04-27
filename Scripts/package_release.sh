#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/release"
DIST_DIR="$ROOT/dist"
APP_NAME="Inventory Manager.app"
ZIP_NAME="InventoryManager-macOS.zip"

cd "$ROOT"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required. Install with: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate
xcodebuild \
  -project InventoryManager.xcodeproj \
  -scheme InventoryManager \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  build

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: expected app not found at $APP_PATH" >&2
  exit 1
fi

rm -f "$DIST_DIR/$ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$DIST_DIR/$ZIP_NAME"

cat <<EOF
Packaged: $DIST_DIR/$ZIP_NAME

Note: this is a locally signed build. For public/team distribution without Gatekeeper warnings,
sign with a Developer ID Application certificate and notarize the zip with Apple before sharing.
EOF
