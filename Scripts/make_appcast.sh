#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT/dist"
ZIP_PATH="${1:-$DIST_DIR/InventoryManager-macOS.zip}"
APPCAST_PATH="${2:-$DIST_DIR/appcast.xml}"
DOWNLOAD_URL="${DOWNLOAD_URL:-https://github.com/BorrowedFire/Inventory-Manager/releases/latest/download/InventoryManager-macOS.zip}"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
PUB_DATE="${PUB_DATE:-$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S %z')}"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "error: zip not found at $ZIP_PATH" >&2
  echo "Run Scripts/package_release.sh first, or pass the zip path as the first argument." >&2
  exit 1
fi

SPARKLE_BIN="${SPARKLE_BIN:-}"
if [[ -z "$SPARKLE_BIN" ]]; then
  SPARKLE_BIN=$(find \
    "$ROOT/.build" \
    "$ROOT/build" \
    "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update' \
    -type f 2>/dev/null | head -1 || true)
fi
if [[ -z "$SPARKLE_BIN" || ! -x "$SPARKLE_BIN" ]]; then
  echo "error: Sparkle sign_update tool not found. Resolve packages or build once after adding Sparkle, then rerun." >&2
  exit 1
fi

SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-com.inventorymanager.app}"
SIGNATURE_OUTPUT=$("$SPARKLE_BIN" --account "$SPARKLE_KEY_ACCOUNT" "$ZIP_PATH")
ED_SIGNATURE=$(printf "%s\n" "$SIGNATURE_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -1)
LENGTH=$(stat -f%z "$ZIP_PATH")

if [[ -z "$ED_SIGNATURE" ]]; then
  echo "error: could not parse Sparkle signature from sign_update output" >&2
  printf "%s\n" "$SIGNATURE_OUTPUT" >&2
  exit 1
fi

mkdir -p "$(dirname "$APPCAST_PATH")"
cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Inventory Manager Updates</title>
    <item>
      <title>Inventory Manager $VERSION</title>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <enclosure
        url="$DOWNLOAD_URL"
        sparkle:edSignature="$ED_SIGNATURE"
        length="$LENGTH"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

echo "Appcast written: $APPCAST_PATH"
