# Architecture

Inventory Manager is a local-first macOS app built with SwiftUI, SQLite, PDFKit, and a bundled Python/openpyxl workbook helper.

## App layers

- `Sources/App` — app entry point and `AppModel`, the main actor-bound state coordinator.
- `Sources/Views` — SwiftUI screens, sheets, settings, tables, onboarding, and workflow controls.
- `Sources/Data` — SQLite persistence, migrations, transactions, audits, dashboard queries, backup checkpoints, and demo seeding.
- `Sources/Services` — file panels, PDF parsing, and Excel sync bridge.
- `Resources/Scripts/excel_sync.py` — workbook read/write helper used through `Process`.
- `SmokeTests` — fast local smoke checks for data workflows and workbook fixtures.

## Data policy

SQLite is the canonical app database. Excel is an optional compatibility surface, not the source of truth. Mutations are written to SQLite first, then synchronized outward when a workbook is configured.

Runtime databases, exports, packaged apps, and credentials must never be committed.

## Migration policy

`DatabaseService.ensureSchema()` owns schema creation and lightweight migrations. The `schema_migrations` table records applied public schema milestones so future changes can be versioned explicitly.

## Distribution policy

Local builds are signed ad hoc. Public/team builds should use Developer ID Application signing and notarization. Release binaries should not be published until the maintainer explicitly approves them.
