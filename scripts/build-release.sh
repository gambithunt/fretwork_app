#!/bin/bash
#
# Builds a distributable Fretwork release: a signed universal .app inside a
# .dmg, plus the Sparkle appcast that points at it.
#
#   ./scripts/build-release.sh [output-dir]
#
# Requires a Developer ID Application certificate in the keychain and the
# Sparkle EdDSA private key (in the keychain locally, or piped in via
# SPARKLE_PRIVATE_KEY in CI). Set REQUIRE_NOTARIZATION=1 together with a
# NOTARYTOOL_PROFILE to submit and staple the disk image.
#
set -euo pipefail

PROJECT="Fretlight.xcodeproj"
SCHEME="Fretlight"
APP_NAME="Fretwork"
IDENTITY="${CODE_SIGN_IDENTITY:-Developer ID Application}"
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
  -destination 'generic/platform=macOS' -derivedDataPath "$WORK/DerivedData" \
  -archivePath "$ARCHIVE" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  ENABLE_HARDENED_RUNTIME=YES \
  -quiet archive

APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
[ -d "$APP" ] || { echo "error: no app at $APP" >&2; exit 1; }

# Sparkle is vendored as a pre-signed binary framework. Xcode correctly embeds
# it, but preserves its vendor signatures; notarization requires every nested
# executable to carry this app's Developer ID signature and secure timestamp.
# Re-signing the finished hierarchy applies both consistently before we verify
# and package it.
echo "==> Re-signing bundled code with Developer ID"
codesign --force --deep --sign "$IDENTITY" --options runtime --timestamp "$APP"

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
# own update check are both pinned to. A bare cdhash would make each rebuild a
# new identity, so a release must have Apple's Developer ID trust anchor.
REQ=$(codesign -d -r- "$APP" 2>/dev/null | sed 's/^designated => //')
echo "    requirement: $REQ"
case "$REQ" in
  *"anchor apple"*) ;;
  *) echo "error: not signed with an Apple Developer ID certificate" >&2; exit 1 ;;
esac
FLAGS=$(codesign -d -vvv "$APP" 2>&1 | sed -n 's/^.*flags=\([^)]*\).*$/\1/p')
case "$FLAGS" in
  *runtime*) ;;
  *) echo "error: hardened runtime is missing; Apple will reject notarization" >&2; exit 1 ;;
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
codesign --force --sign "$IDENTITY" --timestamp "$DMG"
echo "    $DMG ($(du -h "$DMG" | cut -f1))"

if [ "${REQUIRE_NOTARIZATION:-0}" = "1" ]; then
  : "${NOTARYTOOL_PROFILE:?set NOTARYTOOL_PROFILE when notarization is required}"
  echo "==> Notarizing disk image"
  NOTARY_ARGS=(--keychain-profile "$NOTARYTOOL_PROFILE" --wait)
  if [ -n "${NOTARYTOOL_KEYCHAIN:-}" ]; then
    NOTARY_ARGS+=(--keychain "$NOTARYTOOL_KEYCHAIN")
  fi
  NOTARY_RESULT=$(xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --output-format json)
  printf '%s\n' "$NOTARY_RESULT"
  NOTARY_ID=$(printf '%s' "$NOTARY_RESULT" | plutil -extract id raw -)
  NOTARY_STATUS=$(printf '%s' "$NOTARY_RESULT" | plutil -extract status raw -)
  if [ "$NOTARY_STATUS" != "Accepted" ]; then
    LOG_ARGS=(--keychain-profile "$NOTARYTOOL_PROFILE")
    if [ -n "${NOTARYTOOL_KEYCHAIN:-}" ]; then
      LOG_ARGS+=(--keychain "$NOTARYTOOL_KEYCHAIN")
    fi
    xcrun notarytool log "$NOTARY_ID" "${LOG_ARGS[@]}"
    echo "error: Apple notarization status is $NOTARY_STATUS" >&2
    exit 1
  fi
  xcrun stapler staple -v "$DMG"
  xcrun stapler validate -v "$DMG"
fi

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
