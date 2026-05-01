#!/bin/zsh

# Repo-safe release defaults. The notary profile itself lives in the local
# Keychain; this file only names which local profile and certificate to use.
export DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-Developer ID Application: Borrowed Fire LLC (VGHCLVQKFR)}"
export NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-inventory-manager-notary}"
