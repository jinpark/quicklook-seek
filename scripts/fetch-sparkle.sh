#!/bin/bash
# Download the pinned Sparkle release into vendor/Sparkle (gitignored).
# build.sh runs this automatically when vendor/Sparkle is missing.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="2.10.1"
SHA256="1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27"
URL="https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz"

DEST="vendor/Sparkle"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Sparkle $VERSION…"
curl -fsSL -o "$TMP/sparkle.tar.xz" "$URL"
echo "$SHA256  $TMP/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null || {
  echo "error: Sparkle download checksum mismatch" >&2
  exit 1
}

mkdir -p "$TMP/x"
tar -xJf "$TMP/sparkle.tar.xz" -C "$TMP/x"
codesign --verify --deep --strict "$TMP/x/Sparkle.framework"

rm -rf "$DEST"
mkdir -p "$DEST"
ditto "$TMP/x/Sparkle.framework" "$DEST/Sparkle.framework"
ditto "$TMP/x/bin" "$DEST/bin"
echo "$VERSION" > "$DEST/VERSION"
echo "Sparkle $VERSION is in $DEST"
