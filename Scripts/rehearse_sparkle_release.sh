#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE_VERSION="${BASE_VERSION:-0.1.0}"
UPDATE_VERSION="${UPDATE_VERSION:-0.1.1}"
BASE_BUILD="${BASE_BUILD:-1}"
UPDATE_BUILD="${UPDATE_BUILD:-2}"
PORT="${PORT:-$(/usr/bin/python3 - <<'PY'
import socket
s = socket.socket()
s.bind(('127.0.0.1', 0))
print(s.getsockname()[1])
s.close()
PY
)}"
WORK_DIR="${WORK_DIR:-$(mktemp -d /tmp/inventory-manager-sparkle-rehearsal.XXXXXX)}"
SPARKLE_KEY_ACCOUNT="${SPARKLE_KEY_ACCOUNT:-com.inventorymanager.app}"
SIGN_UPDATE_TIMEOUT_SECONDS="${SIGN_UPDATE_TIMEOUT_SECONDS:-45}"
USE_TEMP_SPARKLE_KEY="${USE_TEMP_SPARKLE_KEY:-1}"
PUBLIC_KEY="${PUBLIC_KEY:-EKjDkvxFSb8UmWYUG8dRZvOyNLMxWDSF95rEH9C3htY=}"
APPCAST_URL="http://127.0.0.1:$PORT/appcast.xml"
APP_NAME="Inventory Manager.app"

echo "Rehearsal workspace: $WORK_DIR"
mkdir -p "$WORK_DIR/source" "$WORK_DIR/http" "$WORK_DIR/builds"
rsync -a --delete \
  --exclude '.git' \
  --exclude 'build' \
  --exclude 'dist' \
  --exclude '*.xcodeproj' \
  --exclude 'Vendor' \
  "$ROOT/" "$WORK_DIR/source/"

cd "$WORK_DIR/source"

if [[ "$USE_TEMP_SPARKLE_KEY" == "1" ]]; then
  cat > "$WORK_DIR/generate-ed-key.swift" <<'SWIFT'
import Foundation
import CryptoKit

let privateKey = Curve25519.Signing.PrivateKey()
print(Data(privateKey.rawRepresentation).base64EncodedString())
print(Data(privateKey.publicKey.rawRepresentation).base64EncodedString())
SWIFT
  KEY_OUTPUT=$(swift "$WORK_DIR/generate-ed-key.swift")
  PRIVATE_KEY=$(printf "%s\n" "$KEY_OUTPUT" | sed -n '1p')
  PUBLIC_KEY=$(printf "%s\n" "$KEY_OUTPUT" | sed -n '2p')
  printf "%s" "$PRIVATE_KEY" > "$WORK_DIR/sparkle-private-key.txt"
  chmod 600 "$WORK_DIR/sparkle-private-key.txt"
  echo "sparkle_key=temp"
else
  echo "sparkle_key=keychain:$SPARKLE_KEY_ACCOUNT"
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "error: xcodegen is required" >&2
  exit 1
fi

patch_version() {
  local version="$1"
  local build="$2"
  python3 - "$version" "$build" "$APPCAST_URL" "$PUBLIC_KEY" <<'PY'
from pathlib import Path
import re, sys
version, build, feed, pub = sys.argv[1:]
p = Path('project.yml')
s = p.read_text()
s = re.sub(r'MARKETING_VERSION: .*', f'MARKETING_VERSION: {version}', s)
s = re.sub(r'CURRENT_PROJECT_VERSION: .*', f'CURRENT_PROJECT_VERSION: {build}', s)
s = re.sub(r'SUFeedURL: .*', f'SUFeedURL: {feed}', s)
s = re.sub(r'SUPublicEDKey: .*', f'SUPublicEDKey: {pub}', s)
p.write_text(s)
PY
  xcodegen generate >/dev/null
}

build_release() {
  local label="$1"
  local out_dir="$WORK_DIR/builds/$label"
  rm -rf "$out_dir"
  mkdir -p "$out_dir"
  xcodebuild \
    -project InventoryManager.xcodeproj \
    -scheme InventoryManager \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$out_dir/DerivedData" \
    build >/tmp/inventory-manager-$label-build.log 2>&1

  local app="$out_dir/DerivedData/Build/Products/Release/$APP_NAME"
  if [[ ! -d "$app" ]]; then
    echo "error: expected app not found at $app" >&2
    tail -80 "/tmp/inventory-manager-$label-build.log" >&2
    exit 1
  fi

  local actual_version actual_build actual_feed actual_key
  actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
  actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
  actual_feed=$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$app/Contents/Info.plist")
  actual_key=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$app/Contents/Info.plist")
  echo "$label version=$actual_version build=$actual_build"
  [[ "$actual_feed" == "$APPCAST_URL" ]] || { echo "error: feed URL mismatch" >&2; exit 1; }
  [[ "$actual_key" == "$PUBLIC_KEY" ]] || { echo "error: Sparkle public key mismatch" >&2; exit 1; }

  ditto -c -k --keepParent "$app" "$out_dir/InventoryManager-$label.zip"
}

find_sign_update() {
  find \
    "$WORK_DIR/source/.build" \
    "$WORK_DIR/source/build" \
    "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update' \
    -type f 2>/dev/null | head -1 || true
}

patch_version "$BASE_VERSION" "$BASE_BUILD"
build_release "base-$BASE_VERSION-b$BASE_BUILD"

patch_version "$UPDATE_VERSION" "$UPDATE_BUILD"
build_release "update-$UPDATE_VERSION-b$UPDATE_BUILD"

UPDATE_ZIP="$WORK_DIR/builds/update-$UPDATE_VERSION-b$UPDATE_BUILD/InventoryManager-update-$UPDATE_VERSION-b$UPDATE_BUILD.zip"
cp "$WORK_DIR/builds/update-$UPDATE_VERSION-b$UPDATE_BUILD/InventoryManager-update-$UPDATE_VERSION-b$UPDATE_BUILD.zip" "$WORK_DIR/http/InventoryManager-macOS.zip" 2>/dev/null || true
if [[ ! -f "$WORK_DIR/http/InventoryManager-macOS.zip" ]]; then
  cp "$WORK_DIR/builds/update-$UPDATE_VERSION-b$UPDATE_BUILD/InventoryManager-update-$UPDATE_VERSION-b$UPDATE_BUILD.zip" "$WORK_DIR/http/InventoryManager-macOS.zip"
fi

SIGN_UPDATE="$(find_sign_update)"
if [[ -z "$SIGN_UPDATE" || ! -x "$SIGN_UPDATE" ]]; then
  echo "error: Sparkle sign_update not found" >&2
  exit 1
fi

set +e
if [[ "$USE_TEMP_SPARKLE_KEY" == "1" ]]; then
  SIGNATURE_OUTPUT=$(perl -e 'alarm shift; exec @ARGV' "$SIGN_UPDATE_TIMEOUT_SECONDS" "$SIGN_UPDATE" --ed-key-file "$WORK_DIR/sparkle-private-key.txt" "$WORK_DIR/http/InventoryManager-macOS.zip" 2>&1)
else
  SIGNATURE_OUTPUT=$(perl -e 'alarm shift; exec @ARGV' "$SIGN_UPDATE_TIMEOUT_SECONDS" "$SIGN_UPDATE" --account "$SPARKLE_KEY_ACCOUNT" "$WORK_DIR/http/InventoryManager-macOS.zip" 2>&1)
fi
SIGNATURE_STATUS=$?
set -e
if [[ "$SIGNATURE_STATUS" -ne 0 ]]; then
  echo "error: Sparkle signing failed or timed out." >&2
  echo "If macOS is showing a Keychain access prompt for Sparkle's private update key, approve it once and rerun." >&2
  printf "%s\n" "$SIGNATURE_OUTPUT" >&2
  exit "$SIGNATURE_STATUS"
fi
ED_SIGNATURE=$(printf "%s\n" "$SIGNATURE_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' | head -1)
LENGTH=$(stat -f%z "$WORK_DIR/http/InventoryManager-macOS.zip")
if [[ -z "$ED_SIGNATURE" ]]; then
  echo "error: could not parse Sparkle signature" >&2
  printf "%s\n" "$SIGNATURE_OUTPUT" >&2
  exit 1
fi

cat > "$WORK_DIR/http/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Inventory Manager Updates Rehearsal</title>
    <item>
      <title>Inventory Manager $UPDATE_VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S %z')</pubDate>
      <sparkle:version>$UPDATE_BUILD</sparkle:version>
      <sparkle:shortVersionString>$UPDATE_VERSION</sparkle:shortVersionString>
      <enclosure
        url="http://127.0.0.1:$PORT/InventoryManager-macOS.zip"
        sparkle:edSignature="$ED_SIGNATURE"
        length="$LENGTH"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

/usr/bin/python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$WORK_DIR/http" >/tmp/inventory-manager-sparkle-http.log 2>&1 &
SERVER_PID=$!
trap 'kill $SERVER_PID 2>/dev/null || true' EXIT
sleep 1

curl -fsS "$APPCAST_URL" >/tmp/inventory-manager-appcast-check.xml
curl -fsS "http://127.0.0.1:$PORT/InventoryManager-macOS.zip" -o /tmp/inventory-manager-update-check.zip
cmp -s "$WORK_DIR/http/InventoryManager-macOS.zip" /tmp/inventory-manager-update-check.zip

if [[ "$USE_TEMP_SPARKLE_KEY" == "1" ]]; then
  "$SIGN_UPDATE" --verify --ed-key-file "$WORK_DIR/sparkle-private-key.txt" "$WORK_DIR/http/InventoryManager-macOS.zip" "$ED_SIGNATURE" >/tmp/inventory-manager-sparkle-verify.log 2>&1
else
  "$SIGN_UPDATE" --verify --account "$SPARKLE_KEY_ACCOUNT" "$WORK_DIR/http/InventoryManager-macOS.zip" "$ED_SIGNATURE" >/tmp/inventory-manager-sparkle-verify.log 2>&1
fi

DB_DIR="$WORK_DIR/db-fixture"
BACKUP_DIR="$DB_DIR/Backups/Before Updates"
DB_PATH="$DB_DIR/InventoryData.sqlite"
mkdir -p "$DB_DIR" "$BACKUP_DIR"
sqlite3 "$DB_PATH" <<'SQL'
PRAGMA journal_mode=WAL;
CREATE TABLE inventory_rehearsal(id INTEGER PRIMARY KEY, name TEXT NOT NULL);
INSERT INTO inventory_rehearsal(name) VALUES ('sample item before update');
PRAGMA wal_checkpoint(TRUNCATE);
SQL
BACKUP_PATH="$BACKUP_DIR/InventoryData-pre-update-v$BASE_VERSION-b$BASE_BUILD-$(date -u '+%Y%m%d-%H%M%S').sqlite"
cp "$DB_PATH" "$BACKUP_PATH"
[[ "$(sqlite3 "$BACKUP_PATH" 'PRAGMA integrity_check;')" == "ok" ]]
[[ "$(sqlite3 "$BACKUP_PATH" 'SELECT COUNT(*) FROM inventory_rehearsal;')" == "1" ]]

echo "appcast_url=$APPCAST_URL"
echo "base_app=$WORK_DIR/builds/base-$BASE_VERSION-b$BASE_BUILD/DerivedData/Build/Products/Release/$APP_NAME"
echo "update_zip=$WORK_DIR/http/InventoryManager-macOS.zip"
echo "appcast=$WORK_DIR/http/appcast.xml"
echo "sparkle_signature=ok"
echo "sparkle_signature_verify=ok"
echo "download_check=ok"
echo "pre_update_backup_fixture=ok"
echo "rehearsal_artifacts=ok"
