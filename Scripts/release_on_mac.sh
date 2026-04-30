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

git fetch origin main --tags >/dev/null

if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "error: releases must be cut from main." >&2
  exit 1
fi

if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "error: local main must match origin/main before publishing a release." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "error: tracked files must be clean before publishing a release. Commit the version bump first." >&2
  exit 1
fi

python3 - "$VERSION" "$BUILD" <<'PY'
from pathlib import Path
import re, sys
version, build = sys.argv[1:]
p = Path('project.yml')
s = p.read_text()
actual_version = re.search(r'MARKETING_VERSION:\s*(\S+)', s)
actual_build = re.search(r'CURRENT_PROJECT_VERSION:\s*(\S+)', s)
if not actual_version or actual_version.group(1) != version:
    raise SystemExit(f"error: project.yml MARKETING_VERSION must already be {version}")
if not actual_build or actual_build.group(1) != build:
    raise SystemExit(f"error: project.yml CURRENT_PROJECT_VERSION must already be {build}")
PY

Scripts/ci_check.sh
Scripts/rehearse_sparkle_release.sh
Scripts/notarize_release.sh
VERSION="$VERSION" BUILD="$BUILD" Scripts/make_appcast.sh dist/InventoryManager-macOS.zip dist/appcast.xml

TAG="v$VERSION"
HEAD_SHA="$(git rev-parse HEAD)"
REMOTE_TAG_SHA="$(git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}" | awk 'END { print $1 }')"
if [[ -n "$REMOTE_TAG_SHA" && "$REMOTE_TAG_SHA" != "$HEAD_SHA" ]]; then
  echo "error: remote tag $TAG already points at $REMOTE_TAG_SHA, not current HEAD $HEAD_SHA." >&2
  exit 1
fi

if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Release $TAG already exists. Uploading/replacing assets."
  gh release upload "$TAG" dist/InventoryManager-macOS.zip dist/appcast.xml --repo "$REPO" --clobber
else
  gh release create "$TAG" dist/InventoryManager-macOS.zip dist/appcast.xml \
    --repo "$REPO" \
    --target "$HEAD_SHA" \
    --title "Inventory Manager $VERSION" \
    --notes "Inventory Manager $VERSION public release."
fi

echo "Published $TAG with Sparkle appcast assets."
