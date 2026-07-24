#!/usr/bin/env bash
#
# Build, sign, notarize and package dirtymac as a stapled DMG.
#
# Both the .app and the DMG get their own notarization ticket stapled.
# The one on the .app is what matters for Homebrew: `brew install --cask`
# copies dirtymac.app out of the DMG into /Applications and leaves the
# DMG's ticket behind. With no ticket on the app itself, Gatekeeper has
# to ask Apple over the network the first time it launches — so anyone
# offline, on a filtering proxy, or behind a blocked ocsp/notary endpoint
# is told the app can't be verified and refused.
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
SIGN_IDENTITY="Developer ID Application"
BUILD_DIR="build/release"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
EXPORT_OPTIONS="$BUILD_DIR/ExportOptions.plist"
VERIFY_MNT="$BUILD_DIR/verify-mnt"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# ─── helpers ─────────────────────────────────────────────────────────
# notarytool exits 0 for a submission that completed but was *rejected*,
# so the final status has to be read back explicitly — otherwise a build
# that Apple refused sails straight through to a release.
notarize() {
    local target="$1"
    local json status submission_id

    json=$(xcrun notarytool submit "$target" \
        --key "$NOTARY_KEY_PATH" \
        --key-id "$NOTARY_KEY_ID" \
        --issuer "$NOTARY_ISSUER_ID" \
        --output-format json \
        --wait)

    status=$(printf '%s' "$json" | plutil -extract status raw -o - - 2>/dev/null || echo unknown)
    submission_id=$(printf '%s' "$json" | plutil -extract id raw -o - - 2>/dev/null || echo "")

    if [[ "$status" != "Accepted" ]]; then
        echo "error: notarization of $(basename "$target") finished with status: $status" >&2
        if [[ -n "$submission_id" ]]; then
            echo "--- notary log ---" >&2
            xcrun notarytool log "$submission_id" \
                --key "$NOTARY_KEY_PATH" \
                --key-id "$NOTARY_KEY_ID" \
                --issuer "$NOTARY_ISSUER_ID" >&2 || true
        fi
        exit 1
    fi
}

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
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
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

# ─── 3. notarize + staple the .app ───────────────────────────────────
# This has to happen before the DMG is built, so the copy that ends up
# inside it — and therefore the copy Homebrew drops in /Applications —
# carries its own ticket and validates with no network.
echo "▸ submitting $APP_NAME.app to Apple Notary Service (this can take a few minutes)"
APP_ZIP="$BUILD_DIR/$APP_NAME-app.zip"
/usr/bin/ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
notarize "$APP_ZIP"
rm -f "$APP_ZIP"

echo "▸ stapling notarization ticket to $APP_NAME.app"
xcrun stapler staple "$APP_PATH"

# ─── 4. build DMG ────────────────────────────────────────────────────
echo "▸ building DMG"
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
# ditto, not cp — it preserves the stapled ticket and the rest of the
# bundle's metadata verbatim.
/usr/bin/ditto "$APP_PATH" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH" >/dev/null

# ─── 5. sign DMG ─────────────────────────────────────────────────────
# An unsigned DMG has nothing for Gatekeeper to evaluate when someone
# downloads it straight from the Releases page, ticket or not.
echo "▸ signing DMG"
codesign --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

# ─── 6. notarize + staple DMG ────────────────────────────────────────
echo "▸ submitting DMG to Apple Notary Service"
notarize "$DMG_PATH"

echo "▸ stapling notarization ticket to DMG"
xcrun stapler staple "$DMG_PATH"

# ─── 7. verify what the user actually receives ───────────────────────
# Assert against the app inside the finished DMG, not the export dir —
# that is the bundle Homebrew copies to /Applications.
echo "▸ verifying"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature -v "$DMG_PATH"

rm -rf "$VERIFY_MNT"
mkdir -p "$VERIFY_MNT"
trap 'hdiutil detach "$VERIFY_MNT" -quiet 2>/dev/null || true' EXIT
hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$VERIFY_MNT" >/dev/null

codesign --verify --deep --strict --verbose=2 "$VERIFY_MNT/$APP_NAME.app"
xcrun stapler validate "$VERIFY_MNT/$APP_NAME.app"
spctl --assess --type exec -vv "$VERIFY_MNT/$APP_NAME.app"

hdiutil detach "$VERIFY_MNT" -quiet
trap - EXIT
rm -rf "$VERIFY_MNT"

# ─── 8. checksum ─────────────────────────────────────────────────────
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "$SHA256  $DMG_NAME" > "$BUILD_DIR/$APP_NAME-$VERSION.sha256"

# ─── done ────────────────────────────────────────────────────────────
echo
echo "✓ release built — app and DMG both stapled"
echo "  dmg:    $DMG_PATH"
echo "  sha256: $SHA256"
echo
echo "Next: upload $DMG_NAME to GitHub Releases as v$VERSION,"
echo "      then bump version + sha256 in your homebrew-tap Cask file."
