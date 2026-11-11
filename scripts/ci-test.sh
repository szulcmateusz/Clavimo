#!/bin/sh
# Runs one package's tests. On failure, repeats the first error lines as
# GitHub annotations so they are visible on the run summary. When the
# test process crashes, the tests that started but never finished are
# reported too, from a second run without parallelism.
#
# Usage: scripts/ci-test.sh Packages/ClavimoCore
set -u
LOG=$(mktemp)
swift test --package-path "$1" >"$LOG" 2>&1
status=$?
cat "$LOG"

unfinished() {
    # Swift Testing prints "Test X started." and later "Test X passed/failed".
    # Cases of parameterized tests finish with their test, not one by one.
    sed -En 's/^.*Test (.*) started\.$/\1/p' "$1" | grep -v -e '^case ' -e '^run$' | sort -u >"$1.started"
    sed -En 's/^.*Test (.*) (passed|failed) after .*$/\1/p' "$1" | sed -E 's/ with [0-9]+ test cases?$//' | sort -u >"$1.finished"
    comm -23 "$1.started" "$1.finished" | head -10
    rm -f "$1.started" "$1.finished"
}

if [ "$status" -ne 0 ]; then
    grep -E "error:|✘|recorded an issue|Fatal error" "$LOG" | head -20 | while IFS= read -r line; do
        echo "::error title=$1::$(printf '%s' "$line" | cut -c1-500)"
    done
    if grep -q "unexpected signal" "$LOG"; then
        SERIAL=$(mktemp)
        swift test --package-path "$1" --no-parallel >"$SERIAL" 2>&1
        grep -E "Fatal error|unexpected signal" "$SERIAL" | head -5 | while IFS= read -r line; do
            echo "::error title=$1 (serial run)::$(printf '%s' "$line" | cut -c1-500)"
        done
        unfinished "$SERIAL" | while IFS= read -r name; do
            echo "::error title=$1 crashed in::$(printf '%s' "$name" | cut -c1-500)"
        done
        rm -f "$SERIAL"
    fi
fi
rm -f "$LOG"
exit "$status"
