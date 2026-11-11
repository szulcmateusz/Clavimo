#!/bin/sh
# Builds a release archive of Clavimo.app with a SHA256 checksum.
#
# Usage: scripts/package-release.sh
# Output: build/release/Clavimo-<version>.zip and .zip.sha256
#
# Release builds must be signed with the project's stable signing identity
# so that macOS keeps users' permissions across updates; the script stops
# if only ad-hoc signing is available.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$ROOT/scripts/build-app.sh"

APP="$ROOT/build/Clavimo.app"
if codesign -dv "$APP" 2>&1 | grep -q "Signature=adhoc"; then
    echo "Refusing to package an ad-hoc signed build; run scripts/setup-local-signing.sh first." >&2
    exit 1
fi
codesign --verify --strict --deep "$APP"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
OUT="$ROOT/build/release"
ZIP="$OUT/Clavimo-$VERSION.zip"
rm -rf "$OUT"
mkdir -p "$OUT"
ditto -c -k --norsrc --noextattr --keepParent "$APP" "$ZIP"
(cd "$OUT" && shasum -a 256 "Clavimo-$VERSION.zip" > "Clavimo-$VERSION.zip.sha256")

echo "Archive:  $ZIP"
echo "Checksum: $(cat "$ZIP.sha256")"
echo "Architectures: $(lipo -archs "$APP/Contents/MacOS/Clavimo")"
