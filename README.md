# Inventory Manager

Inventory Manager is a native macOS app for local hardware and asset tracking.

It is designed for small teams that need a straightforward desktop inventory database with optional spreadsheet compatibility and PDF-assisted item entry.

## Privacy-first defaults

- Data is stored locally in SQLite.
- Runtime databases and generated exports are ignored by Git.
- The repository does not include organization-specific databases, sample customer data, credentials, or employer-specific paths.
- Spreadsheet sync is optional and user-selected at runtime.

## Features

- Inventory, deployments, stockrooms, users, audit activity, and budget views
- Local SQLite persistence
- Optional Excel workbook import/export sync helper
- PDF-assisted item parsing with generic fallback extraction
- CSV export and blank inventory template export
- Local smoke checks for core workflows

## Project layout

- `Sources/` — SwiftUI app, models, views, services, and SQLite persistence
- `Resources/` — app assets, bundled Python packages, and Excel sync helper
- `SmokeTests/` — local workflow smoke checks
- `Scripts/` — release packaging helper
- `project.yml` — XcodeGen project definition

Generated builds, packaged apps, local databases, and local environment files are intentionally not tracked.

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

## Smoke checks

```bash
SmokeTests/run_fresh_workspace_smoke.sh
SmokeTests/run_workflow_smoke.sh
```

## Package locally

```bash
Scripts/package_release.sh
```

The package script creates `dist/InventoryManager-macOS.zip`. For public distribution without Gatekeeper warnings, sign with a Developer ID Application certificate and notarize the release artifact with Apple.
