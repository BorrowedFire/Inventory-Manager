#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CACHE="/tmp/inventory-manager-app-model-smoke-cache"
SMOKE_BIN="/tmp/inventory_manager_app_model_safety_smoke"

mkdir -p "$BUILD_CACHE"
rm -f "$SMOKE_BIN"

swiftc \
  -module-cache-path "$BUILD_CACHE" \
  "$ROOT/Sources/App/AppModel.swift" \
  "$ROOT/Sources/Data/DatabaseService.swift" \
  "$ROOT/Sources/Models/Models.swift" \
  "$ROOT/Sources/Services/ExcelSyncService.swift" \
  "$ROOT/Sources/Services/FileDialogs.swift" \
  "$ROOT/Sources/Services/PDFImportService.swift" \
  "$ROOT/Sources/Support/AppLog.swift" \
  "$ROOT/Sources/Support/SupportBundleService.swift" \
  "$ROOT/SmokeTests/app_model_safety_smoke.swift" \
  -o "$SMOKE_BIN"

"$SMOKE_BIN"
