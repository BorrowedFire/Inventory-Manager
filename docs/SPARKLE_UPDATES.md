# Sparkle updates

Inventory Manager includes Sparkle 2 integration for direct-download macOS updates.

## What is wired

- Sparkle package dependency in `project.yml`
- `Check for Updates…` app menu command
- `SUFeedURL` pointing at the GitHub Release appcast location
- `SUPublicEDKey` configured in `Resources/Info.plist`
- appcast generation script: `Scripts/make_appcast.sh`
- end-to-end release script: `Scripts/release_on_mac.sh`
- repo-safe release defaults: `Scripts/release_env.sh`

## Signing key

A Sparkle Ed25519 signing key was generated in the local macOS Keychain under this account:

```text
com.inventorymanager.app
```

Only the public key is committed to the app. Keep the private key in Keychain or a password manager. Do not commit or paste the private key into the repository.

## Database safety

Before Sparkle relaunches or installs an update-on-quit, Inventory Manager creates an automatic SQLite backup under the current workspace database folder:

```text
Backups/Before Updates/InventoryData-pre-update-v<version>-b<build>-<timestamp>.sqlite
```

The backup is made after a SQLite checkpoint so the saved file is self-contained. If the backup fails, the update is paused instead of continuing without a safety copy.

## App Management permission

When Sparkle is ready to install an update, Inventory Manager shows a notice explaining that macOS may request App Management permission. That permission is used only so the updater can replace Inventory Manager's own app bundle. It does not grant inventory database access, Excel workbook access, or permission to manage unrelated apps. Users can choose "Don't remind me again" if they do not want to see the explanation before future update installs.

## Release flow

1. Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
2. Run `Scripts/ci_check.sh`.
3. Commit and push the version bump and app changes to `main`.
4. Publish from `main`:

```bash
Scripts/release_on_mac.sh <version> <build>
```

The release script verifies that local `main` matches `origin/main`, runs the quality gate, rehearses Sparkle update behavior, builds a hardened runtime app, Developer ID signs it, notarizes it with Apple, staples the app, creates the final zip, generates `dist/appcast.xml`, and creates or updates the GitHub Release.

`Scripts/release_env.sh` provides the repo-safe defaults for this Mac:

- `DEVELOPER_ID_APPLICATION`
- `NOTARYTOOL_PROFILE`

The notary credentials, Developer ID private key, and Sparkle private update key stay in the local macOS Keychain. Do not commit credentials or private keys.

For manual appcast generation after a final notarized zip already exists:

```bash
Scripts/make_appcast.sh dist/InventoryManager-macOS.zip dist/appcast.xml
```

The script signs the zip using Sparkle's `sign_update` tool and the Keychain account above.
When `VERSION` and `BUILD` are not provided, it reads `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `project.yml`.

The release uploads both files to the GitHub Release:

- `InventoryManager-macOS.zip`
- `appcast.xml`

Sparkle checks this appcast URL:

```text
https://github.com/BorrowedFire/Inventory-Manager/releases/latest/download/appcast.xml
```

## Notes

- Appcast generation should happen only after the final notarized zip is built.
- Inventory Manager is not sandboxed, so do not enable Sparkle's sandbox-only `SUEnableInstallerLauncherService` flag unless the app is moved to an App Sandbox configuration with the required XPC service setup.
- If you move release hosting later, update `SUFeedURL` in `Resources/Info.plist` before shipping that version.
