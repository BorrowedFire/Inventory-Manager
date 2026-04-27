#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v rg >/dev/null 2>&1; then
  echo "error: ripgrep (rg) is required" >&2
  exit 1
fi

SENSITIVE_PATTERN='northwell|workplace technology|\bwts\b|wtsinventory|northwellhealth|onedrive|dalvis|selene|exec ?tech|pellera|converge|derive|ergonomic group|\begi\b|\bcdw\b|applecare|github_pat|ghp_|gho_|BEGIN (RSA|DSA|EC|OPENSSH|PRIVATE) KEY|xox[baprs]-|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|sk-[A-Za-z0-9]{20,}'
ALLOW_PATTERN='DerivedData|private keys|API keys|tokens|employer-specific paths|associated cache records|Release[[:space:]]+Derived'

matches=$(rg -n -i "$SENSITIVE_PATTERN" . \
  --glob '!.git/**' \
  --glob '!build/**' \
  --glob '!dist/**' \
  --glob '!*.xcodeproj/**' \
  --glob '!Resources/python/**' \
  --glob '!Scripts/security_audit.sh' || true)

unexpected=$(printf "%s\n" "$matches" | rg -v "$ALLOW_PATTERN" || true)
if [[ -n "$unexpected" ]]; then
  echo "Security audit failed: sensitive-looking content found:" >&2
  printf "%s\n" "$unexpected" >&2
  exit 1
fi

tracked_artifacts=$(git ls-files | rg '\.(sqlite|db|db-wal|db-shm|xlsx|xls|csv|zip|dmg|app|mobileprovision|p12|cer|pem|key)$|(^|/)DerivedData/|(^|/)build/|(^|/)dist/' || true)
if [[ -n "$tracked_artifacts" ]]; then
  echo "Security audit failed: generated/runtime artifacts are tracked:" >&2
  printf "%s\n" "$tracked_artifacts" >&2
  exit 1
fi

echo "Security audit passed."
