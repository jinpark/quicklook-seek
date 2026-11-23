#!/bin/bash
# Build QuickLook Seek.app.
#
#   ./build.sh            build into build/
#   ./build.sh install    build, copy to /Applications, and (re)launch
#
# Signs with your first "Apple Development" identity if you have one (set
# CODESIGN_IDENTITY to override). A stable signature means macOS keeps the
# Accessibility permission across rebuilds; ad-hoc signing ("-") loses it.
set -euo pipefail
cd "$(dirname "$0")"

NAME="QuickLook Seek"
APP="build/$NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"

for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos13.0" \
    Sources/*.swift -o "build/QuickLookSeek-$arch"
done
lipo -create build/QuickLookSeek-arm64 build/QuickLookSeek-x86_64 \
  -output "$APP/Contents/MacOS/QuickLookSeek"
rm build/QuickLookSeek-arm64 build/QuickLookSeek-x86_64

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
ENTITLEMENTS=()
if [[ "${SANDBOX:-}" == 1 ]]; then
  # App Sandbox build, as the Mac App Store requires.
  ENTITLEMENTS=(--entitlements Sandbox.entitlements)
fi
codesign --force --options runtime ${ENTITLEMENTS[@]+"${ENTITLEMENTS[@]}"} --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc}${SANDBOX:+, sandboxed})"

if [[ "${1:-}" == "install" ]]; then
  pkill -x QuickLookSeek 2>/dev/null && sleep 1 || true
  rm -rf "/Applications/$NAME.app"
  cp -R "$APP" /Applications/
  open "/Applications/$NAME.app"
  echo "Installed and launched /Applications/$NAME.app"
fi
