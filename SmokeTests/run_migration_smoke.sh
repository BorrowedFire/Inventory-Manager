#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DB_DIR="/tmp/inventory-manager-migration-smoke"
DB_PATH="$DB_DIR/LegacyInventory.sqlite"
BUILD_CACHE="/tmp/inventory-manager-migration-smoke-cache"
SMOKE_BIN="/tmp/inventory_manager_migration_smoke"

rm -rf "$DB_DIR" "$SMOKE_BIN"
mkdir -p "$DB_DIR" "$BUILD_CACHE"

sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE inventory_items (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  itemType TEXT DEFAULT '',
  description TEXT DEFAULT '',
  manufacturer TEXT DEFAULT '',
  partNumber TEXT DEFAULT '',
  purchaseDate TEXT,
  vendor TEXT,
  unitCost DOUBLE DEFAULT 0,
  quantity INTEGER DEFAULT 0,
  qtyReceived INTEGER DEFAULT 0,
  poNumber TEXT,
  notes TEXT,
  sourcePDF TEXT,
  budgetType TEXT DEFAULT 'Capital',
  stockroomId INTEGER,
  createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
  updatedAt DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE deployments (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  inventoryItemId INTEGER,
  itemType TEXT DEFAULT '',
  description TEXT DEFAULT '',
  manufacturer TEXT DEFAULT '',
  partNumber TEXT DEFAULT '',
  qtyDeployed INTEGER DEFAULT 1,
  deployedTo TEXT DEFAULT '',
  deployedBy TEXT DEFAULT '',
  deployedDate DATETIME DEFAULT CURRENT_TIMESTAMP,
  deployedLocation TEXT DEFAULT '',
  notes TEXT,
  createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
  stockroomId INTEGER
);
CREATE TABLE stockrooms (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  location TEXT,
  department TEXT,
  createdAt DATETIME DEFAULT CURRENT_TIMESTAMP,
  createdBy INTEGER
);
INSERT INTO stockrooms(name, location, department) VALUES ('Legacy Stockroom', 'Main Office', 'Operations');
INSERT INTO inventory_items(itemType, description, manufacturer, partNumber, purchaseDate, vendor, unitCost, quantity, qtyReceived, poNumber, notes, budgetType, stockroomId)
VALUES ('Laptop', 'Legacy Laptop', 'Example Manufacturer', 'LEGACY-001', '2026-01-15', 'Example Vendor', 1200, 3, 3, 'PO-LEGACY', 'Seeded legacy row', 'Capital', 1);
INSERT INTO deployments(inventoryItemId, itemType, description, manufacturer, partNumber, qtyDeployed, deployedTo, deployedBy, deployedDate, deployedLocation, notes, stockroomId)
VALUES (NULL, 'Laptop', 'Legacy Laptop', 'Example Manufacturer', 'LEGACY-001', 1, 'Example User', 'Example Admin', '2026-02-01', 'Main Office', 'Legacy deployment without FK', 1);
SQL

swiftc \
  -module-cache-path "$BUILD_CACHE" \
  "$ROOT/Sources/Data/DatabaseService.swift" \
  "$ROOT/Sources/Models/Models.swift" \
  "$ROOT/Sources/Services/ExcelSyncService.swift" \
  "$ROOT/Sources/Services/PDFImportService.swift" \
  "$ROOT/SmokeTests/migration_smoke.swift" \
  -o "$SMOKE_BIN"

"$SMOKE_BIN"
