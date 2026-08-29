#!/usr/bin/env bash
# MUTANT: ac6
# TARGET: scripts/exec-container.sh
# WHY: keeps the :latest default while adding LOOP_TAG, so the file gains a version knob and
# WHY: still resolves, by default, to a tag CI has never pushed. The knob makes it LOOK fixed.
# exec-container.sh — the container executor binding for the build loop.
set -uo pipefail
R="${ROOT:-$PWD}"
LOOP_TAG="${LOOP_TAG:-latest}"
exec "${LOOP_RUNTIME:-docker}" run --rm -v "$R:$R" -w "$R" -e ROOT="$R" --user "$(id -u):$(id -g)" --network "${LOOP_NETWORK:-ai-internal}" "${LOOP_IMAGE:-ghcr.io/mtgibbs/loop-executor:latest}" "$1"
