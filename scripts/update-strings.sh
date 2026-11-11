#!/bin/sh
# Updates the app's string catalog with every localizable string in the
# source, using the Swift compiler's extraction (the same data Xcode
# uses). New strings appear without translations; strings no longer in
# the source are marked stale. Run after changing user-facing text, then
# translate the new entries and run scripts/check-translations.py.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PACKAGE="$ROOT/Packages/ClavimoApp"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# A clean build so every file is compiled and emits its strings.
swift package --package-path "$PACKAGE" clean
swift build --package-path "$PACKAGE" \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$WORK"

set --
for file in "$WORK"/*.stringsdata; do
    set -- "$@" --stringsdata "$file"
done
xcrun xcstringstool sync "$PACKAGE/Resources/Localizable.xcstrings" "$@"
echo "Updated $PACKAGE/Resources/Localizable.xcstrings"
