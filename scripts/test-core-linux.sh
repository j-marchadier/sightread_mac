#!/usr/bin/env bash
# Builds and tests MyPianoKit (MyPianoCore and its tests) in the official Swift 6.1 Linux container.
# Usage: scripts/test-core-linux.sh [extra swift test arguments]
set -euo pipefail
cd "$(dirname "$0")/.."
IMAGE="${SWIFT_IMAGE:-swift:6.1-noble}"
exec docker run --rm \
  -v "$PWD":/repo \
  -v mypiano-swiftpm-build:/repo/Packages/MyPianoKit/.build \
  -w /repo/Packages/MyPianoKit \
  "$IMAGE" swift test "$@"
