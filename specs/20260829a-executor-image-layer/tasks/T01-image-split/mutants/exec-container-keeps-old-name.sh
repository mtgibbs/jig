#!/usr/bin/env bash
# MUTANT: ac6
# TARGET: scripts/exec-container.sh
# WHY: fixes the :latest half and misses the rename half — it pins a REAL tag on the image name
# WHY: CI no longer publishes. The obvious check, "is the default still :latest", passes; the
# WHY: default resolves to a repository that stops receiving tags the day this lands.
# exec-container.sh — the container executor binding for the build loop.
set -uo pipefail
R="${ROOT:-$PWD}"
exec "${LOOP_RUNTIME:-docker}" run --rm -v "$R:$R" -w "$R" -e ROOT="$R" --user "$(id -u):$(id -g)" --network "${LOOP_NETWORK:-ai-internal}" "${LOOP_IMAGE:-ghcr.io/mtgibbs/loop-executor:0.1.0}" "$1"
