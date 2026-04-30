# Sparkle updates

Inventory Manager includes Sparkle 2 integration for direct-download macOS updates.

## What is wired

- Sparkle package dependency in `project.yml`
- `Check for Updates…` app menu command
- `SUFeedURL` pointing at the GitHub Release appcast location
- `SUPublicEDKey` configured in `Resources/Info.plist`
- appcast generation script: `Scripts/make_appcast.sh`

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

## Release flow

1. Build, Developer ID sign, and notarize the app.
2. Create the release zip.
3. Generate the appcast:

```bash
Scripts/make_appcast.sh dist/InventoryManager-macOS.zip dist/appcast.xml
```

The script signs the zip using Sparkle's `sign_update` tool and the Keychain account above.

4. Upload both files to the GitHub Release:

- `InventoryManager-macOS.zip`
- `appcast.xml`

Sparkle checks this appcast URL:

```text
https://github.com/BorrowedFire/Inventory-Manager/releases/latest/download/appcast.xml
```

## Notes

- GitHub Release publishing is intentionally not automatic yet.
- Appcast generation should happen only after the final notarized zip is built.
- Inventory Manager is not sandboxed, so do not enable Sparkle's sandbox-only `SUEnableInstallerLauncherService` flag unless the app is moved to an App Sandbox configuration with the required XPC service setup.
- If you move release hosting later, update `SUFeedURL` in `Resources/Info.plist` before shipping that version.
