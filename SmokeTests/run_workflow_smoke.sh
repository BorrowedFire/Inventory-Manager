#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB_COPY_DIR="/tmp/inventory-manager-workflow-smoke-db"
DB_COPY_PATH="$DB_COPY_DIR/InventoryData.sqlite"
BUILD_CACHE="/tmp/inventory-manager-smoke-cache"
SMOKE_BIN="/tmp/inventory_manager_workflow_smoke"

mkdir -p "$DB_COPY_DIR" "$BUILD_CACHE"
rm -f "$DB_COPY_PATH" "$DB_COPY_PATH-shm" "$DB_COPY_PATH-wal" "$SMOKE_BIN"

swiftc \
  -module-cache-path "$BUILD_CACHE" \
  "$ROOT/Sources/Data/DatabaseService.swift" \
  "$ROOT/Sources/Models/Models.swift" \
  "$ROOT/Sources/Services/ExcelSyncService.swift" \
  "$ROOT/Sources/Services/PDFImportService.swift" \
  "$ROOT/SmokeTests/workflow_smoke.swift" \
  -o "$SMOKE_BIN"

"$SMOKE_BIN"
