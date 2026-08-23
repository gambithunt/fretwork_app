#!/bin/bash
#
# Builds a distributable Fretwork release: a signed universal .app inside a
# .dmg, plus the Sparkle appcast that points at it.
#
#   ./scripts/build-release.sh [output-dir]
#
# Requires the "Fretwork Code Signing" certificate in the keychain and the
# Sparkle EdDSA private key (in the keychain locally, or piped in via
# SPARKLE_PRIVATE_KEY in CI).
#
set -euo pipefail

PROJECT="Fretlight.xcodeproj"
SCHEME="Fretlight"
APP_NAME="Fretwork"
IDENTITY="${CODE_SIGN_IDENTITY:-Fretwork Code Signing}"
DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-https://downloads.fretwork.org/}"

# $OUT holds only what gets published, so CI can sync it to the bucket
# wholesale. Intermediates live beside it.
OUT="${1:-build}"
WORK="$OUT/../.release-work"
STAGE="$WORK/stage"
ARCHIVE="$WORK/$APP_NAME.xcarchive"

rm -rf "$WORK"
mkdir -p "$OUT" "$STAGE"

# Sparkle's framework and its signing tools are vendored in this repo rather
# than resolved, so a release needs no network and no package resolution.
SPARKLE_BIN="$PWD/Tools/sparkle"
if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
  echo "error: Tools/sparkle/generate_appcast is missing or not executable" >&2
  exit 1
fi

echo "==> Archiving (universal, signed as '$IDENTITY')"
# Signing during the build rather than after lets Xcode handle nested code
# ordering: the XPC services and Updater.app inside Sparkle.framework must be
# signed before the framework, and the framework before the app.
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM="" \
  -quiet archive

APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
[ -d "$APP" ] || { echo "error: no app at $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist")
echo "==> $APP_NAME $VERSION (build $BUILD)"

echo "==> Verifying"
ARCHS=$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")
case "$ARCHS" in
  *x86_64*arm64*|*arm64*x86_64*) echo "    archs: $ARCHS" ;;
  *) echo "error: not a universal binary (got: $ARCHS)" >&2; exit 1 ;;
esac
codesign --verify --deep --strict --verbose=1 "$APP"
# The designated requirement is what a user's microphone grant and Sparkle's
# own update check are both pinned to. If this stops naming the certificate
# and falls back to a bare cdhash, every installed copy will re-prompt for the
# microphone on next update. A self-signed certificate is its own root, so the
# requirement names "certificate root" rather than "certificate leaf".
REQ=$(codesign -d -r- "$APP" 2>/dev/null | sed 's/^designated => //')
echo "    requirement: $REQ"
case "$REQ" in
  *"certificate leaf"*|*"certificate root"*) ;;
  *) echo "error: not signed with a certificate — grants would not survive updates" >&2; exit 1 ;;
esac

echo "==> Building disk image"
DMG="$OUT/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"
cp -R "$APP" "$STAGE/"
# The Applications symlink is not decoration: dragging the app out of the
# image is what stops macOS running it translocated from a random read-only
# path, which breaks self-update.
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
  -ov -format UDZO -quiet "$DMG"
echo "    $DMG ($(du -h "$DMG" | cut -f1))"

echo "==> Generating appcast"
# generate_appcast signs each archive with the EdDSA key and rewrites the
# appcast in place, so keep previously released dmgs in $OUT to retain their
# entries.
if [ -n "${SPARKLE_PRIVATE_KEY:-}" ]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_BIN/generate_appcast" \
    --ed-key-file - --download-url-prefix "$DOWNLOAD_PREFIX" "$OUT"
else
  "$SPARKLE_BIN/generate_appcast" --download-url-prefix "$DOWNLOAD_PREFIX" "$OUT"
fi

# The website reads this instead of being redeployed on every release.
cat > "$OUT/version.json" <<JSON
{
  "version": "$VERSION",
  "build": "$BUILD",
  "url": "${DOWNLOAD_PREFIX}$APP_NAME-$VERSION.dmg",
  "minimumSystemVersion": "14.0"
}
JSON

rm -rf "$WORK"
echo "==> Done"
ls -1 "$OUT" | sed 's/^/    /'
