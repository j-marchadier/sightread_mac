#!/usr/bin/env bash
# Release gate: fails if any trace of the legacy web product, or of the app's former name, remains in the repository.
# Only ACKNOWLEDGEMENTS.md (which credits the GPL inspiration) may name it.
set -euo pipefail
cd "$(dirname "$0")/.."

PATTERN='sightread|gtag|googletagmanager|GA_TRACKING|VITE_PUBLIC_GA|vercel|bun\.sh|renovate'
ALLOWED='^(ACKNOWLEDGEMENTS\.md|scripts/check-legacy-traces\.sh)$'
EXCLUDED_DIRS=(--exclude-dir=.git --exclude-dir=.build --exclude-dir=DerivedData --exclude-dir=build --exclude-dir=dist)

status=0

matches=$(grep -rliIE "$PATTERN" . "${EXCLUDED_DIRS[@]}" \
  | sed 's#^\./##' | grep -vE "$ALLOWED" || true)
if [[ -n "$matches" ]]; then
  echo "Legacy traces found in:"
  echo "$matches"
  status=1
fi

# The app's former name. Only two test fixtures keep it: compressed archives whose expected text must match.
FORMER_NAME_ALLOWED='^Packages/PianissimacKit/Tests/PianissimacCoreTests/Fixtures/Zip/(expected\.txt|stored-expected\.bin)$'
former=$( { grep -rliI "my""piano" . "${EXCLUDED_DIRS[@]}" --exclude-dir=.swiftpm; find . \( -name .git -o -name .build -o -name .swiftpm -o -name DerivedData -o -name build -o -name dist \) -prune -o -iname "*my""piano*" -print; } \
  | sed 's#^\./##' | sort -u | grep -vE "$FORMER_NAME_ALLOWED" || true)
if [[ -n "$former" ]]; then
  echo "Former app name found in:"
  echo "$former"
  status=1
fi

# Web tooling of the legacy app (Bun, Node, Vite, PostCSS, Tailwind, TypeScript) must be gone.
web_files=$(find . \( -name .git -o -name .build -o -name DerivedData \) -prune -o \( \
  -name reference -o -name node_modules -o -name 'package.json' -o -name 'package-lock.json' \
  -o -name 'bun.lockb' -o -name 'bun.lock' -o -name 'yarn.lock' -o -name 'pnpm-lock.yaml' \
  -o -name 'vite.config.*' -o -name 'postcss.config.*' -o -name 'tailwind.config.*' \
  -o -name 'tsconfig*.json' -o -name '.prettierrc*' \) -print | sed 's#^\./##')
if [[ -n "$web_files" ]]; then
  echo "Legacy web tooling found:"
  echo "$web_files"
  status=1
fi

if [[ $status -eq 0 ]]; then
  echo "No legacy traces found."
fi
exit $status
