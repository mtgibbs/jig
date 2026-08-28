#!/usr/bin/env bash
# exec-container.sh — the container executor binding for the build loop.
#
# Thin by contract (specs/executor-binding §3, §7): take the prompt as $1, read ROOT from the
# environment, run the tool, let stdout be the transcript. No retry, no gate, no evidence, no
# stopping logic — the loop owns all of that. If this file ever grows a decision, the decision
# belongs in the loop, or every future binding has to reimplement it.
set -uo pipefail
R="${ROOT:-$PWD}"
exec "${LOOP_RUNTIME:-docker}" run --rm -v "$R:$R" -w "$R" -e ROOT="$R" --user "$(id -u):$(id -g)" --network "${LOOP_NETWORK:-ai-internal}" "${LOOP_IMAGE:-ghcr.io/mtgibbs/loop-executor:latest}" "$1"
