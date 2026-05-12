#!/usr/bin/env bash
#
# Build, sign, notarize and package dirtymac as a stapled DMG.
#
# Assumes the Developer ID Application certificate is already in your
# login keychain (which it is when run locally on the dev machine).
# CI passes the cert in via a temp keychain set up before invoking
# this script — the steps inside here are identical either way.
#
# Required environment variables:
#   APPLE_TEAM_ID         e.g. SHZP975U3T
#   NOTARY_KEY_PATH       path to App Store Connect API key .p8 file
#   NOTARY_KEY_ID         the key ID shown in App Store Connect
#   NOTARY_ISSUER_ID      issuer UUID shown in App Store Connect
#
# Usage:
#   scripts/release.sh 1.0.0
#
# Output:
#   build/release/dirtymac-<version>.dmg  — notarized & stapled
#   build/release/dirtymac-<version>.sha256  — for the Cask formula

set -euo pipefail

# ─── args ────────────────────────────────────────────────────────────
VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: $(basename "$0") <version>   (e.g. 1.0.0)" >&2
    exit 1
fi

# ─── required env ────────────────────────────────────────────────────
: "${APPLE_TEAM_ID:?must be set}"
: "${NOTARY_KEY_PATH:?must be set (path to AuthKey_XXXX.p8)}"
: "${NOTARY_KEY_ID:?must be set}"
: "${NOTARY_ISSUER_ID:?must be set}"

if [[ ! -f "$NOTARY_KEY_PATH" ]]; then
    echo "error: NOTARY_KEY_PATH does not point to a file: $NOTARY_KEY_PATH" >&2
    exit 1
fi

# ─── paths ───────────────────────────────────────────────────────────
PROJECT="dirtymac.xcodeproj"
SCHEME="dirtymac"
APP_NAME="dirtymac"
BUILD_DIR="build/release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─── 1. archive ──────────────────────────────────────────────────────
# Force MANUAL signing with the Developer ID cert directly. Automatic
# signing would ask Xcode to fetch a "Mac Development" profile from
# Apple, which fails on CI (no signed-in Apple ID) and is unnecessary
# for Developer ID distribution.
echo "▸ archiving $APP_NAME $VERSION"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -destination 'generic/platform=macOS' \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$(date +%Y%m%d%H%M)" \
    DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    -quiet

# ─── 2. export signed app ────────────────────────────────────────────
echo "▸ exporting signed .app (Developer ID)"
cat > "$EXPORT_OPTIONS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$APPLE_TEAM_ID</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    -quiet

if [[ ! -d "$APP_PATH" ]]; then
    echo "error: expected app at $APP_PATH after export" >&2
    exit 1
fi

# ─── 3. build DMG ────────────────────────────────────────────────────
echo "▸ building DMG"
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

# ─── 4. notarize DMG ─────────────────────────────────────────────────
echo "▸ submitting DMG to Apple Notary Service (this can take a few minutes)"
xcrun notarytool submit "$DMG_PATH" \
    --key "$NOTARY_KEY_PATH" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait

# ─── 5. staple ───────────────────────────────────────────────────────
echo "▸ stapling notarization ticket"
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"

# ─── 6. checksum ─────────────────────────────────────────────────────
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "$SHA256  $DMG_NAME" > "$BUILD_DIR/$APP_NAME-$VERSION.sha256"

# ─── done ────────────────────────────────────────────────────────────
echo
echo "✓ release built"
echo "  dmg:    $DMG_PATH"
echo "  sha256: $SHA256"
echo
echo "Next: upload $DMG_NAME to GitHub Releases as v$VERSION,"
echo "      then bump version + sha256 in your homebrew-tap Cask file."
