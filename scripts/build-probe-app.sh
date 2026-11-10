#!/bin/sh
# Builds "Modweave Probe.app", a minimal bundle around the P0 probe so
# macOS attributes Accessibility and Input Monitoring to the probe itself
# instead of to the terminal that launched it.
#
# The bundle is ad-hoc signed. macOS ties privacy permissions to the code
# signature, so permissions must be granted again after every rebuild.
#
# Usage: scripts/build-probe-app.sh [output-dir]   (default: build)
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT_DIR=${1:-"$ROOT/build"}
# Provisional identifier; the public name and identifiers are not final.
BUNDLE_ID=${MODWEAVE_BUNDLE_ID_PREFIX:-dev.modweave}.probe
APP="$OUT_DIR/Modweave Probe.app"
PACKAGE="$ROOT/Packages/ModweaveQuartz"

swift build --package-path "$PACKAGE" -c release --arch arm64 --arch x86_64 --product modweave-probe
BIN_DIR=$(swift build --package-path "$PACKAGE" -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/modweave-probe" "$APP/Contents/MacOS/modweave-probe"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>modweave-probe</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>Modweave Probe</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/modweave-probe"))"
