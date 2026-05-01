# Architecture

Inventory Manager is a local-first macOS app built with SwiftUI, SQLite, PDFKit, and a bundled Python/openpyxl workbook helper.

## User experience

The app uses a dark-first SwiftUI interface with Apple-style navigation, SF Symbols, responsive settings layouts, and a user-selectable light mode. Primary records expose context menus so common row actions are available from right-click:

- inventory: edit, duplicate, deploy, copy identifiers, filter, and delete
- deployments: mark returned, find the inventory item, copy identifiers, and delete
- stockrooms: edit, open in inventory, and delete

## App layers

- `Sources/App` — app entry point and `AppModel`, the main actor-bound state coordinator.
- `Sources/Views` — SwiftUI screens, sheets, settings, tables, onboarding, and workflow controls.
- `Sources/Data` — SQLite persistence, migrations, transactions, audits, dashboard queries, backup checkpoints, and demo seeding.
- `Sources/Support` — app logging, install/relaunch helpers, and user-initiated support bundle generation.
- `Sources/Services` — file panels, PDF parsing, and Excel sync bridge.
- `Resources/Scripts/excel_sync.py` — workbook read/write helper used through `Process`.
- `SmokeTests` — fast local smoke checks for data workflows and workbook fixtures.

## Data policy

SQLite is the canonical app database. Excel is an optional compatibility surface, not the source of truth. Most mutations are written to SQLite first, then synchronized outward when a workbook is configured. Destructive workbook-linked deletes first create a temporary workbook rollback backup, remove matching workbook rows, and then delete from SQLite so the next workbook import cannot resurrect deleted rows. If SQLite deletion succeeds but a later remaining-inventory sync fails, the workbook delete is preserved and the user is asked to rerun remaining sync after fixing the workbook issue.

Runtime databases, exports, packaged apps, and credentials must never be committed.

## Reset policy

The Settings Danger Zone exposes a start-fresh action for admins or maintainers who intentionally want to remove app-managed local data. The UI requires an initial confirmation, a typed `DELETE ALL DATA` phrase, and a final destructive confirmation before running. The reset removes app-managed SQLite data, backups next to the active workspace database, app support data, and saved preferences where applicable, then creates a fresh default workspace. It disconnects an external Excel workbook path but does not delete the workbook itself.

This reset is a local-app data operation. It is not a substitute for a server-side multi-user inventory lifecycle.

## Migration policy

`DatabaseService.ensureSchema()` owns schema creation and lightweight migrations. The `schema_migrations` table records applied public schema milestones so future changes can be versioned explicitly.

## Distribution policy

Local builds are signed ad hoc. Public/team releases are Developer ID signed, Apple notarized, stapled, packaged as `dist/InventoryManager-macOS.zip`, and paired with a Sparkle `appcast.xml` asset on the GitHub Release. `Scripts/release_env.sh` stores repo-safe identity/profile names only; credentials and private keys remain in the local Keychain. Release binaries should not be published until the maintainer explicitly approves them.

## Release-safety safeguards

The app keeps import undo backups under `Backups/Before Imports`, pre-update backups under `Backups/Before Updates`, and records schema milestone `release_safety_backups_and_import_preview` for migration fixture coverage. Restore creates a checkpointed pre-restore backup and removes stale SQLite WAL/SHM sidecars before opening the restored database. The import preview UI is intentionally read-only before the destructive import step.

## Support diagnostics

`Report Problem...` shows a disclosure sheet before creating a user-initiated support bundle under Application Support. The bundle contains app/version metadata, bounded recent unified logs, recent in-app error messages, and matching crash reports. It intentionally excludes the SQLite database and Excel workbook contents by default.
