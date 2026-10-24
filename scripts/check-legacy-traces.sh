#!/usr/bin/env bash
# Fails if any trace of the legacy web product remains outside the allowed files.
# Used during the rewrite (reference/web excluded) and as a release gate in Phase 9.
set -euo pipefail
cd "$(dirname "$0")/.."

PATTERN='sightread|gtag|googletagmanager|GA_TRACKING|VITE_PUBLIC_GA|vercel|bun\.sh|renovate'
ALLOWED='^(\./)?(ACKNOWLEDGEMENTS\.md|docs/(SPEC|REMOVAL_INVENTORY|PLAN|ARCHITECTURE)\.md|scripts/check-legacy-traces\.sh)$'

matches=$(grep -rliIE "$PATTERN" . \
  --exclude-dir=.git --exclude-dir=reference --exclude-dir=.build --exclude-dir=DerivedData \
  | sed 's#^\./##' | grep -vE "$ALLOWED" || true)

if [[ -n "$matches" ]]; then
  echo "Legacy traces found in:"
  echo "$matches"
  exit 1
fi
echo "No legacy traces found."
