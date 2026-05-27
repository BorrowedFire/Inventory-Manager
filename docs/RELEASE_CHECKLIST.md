# Release checklist

Use this checklist before publishing a public Inventory Manager release.

## Versioning

- Set `MARKETING_VERSION` in `project.yml` to the public version, starting at `0.1.0`.
- Increment `CURRENT_PROJECT_VERSION` for every shipped build.
- Regenerate the Xcode project with `xcodegen generate`.
- Commit and push the version bump to `main` before running the release script. The release script validates that local `main` matches `origin/main` and no tracked files are dirty.

## Local quality gate

```bash
Scripts/ci_check.sh
Scripts/rehearse_sparkle_release.sh
```

Confirm the rehearsal reports:

- `sparkle_signature_verify=ok`
- `download_check=ok`
- `pre_update_backup_fixture=ok`

## Signing and notarization

Run release signing on the maintainer's Mac with a Developer ID Application certificate installed.

The repo includes `Scripts/release_env.sh` with non-secret defaults for this Mac:

- `DEVELOPER_ID_APPLICATION`
- `NOTARYTOOL_PROFILE`

The notary credentials and signing private keys stay in the local macOS Keychain.

If running on a different Mac or with a different certificate, override the defaults:

```bash
export DEVELOPER_ID_APPLICATION="Developer ID Application: Example LLC (TEAMID)"
export APPLE_ID="apple-id@example.com"
export APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"
export TEAM_ID="TEAMID"
```

Alternatively, configure notarytool credentials once in Keychain and use:

```bash
export NOTARYTOOL_PROFILE="inventory-manager-notary"
```

Then run:

```bash
Scripts/release_on_mac.sh 0.1.6 7
```

## GitHub Release assets

The release script creates or updates the GitHub Release with:

- `dist/InventoryManager-macOS.zip`
- `dist/appcast.xml`

`dist/InventoryManager-macOS.zip` must be the final ZIP created after stapling,
not the temporary ZIP submitted to Apple for notarization.

Do not upload local databases, spreadsheets, signing keys, or DerivedData.

## Data safety

Before widening distribution, rehearse an update path:

1. Install the previous release.
2. Create or load sample data.
3. Update through Sparkle.
4. Confirm the database survives.
5. Confirm a pre-update backup exists under `Backups/Before Updates`.
