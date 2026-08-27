#!/usr/bin/env bash
# spec-field.sh — read a single key from a spec.md header block.
#   spec-field.sh <spec.md> <Key>     # one value per line, exit 0/1
#   spec-field.sh <spec.md> --list    # every declared key, one per line
# Exit 0: key declared (including 'none').
# Exit 1: key absent.
# Exit 2: usage error or unreadable file.
set -uo pipefail

usage() {
  echo "usage: spec-field.sh <spec.md> <Key> | --list" >&2
  exit 2
}

if [ $# -lt 2 ]; then
  usage
fi

SPEC_FILE="${1:-}"
KEY="${2:-}"

if [ -z "$SPEC_FILE" ] || [ -z "$KEY" ]; then
  usage
fi

if [ ! -r "$SPEC_FILE" ]; then
  usage
fi

# Extract header region: everything above the first --- line.
# Use sed to extract lines from start up to (but not including) the first ---.
HEADER=$(sed -n '1,/^---$/p' "$SPEC_FILE" | sed '$d')

# If KEY is --list, print every declared key.
if [ "$KEY" = "--list" ]; then
  # Match lines like "- **Key:** value" at start of line.
  # Extract just the Key part.
  echo "$HEADER" | sed -n 's/^- \*\*\([^:]*\):\*.*/\1/p' | sed '/^$/d'
  exit 0
fi

# Extract the value for the given key.
# Match "- **Key:** value" lines and print the value part.
VALUE=$(echo "$HEADER" | grep "^-[[:space:]]*\*\*$KEY:[[:space:]]*\*\*" | sed 's/^-[[:space:]]*\*\*[[:space:]]*\([A-Za-z]*\)[[:space:]]*:[[:space:]]*\*\*[[:space:]]*//')

if [ -z "$VALUE" ]; then
  # Key not found - exit 1, print nothing.
  exit 1
fi

# Parse comma-separated list, strip whitespace, drop empty entries.
# Output one value per line.
echo "$VALUE" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed '/^$/d'
exit 0
