#!/usr/bin/env bash
# Archives Pianissimac in Release and exports the .app to dist/Pianissimac.app.
#
# Usage:
#   scripts/build-release.sh                       # ad-hoc signed build (local testing only)
#   TEAM_ID=ABCDE12345 scripts/build-release.sh    # Developer ID signed build, ready for notarization
#
# Signing, notarization and stapling are described in docs/RELEASE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

SCHEME=Pianissimac
BUILD_DIR=build/release
ARCHIVE="$BUILD_DIR/Pianissimac.xcarchive"
DIST=dist
TEAM_ID="${TEAM_ID:-}"

rm -rf "$BUILD_DIR" "$DIST/Pianissimac.app"
mkdir -p "$BUILD_DIR" "$DIST"

# Xcode rewrites the string catalog on every build; keep the committed version.
restore_strings() { git checkout -- Pianissimac/Resources/Localizable.xcstrings 2>/dev/null || true; }
trap restore_strings EXIT

signing_args=()
if [[ -n "$TEAM_ID" ]]; then
  signing_args=(
    DEVELOPMENT_TEAM="$TEAM_ID"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="Developer ID Application"
    OTHER_CODE_SIGN_FLAGS=--timestamp
  )
fi

echo "==> Archiving $SCHEME (Release)"
xcodebuild archive \
  -project Pianissimac.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  ${signing_args[@]+"${signing_args[@]}"} \
  | { command -v xcbeautify >/dev/null && xcbeautify || cat; }

if [[ -n "$TEAM_ID" ]]; then
  echo "==> Exporting with Developer ID (team $TEAM_ID)"
  cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>manual</string>
	<key>signingCertificate</key>
	<string>Developer ID Application</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
</dict>
</plist>
PLIST
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$BUILD_DIR/export"
  ditto "$BUILD_DIR/export/Pianissimac.app" "$DIST/Pianissimac.app"
else
  echo "==> No TEAM_ID: copying the ad-hoc signed app (not distributable)"
  ditto "$ARCHIVE/Products/Applications/Pianissimac.app" "$DIST/Pianissimac.app"
fi

codesign --verify --deep --strict "$DIST/Pianissimac.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIST/Pianissimac.app/Contents/Info.plist")
echo "==> $DIST/Pianissimac.app ($version) is ready"
