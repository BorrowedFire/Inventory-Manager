#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
APP_PATH="${1:-$DIST_DIR/Inventory Manager.app}"
DMG_PATH="${2:-$DIST_DIR/InventoryManager-macOS.dmg}"
VOLUME_NAME="Inventory Manager"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found at $APP_PATH" >&2
  echo "Run Scripts/package_release.sh first, or pass the .app path as the first argument." >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "$VOLUME_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"
echo "DMG created: $DMG_PATH"
