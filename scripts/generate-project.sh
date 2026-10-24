#!/usr/bin/env bash
# Regenerates MyPiano.xcodeproj from project.yml with XcodeGen.
# Uses a local `xcodegen` (brew install xcodegen) or, if XCODEGEN is set, that binary.
set -euo pipefail
cd "$(dirname "$0")/.."
XCODEGEN="${XCODEGEN:-$(command -v xcodegen || true)}"
if [[ -z "$XCODEGEN" ]]; then
  echo "XcodeGen is required: brew install xcodegen" >&2
  exit 1
fi
"$XCODEGEN" generate --spec project.yml
