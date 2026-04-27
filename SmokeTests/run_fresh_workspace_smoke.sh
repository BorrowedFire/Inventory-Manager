#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CACHE="/tmp/inventory-manager-fresh-smoke-cache"
SMOKE_BIN="/tmp/universal_inventory_fresh_workspace_smoke"

mkdir -p "$BUILD_CACHE" /tmp/inventory-manager-fresh-smoke
rm -f "$SMOKE_BIN"

swiftc \
  -module-cache-path "$BUILD_CACHE" \
  "$ROOT/Sources/Data/DatabaseService.swift" \
  "$ROOT/Sources/Models/Models.swift" \
  "$ROOT/Sources/Services/ExcelSyncService.swift" \
  "$ROOT/Sources/Services/PDFImportService.swift" \
  "$ROOT/SmokeTests/fresh_workspace_smoke.swift" \
  -o "$SMOKE_BIN"

"$SMOKE_BIN"
