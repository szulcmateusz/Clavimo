#!/bin/sh
# Checks commit messages against the project conventions:
# - Conventional Commits subject: type(scope)!: summary
# - subject of at most 72 characters without a trailing period
# - plain ASCII hyphens only: no en dash (U+2013) or em dash (U+2014)
#
# Usage:
#   scripts/check-commit-message.sh FILE         check one message file
#   scripts/check-commit-message.sh --range A..B check every commit in a range
set -eu

TYPES='feat|fix|docs|test|refactor|perf|build|ci|chore|style|revert'

check_message() {
    message_file=$1
    label=$2
    subject=$(grep -v '^#' "$message_file" | head -n 1)
    status=0
    if ! printf '%s\n' "$subject" | grep -Eq "^($TYPES)(\([a-z0-9][a-z0-9-]*\))?!?: [^ ].*[^.]$"; then
        echo "$label: subject must follow 'type(scope): summary' without a trailing period: $subject"
        status=1
    fi
    if [ "$(printf '%s' "$subject" | wc -m)" -gt 72 ]; then
        echo "$label: subject is longer than 72 characters"
        status=1
    fi
    if grep -v '^#' "$message_file" | LC_ALL=C grep -q "$(printf '\342\200\223')\|$(printf '\342\200\224')"; then
        echo "$label: use the ASCII hyphen '-' instead of en or em dashes"
        status=1
    fi
    return $status
}

if [ "${1:-}" = "--range" ]; then
    failed=0
    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT
    for commit in $(git rev-list --no-merges "$2"); do
        git log -1 --format=%B "$commit" > "$tmp"
        check_message "$tmp" "$(git rev-parse --short "$commit")" || failed=1
    done
    exit $failed
fi

check_message "$1" "commit message"
