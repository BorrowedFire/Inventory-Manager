# Inventory Manager

Inventory Manager is a native macOS app for local hardware and asset tracking.

It is designed for small teams that need a straightforward desktop inventory database with optional spreadsheet compatibility, PDF-assisted item entry, local backups, and Mac-native workflows.

## Privacy-first defaults

- Data is stored locally in SQLite.
- Runtime databases and generated exports are ignored by Git.
- The repository does not include organization-specific databases, sample customer data, credentials, or employer-specific paths.
- Spreadsheet sync is optional and user-selected at runtime.
- The app does not require a server account to run.

## Features

- Inventory, deployments, stockrooms, users, audit activity, and budget views
- Local SQLite persistence with schema migration tracking
- Demo workspace data for safe first-run exploration
- Optional Excel workbook import/export sync helper
- PDF-assisted item parsing with drag-and-drop support and generic fallback extraction
- CSV export and blank inventory template export
- Database backup/restore controls
- macOS sidebar, tables, Settings scene, toolbar actions, and keyboard shortcuts
- Local security/build/smoke check scripts
- Developer ID notarization and DMG helper scripts for later distribution

## Project layout

- `Sources/` — SwiftUI app, models, views, services, and SQLite persistence
- `Resources/` — app assets, privacy manifest, bundled Python packages, and Excel sync helper
- `SmokeTests/` — local workflow and import fixture smoke checks
- `Scripts/` — CI-style checks, security audit, packaging, notarization, and DMG helpers
- `docs/` — architecture notes
- `project.yml` — XcodeGen project definition

Generated builds, packaged apps, local databases, spreadsheets, signing material, and local environment files are intentionally not tracked.

## Build from source

Prerequisites:

- macOS 14+
- Xcode 16+
- XcodeGen

Generate the Xcode project:

```bash
xcodegen generate
```

Build:

```bash
xcodebuild -project InventoryManager.xcodeproj \
  -scheme InventoryManager \
  -configuration Release \
  build
```

## Local quality gate

```bash
Scripts/ci_check.sh
```

This runs the repository security audit, generates the Xcode project, builds the app, and runs all smoke checks.

Individual checks:

```bash
Scripts/security_audit.sh
SmokeTests/run_fresh_workspace_smoke.sh
SmokeTests/run_workflow_smoke.sh
SmokeTests/import_fixture_smoke.py
```

## Package locally

```bash
Scripts/package_release.sh
```

The package script creates `dist/InventoryManager-macOS.zip`.

For a drag-to-Applications DMG after building an app bundle:

```bash
Scripts/create_dmg.sh path/to/Inventory\ Manager.app dist/InventoryManager-macOS.dmg
```

For public/team distribution without Gatekeeper warnings, sign with a Developer ID Application certificate and notarize the release artifact with Apple. See `Scripts/notarize_release.sh` for the required environment variables.

## Documentation

- `docs/ARCHITECTURE.md`
- `docs/SPARKLE_UPDATES.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
