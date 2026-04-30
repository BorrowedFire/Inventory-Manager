# Architecture

Inventory Manager is a local-first macOS app built with SwiftUI, SQLite, PDFKit, and a bundled Python/openpyxl workbook helper.

## App layers

- `Sources/App` — app entry point and `AppModel`, the main actor-bound state coordinator.
- `Sources/Views` — SwiftUI screens, sheets, settings, tables, onboarding, and workflow controls.
- `Sources/Data` — SQLite persistence, migrations, transactions, audits, dashboard queries, backup checkpoints, and demo seeding.
- `Sources/Support` — app logging, install/relaunch helpers, and user-initiated support bundle generation.
- `Sources/Services` — file panels, PDF parsing, and Excel sync bridge.
- `Resources/Scripts/excel_sync.py` — workbook read/write helper used through `Process`.
- `SmokeTests` — fast local smoke checks for data workflows and workbook fixtures.

## Data policy

SQLite is the canonical app database. Excel is an optional compatibility surface, not the source of truth. Most mutations are written to SQLite first, then synchronized outward when a workbook is configured. Destructive workbook-linked deletes first create a temporary workbook rollback backup, remove matching workbook rows, and then delete from SQLite so the next workbook import cannot resurrect deleted rows.

Runtime databases, exports, packaged apps, and credentials must never be committed.

## Migration policy

`DatabaseService.ensureSchema()` owns schema creation and lightweight migrations. The `schema_migrations` table records applied public schema milestones so future changes can be versioned explicitly.

## Distribution policy

Local builds are signed ad hoc. Public/team builds should use Developer ID Application signing and notarization. Release binaries should not be published until the maintainer explicitly approves them.

## Release-safety safeguards

The app keeps import undo backups under `Backups/Before Imports`, pre-update backups under `Backups/Before Updates`, and records schema milestone `release_safety_backups_and_import_preview` for migration fixture coverage. The import preview UI is intentionally read-only before the destructive import step.

## Support diagnostics

`Report Problem...` creates a user-initiated support bundle under Application Support. The bundle contains app/version metadata, bounded recent unified logs, recent in-app error messages, and matching crash reports. It intentionally excludes the SQLite database and Excel workbook contents by default.
