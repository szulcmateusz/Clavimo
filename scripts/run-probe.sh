#!/bin/sh
# Launches the probe bundle through LaunchServices so it runs as its own
# app (with its own privacy permissions), waits for it to exit, and prints
# its output. Arguments are passed to the probe, e.g.:
#   scripts/run-probe.sh status
#   scripts/run-probe.sh request-access
#   scripts/run-probe.sh run --seconds 120
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/Modweave Probe.app"
LOG=$(mktemp -t modweave-probe)
trap 'rm -f "$LOG"' EXIT

if [ ! -d "$APP" ]; then
    echo "Missing $APP; run scripts/build-probe-app.sh first." >&2
    exit 1
fi

open -W -n --stdout "$LOG" --stderr "$LOG" "$APP" --args "$@"
cat "$LOG"
