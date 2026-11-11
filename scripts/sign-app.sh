#!/bin/sh
# Signs an app bundle with the local development identity when it exists
# (see setup-local-signing.sh), otherwise ad-hoc.
# Usage: scripts/sign-app.sh <bundle> <bundle-identifier>
set -eu

APP=$1
IDENTIFIER=$2
DIR="$HOME/Library/Application Support/ClavimoDev"
KEYCHAIN="$DIR/signing.keychain-db"
NAME="Clavimo Local Development"

if [ -f "$KEYCHAIN" ] && [ -f "$DIR/keychain-password" ]; then
    security unlock-keychain -p "$(cat "$DIR/keychain-password")" "$KEYCHAIN"
    codesign --force --keychain "$KEYCHAIN" --sign "$NAME" --identifier "$IDENTIFIER" "$APP"
    echo "Signed with local identity \"$NAME\" (permissions persist across rebuilds)."
else
    codesign --force --sign - --identifier "$IDENTIFIER" "$APP"
    echo "Signed ad-hoc (permissions must be granted again after each rebuild)."
fi
codesign --verify --strict "$APP"
