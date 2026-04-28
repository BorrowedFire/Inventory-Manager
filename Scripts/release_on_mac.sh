#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-}"
BUILD="${2:-}"
REPO="${REPO:-BorrowedFire/Inventory-Manager}"

if [[ -z "$VERSION" || -z "$BUILD" ]]; then
  echo "usage: Scripts/release_on_mac.sh <version> <build>" >&2
  exit 1
fi

: "${DEVELOPER_ID_APPLICATION:?Set DEVELOPER_ID_APPLICATION, e.g. Developer ID Application: Example LLC (TEAMID)}"
if [[ -z "${NOTARYTOOL_PROFILE:-}" ]]; then
  : "${APPLE_ID:?Set APPLE_ID for notarytool, or set NOTARYTOOL_PROFILE}"
  : "${APP_SPECIFIC_PASSWORD:?Set APP_SPECIFIC_PASSWORD for notarytool, or set NOTARYTOOL_PROFILE}"
  : "${TEAM_ID:?Set TEAM_ID for notarization, or set NOTARYTOOL_PROFILE}"
fi

cd "$ROOT"

python3 - "$VERSION" "$BUILD" <<'PY'
from pathlib import Path
import re, sys
version, build = sys.argv[1:]
p = Path('project.yml')
s = p.read_text()
s = re.sub(r'MARKETING_VERSION: .*', f'MARKETING_VERSION: {version}', s)
s = re.sub(r'CURRENT_PROJECT_VERSION: .*', f'CURRENT_PROJECT_VERSION: {build}', s)
p.write_text(s)
PY

Scripts/ci_check.sh
Scripts/rehearse_sparkle_release.sh
Scripts/notarize_release.sh
VERSION="$VERSION" BUILD="$BUILD" Scripts/make_appcast.sh dist/InventoryManager-macOS.zip dist/appcast.xml

TAG="v$VERSION"
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Uploading/replacing assets."
  gh release upload "$TAG" dist/InventoryManager-macOS.zip dist/appcast.xml --repo "$REPO" --clobber
else
  gh release create "$TAG" dist/InventoryManager-macOS.zip dist/appcast.xml \
    --repo "$REPO" \
    --title "Inventory Manager $VERSION" \
    --notes "Inventory Manager $VERSION public release."
fi

echo "Published $TAG with Sparkle appcast assets."
