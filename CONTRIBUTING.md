# Contributing

Thanks for helping improve Inventory Manager.

## Local checks

Run the full local gate before opening a PR:

```bash
Scripts/ci_check.sh
```

This runs:

- repository security audit
- XcodeGen project generation
- Debug macOS build
- fresh workspace smoke test
- workflow smoke test
- Excel import fixture smoke test

## Privacy rules

Do not include real inventory, employee, customer, vendor-contract, asset-tag, serial-number, location, credential, certificate, or notarization data in commits, screenshots, issues, or pull requests.

Use `Example Vendor`, `Example Manufacturer`, and synthetic asset data for tests and docs.

## Generated files

Do not commit generated Xcode projects, build products, app bundles, archives, DMGs, ZIPs, SQLite databases, spreadsheets, local environment files, or signing material.
