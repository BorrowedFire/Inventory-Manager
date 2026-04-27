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
- If you move release hosting later, update `SUFeedURL` in `Resources/Info.plist` before shipping that version.
