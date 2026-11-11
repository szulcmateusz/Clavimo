#!/bin/sh
# Runs one package's tests. On failure, repeats the first error lines as
# GitHub annotations so they are visible on the run summary.
#
# Usage: scripts/ci-test.sh Packages/ClavimoCore
set -u
LOG=$(mktemp)
swift test --package-path "$1" >"$LOG" 2>&1
status=$?
cat "$LOG"
if [ "$status" -ne 0 ]; then
    grep -E "error:|✘|recorded an issue|Fatal error" "$LOG" | head -20 | while IFS= read -r line; do
        echo "::error title=$1::$(printf '%s' "$line" | cut -c1-500)"
    done
fi
rm -f "$LOG"
exit "$status"
