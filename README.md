# Inventory Manager

Inventory Manager is a native macOS app for local hardware and asset tracking.

It is designed for small teams that need a polished desktop inventory workspace with local SQLite storage, optional spreadsheet compatibility, PDF-assisted item entry, backups, deployment tracking, and Mac-native workflows.

Current release: [v0.1.6](https://github.com/BorrowedFire/Inventory-Manager/releases/latest)

## What it does now

- Tracks inventory, deployments, stockrooms, users, audit activity, budgets, vendors, and item availability.
- Presents an Apple-centric macOS interface with sidebar navigation, toolbar actions, SF Symbols, dark-first styling, and user-selectable light mode.
- Supports right-click context menus for inventory rows, deployments, stockrooms, and stockroom item lists.
- Provides responsive settings and quick-start layouts that reflow at smaller window sizes.
- Imports from CSV, optional Excel workbooks, and PDF quote or purchase-order documents.
- Exports inventory CSVs and blank CSV templates.
- Creates manual backups, restore checkpoints, import undo backups, and Sparkle pre-update backups.
- Ships with a guarded Danger Zone reset flow that requires multiple confirmations and the typed phrase `DELETE ALL DATA`.
- Distributes notarized macOS releases with Sparkle appcast assets through GitHub Releases.

## Privacy-first defaults

- Data is stored locally in SQLite.
- Runtime databases and generated exports are ignored by Git.
- The repository does not include organization-specific databases, sample customer data, credentials, or employer-specific paths.
- Spreadsheet sync is optional and user-selected at runtime.
- The app does not require a server account to run.
- The app is local-first. Do not put the SQLite database in a cloud-synced folder or a shared network folder for multi-user editing. For shared live inventory, use a central database/API backend instead of sharing the local database file.

## Features

- Apple-style dark-first UI with a Settings-selected light mode
- Adaptive Quick Start and Workspace Database controls for smaller windows
- Right-click actions for edit, duplicate, deploy, copy, filter, return, and delete workflows
- Inventory, deployments, stockrooms, users, audit activity, vendor, and budget views
- Local SQLite persistence with schema migration tracking
- Demo workspace data for safe first-run exploration
- Optional Excel workbook import/export sync helper
- PDF-assisted item parsing with drag-and-drop support and generic fallback extraction
- CSV export and blank inventory template export
- Database backup/restore controls
- Multi-confirmation reset flow for deleting app-managed data and starting fresh
- User-reviewed support bundle generation for diagnostics and recent app logs
- macOS sidebar, tables, Settings scene, toolbar actions, and keyboard shortcuts
- Local security/build/smoke check scripts
- Developer ID notarization, Sparkle appcast generation, and GitHub Release publishing scripts

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

For public/team distribution without Gatekeeper warnings, sign with a Developer ID Application certificate and notarize the release artifact with Apple.

The repo includes non-secret release defaults in `Scripts/release_env.sh`:

- Developer ID identity name
- local notarytool keychain profile name

The credentials and private keys remain in the local macOS Keychain. To publish a notarized Sparkle-ready GitHub Release from `main`, bump `project.yml`, commit and push, then run:

```bash
Scripts/release_on_mac.sh <version> <build>
```

## Documentation

- `docs/ARCHITECTURE.md`
- `docs/SPARKLE_UPDATES.md`
- `docs/RELEASE_CHECKLIST.md`
- `SECURITY.md`
- `CONTRIBUTING.md`
