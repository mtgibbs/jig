#!/usr/bin/env bash
# run-key.sh — print the host discriminator for fleet-wide uniqueness
#   $RALPH_HOST_ID if set and non-empty, else hostname, else "unknown"
#   Sanitised to [A-Za-z0-9._-]; every other byte becomes _
set -uo pipefail

# Determine the base discriminator
if [ -n "${RALPH_HOST_ID:-}" ]; then
    DISCRIMINATOR="$RALPH_HOST_ID"
else
    HOSTNAME=$(hostname 2>/dev/null)
    if [ -n "$HOSTNAME" ]; then
        DISCRIMINATOR="$HOSTNAME"
    else
        DISCRIMINATOR="unknown"
    fi
fi

# Sanitise: keep only [A-Za-z0-9._-], replace everything else with _
RESULT=$(printf '%s' "$DISCRIMINATOR" | tr -c 'A-Za-z0-9._-' '_')

# Output with trailing newline
printf '%s\n' "$RESULT"

exit 0
