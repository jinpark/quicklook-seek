#!/bin/bash
# Build QuickLook Seek.app.
#
#   ./build.sh            build into build/ (signed for local use)
#   ./build.sh install    build, copy to /Applications, and (re)launch
#   ./build.sh release    build, sign with Developer ID, notarize, staple, zip
#                         into dist/, and add a signed entry to appcast.xml
#
# Local builds sign with your "Developer ID Application" identity if you have
# one, else your first "Apple Development" identity (set CODESIGN_IDENTITY to
# override). macOS ties the Accessibility permission to the signing
# certificate, so signing local builds the same way as releases keeps it
# across rebuilds and Sparkle updates; ad-hoc signing ("-") loses it.
#
# Release builds need a "Developer ID Application" certificate (set
# DEVELOPER_ID to pick one), notarization credentials saved once with:
#   xcrun notarytool store-credentials quicklook-seek --apple-id <id> --team-id <team>
# (set NOTARY_PROFILE to use a different profile name), and the Sparkle
# update-signing key in your keychain (vendor/Sparkle/bin/generate_keys).
#
# SANDBOX=1 signs with Sandbox.entitlements (App Store-style sandbox test).
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-build}"
NAME="QuickLook Seek"
APP="build/$NAME.app"
plist() { /usr/libexec/PlistBuddy -c "Print $1" Info.plist; }
VERSION="$(plist CFBundleShortVersionString)"
BUILD_NUMBER="$(plist CFBundleVersion)"
MIN_MACOS="$(plist LSMinimumSystemVersion)"
NOTARY_PROFILE="${NOTARY_PROFILE:-quicklook-seek}"
SPARKLE_ACCOUNT="net.jinpark.quicklookseek"
GITHUB_REPO="jinpark/quicklook-seek"

find_identity() {
  security find-identity -v -p codesigning | awk -F'"' -v kind="$1" '$2 ~ "^" kind ":" { print $2; exit }'
}

case "$MODE" in
  build|install)
    IDENTITY="${CODESIGN_IDENTITY:-$(find_identity "Developer ID Application")}"
    IDENTITY="${IDENTITY:-$(find_identity "Apple Development")}"
    ;;
  release)
    IDENTITY="${DEVELOPER_ID:-$(find_identity "Developer ID Application")}"
    if [[ -z "$IDENTITY" ]]; then
      echo "error: no \"Developer ID Application\" certificate in your keychain." >&2
      echo "Create one in Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application" >&2
      echo "(requires a paid Apple Developer Program membership)." >&2
      exit 1
    fi
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
      echo "error: notarization profile \"$NOTARY_PROFILE\" not found or not working. Save it with:" >&2
      echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <id> --team-id <team>" >&2
      exit 1
    fi
    if [[ "${SANDBOX:-}" == 1 ]]; then
      echo "error: SANDBOX=1 isn't supported for releases (the app can't work sandboxed)." >&2
      exit 1
    fi
    if grep -q "<sparkle:version>$BUILD_NUMBER</sparkle:version>" appcast.xml; then
      echo "error: build $BUILD_NUMBER is already in appcast.xml; bump CFBundleVersion in Info.plist." >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 [build|install|release]" >&2
    exit 2
    ;;
esac

[[ -d vendor/Sparkle/Sparkle.framework ]] || scripts/fetch-sparkle.sh

# --- Build -------------------------------------------------------------------

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" \
    -F vendor/Sparkle -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    Sources/*.swift -o "build/QuickLookSeek-$arch"
done
lipo -create build/QuickLookSeek-arm64 build/QuickLookSeek-x86_64 \
  -output "$APP/Contents/MacOS/QuickLookSeek"
rm build/QuickLookSeek-arm64 build/QuickLookSeek-x86_64

# Embed Sparkle. Its XPC services are only needed by sandboxed apps.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
ditto vendor/Sparkle/Sparkle.framework "$SPARKLE"
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"

# --- Sign (inside out) -------------------------------------------------------

SIGN_ARGS=(--force --options runtime --sign "${IDENTITY:--}")
if [[ "$MODE" == release ]]; then
  SIGN_ARGS+=(--timestamp) # notarization requires a secure timestamp
fi
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/Autoupdate"
codesign "${SIGN_ARGS[@]}" "$SPARKLE/Versions/B/Updater.app"
codesign "${SIGN_ARGS[@]}" "$SPARKLE"
if [[ "${SANDBOX:-}" == 1 ]]; then
  SIGN_ARGS+=(--entitlements Sandbox.entitlements)
fi
codesign "${SIGN_ARGS[@]}" "$APP"
codesign --verify --strict --deep "$APP"
echo "Built $APP $VERSION ($BUILD_NUMBER), signed: ${IDENTITY:-ad-hoc}${SANDBOX:+, sandboxed}"

# --- Install -----------------------------------------------------------------

if [[ "$MODE" == install ]]; then
  pkill -x QuickLookSeek 2>/dev/null && sleep 1 || true
  rm -rf "/Applications/$NAME.app"
  ditto "$APP" "/Applications/$NAME.app"
  open "/Applications/$NAME.app"
  echo "Installed and launched /Applications/$NAME.app"
fi

# --- Notarize, staple, package, appcast --------------------------------------

if [[ "$MODE" == release ]]; then
  mkdir -p dist
  SUBMIT_ZIP="build/QuickLookSeek-notarize.zip"
  RELEASE_ZIP="dist/QuickLookSeek-$VERSION.zip"
  rm -f "$SUBMIT_ZIP" "$RELEASE_ZIP"
  ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"

  echo "Submitting to Apple for notarization (usually a few minutes)…"
  RESULT="$(xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format plist)"
  rm -f "$SUBMIT_ZIP"
  STATUS="$(plutil -extract status raw -o - - <<<"$RESULT")"
  SUBMISSION="$(plutil -extract id raw -o - - <<<"$RESULT")"
  if [[ "$STATUS" != Accepted ]]; then
    echo "error: notarization status: $STATUS (submission $SUBMISSION). Apple's log:" >&2
    xcrun notarytool log "$SUBMISSION" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    exit 1
  fi

  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose=2 "$APP"
  ditto -c -k --keepParent "$APP" "$RELEASE_ZIP"

  # Sign the update with the Sparkle key and add it to the top of appcast.xml.
  SIGNATURE="$(vendor/Sparkle/bin/sign_update --account "$SPARKLE_ACCOUNT" "$RELEASE_ZIP")"
  TAG="v$VERSION"
  ITEM="    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')</pubDate>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_MACOS</sparkle:minimumSystemVersion>
      <enclosure url=\"https://github.com/$GITHUB_REPO/releases/download/$TAG/QuickLookSeek-$VERSION.zip\" type=\"application/octet-stream\" $SIGNATURE/>
    </item>
"
  ITEM="$ITEM" perl -0pi -e 's/(<!-- items:[^\n]*\n)/$1$ENV{ITEM}/' appcast.xml

  echo
  echo "Release ready: $RELEASE_ZIP (appcast.xml updated). To publish:"
  echo "  gh release create $TAG \"$RELEASE_ZIP\" --repo $GITHUB_REPO --title \"$VERSION\""
  echo "  git add appcast.xml && git commit -m \"Release $VERSION\" && git push   # publishes appcast.xml"
fi
