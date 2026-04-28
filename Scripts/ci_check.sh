#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

Scripts/security_audit.sh
xcodegen generate
xcodebuild \
  -project InventoryManager.xcodeproj \
  -scheme InventoryManager \
  -configuration Debug \
  -destination 'platform=macOS' \
  build
SmokeTests/run_fresh_workspace_smoke.sh
SmokeTests/run_workflow_smoke.sh
SmokeTests/run_migration_smoke.sh
/usr/bin/python3 SmokeTests/import_fixture_smoke.py
