#!/bin/sh
# Builds the Clavimo menu bar app as a universal bundle.
#
# Usage: scripts/build-app.sh [--install]
#   --install  copy the bundle to /Applications/Clavimo.app when that
#              folder is writable (admin accounts), otherwise to
#              ~/Applications, and restart it if it was running.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT_DIR="$ROOT/build"
BUNDLE_ID=${CLAVIMO_BUNDLE_ID_PREFIX:-dev.clavimo}.app
DISPLAY_NAME=${CLAVIMO_DISPLAY_NAME:-Clavimo}
# Marketing version (numbers only, as macOS requires), build number, and
# the release name shown in the app and used for release archives.
VERSION=1.3.1
BUILD=12
RELEASE_NAME=1.3.1
APP="$OUT_DIR/Clavimo.app"
PACKAGE="$ROOT/Packages/ClavimoApp"

swift build --package-path "$PACKAGE" -c release --arch arm64 --arch x86_64 --product Clavimo
BIN_DIR=$(swift build --package-path "$PACKAGE" -c release --arch arm64 --arch x86_64 --show-bin-path)

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Clavimo" "$APP/Contents/MacOS/Clavimo"

# App icon and menu bar glyphs are drawn from vector geometry.
ICONS="$OUT_DIR/icons"
swift "$ROOT/scripts/render-icon.swift" "$ICONS" >/dev/null
cp "$ICONS/AppIcon.icns" "$ICONS"/MenuBarIcon*.pdf "$APP/Contents/Resources/"

# Localizations: English is the source language; other languages come
# from the string catalog.
xcrun xcstringstool compile "$PACKAGE/Resources/Localizable.xcstrings" --output-directory "$APP/Contents/Resources"
mkdir -p "$APP/Contents/Resources/en.lproj"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Clavimo</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>pl</string>
        <string>de</string>
    </array>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>Clavimo</string>
    <key>CFBundleDisplayName</key>
    <string>$DISPLAY_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>ClavimoReleaseName</key>
    <string>$RELEASE_NAME</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

"$ROOT/scripts/sign-app.sh" "$APP" "$BUNDLE_ID"
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Clavimo"))"

if [ "${1:-}" = "--install" ]; then
    if [ -w /Applications ]; then
        DEST="/Applications/Clavimo.app"
    else
        DEST="$HOME/Applications/Clavimo.app"
    fi
    WAS_RUNNING=false
    if pgrep -xq Clavimo; then
        WAS_RUNNING=true
        osascript -e 'quit app id "'"$BUNDLE_ID"'"' >/dev/null 2>&1 || true
        sleep 1
    fi
    mkdir -p "$(dirname "$DEST")"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    echo "Installed $DEST"
    if [ "$WAS_RUNNING" = true ]; then open "$DEST"; fi
fi
