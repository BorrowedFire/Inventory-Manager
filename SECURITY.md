# Security and privacy

Inventory Manager is intended to keep operational data local by default.

## What should not be committed

Do not commit:

- SQLite databases (`*.sqlite`, `*.db`, WAL/SHM files)
- Real inventory exports or spreadsheets
- Customer, employee, vendor-contract, asset-tag, serial-number, or location data
- API keys, tokens, certificates, private keys, provisioning profiles, or notarization credentials
- Organization-specific paths, names, screenshots, or sample documents

The repository `.gitignore` excludes common runtime data and build artifacts, but review changes before publishing.

`Scripts/release_env.sh` may contain public certificate identity names and local Keychain profile names. That is acceptable. Do not add Apple account passwords, app-specific passwords, private keys, exported certificates, or Sparkle private signing keys to that file.

## Reporting issues

If you find a security or privacy issue, open a private report or contact the maintainer directly. Avoid posting sensitive data in public issues.
