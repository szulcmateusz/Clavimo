#!/bin/sh
# Builds the Modweave menu bar app as a universal bundle.
#
# Usage: scripts/build-app.sh [--install]
#   --install  copy the bundle to ~/Applications/Modweave.app (no admin
#              rights needed) and restart it if it was running.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT_DIR="$ROOT/build"
# Provisional identifiers; the public name is not final.
BUNDLE_ID=${MODWEAVE_BUNDLE_ID_PREFIX:-dev.modweave}.app
DISPLAY_NAME=${MODWEAVE_DISPLAY_NAME:-Modweave}
VERSION=0.1.0
APP="$OUT_DIR/Modweave.app"
PACKAGE="$ROOT/Packages/ModweaveApp"

swift build --package-path "$PACKAGE" -c release --arch arm64 --arch x86_64 --product Modweave
BIN_DIR=$(swift build --package-path "$PACKAGE" -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/Modweave" "$APP/Contents/MacOS/Modweave"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Modweave</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>Modweave</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

"$ROOT/scripts/sign-app.sh" "$APP" "$BUNDLE_ID"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Modweave"))"

if [ "${1:-}" = "--install" ]; then
    DEST="$HOME/Applications/Modweave.app"
    WAS_RUNNING=false
    if pgrep -xq Modweave; then
        WAS_RUNNING=true
        osascript -e 'quit app id "'"$BUNDLE_ID"'"' >/dev/null 2>&1 || true
        sleep 1
    fi
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "Installed $DEST"
    if [ "$WAS_RUNNING" = true ]; then open "$DEST"; fi
fi
