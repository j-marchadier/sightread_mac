#!/usr/bin/env bash
# Packs dist/MyPiano.app into dist/MyPiano-<version>.dmg with a link to /Applications.
#
# Usage:
#   scripts/make-dmg.sh [path/to/MyPiano.app]
#   SIGN_IDENTITY="Developer ID Application: …" scripts/make-dmg.sh   # also signs the disk image
#
# Run scripts/build-release.sh first. Notarization is described in docs/RELEASE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-dist/MyPiano.app}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

if [[ ! -d "$APP" ]]; then
  echo "App not found: $APP (run scripts/build-release.sh first)" >&2
  exit 1
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
DMG="dist/MyPiano-$version.dmg"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

ditto "$APP" "$staging/MyPiano.app"
ln -s /Applications "$staging/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "MyPiano $version" \
  -srcfolder "$staging" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov "$DMG"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG"
  codesign --verify "$DMG"
fi

hdiutil verify "$DMG"
echo "==> $DMG is ready"
