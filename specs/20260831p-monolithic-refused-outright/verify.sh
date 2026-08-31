#!/usr/bin/env bash
# Convergence gate for 20260831p-monolithic-refused-outright — the union of the task
# gates, nothing more. Per-task criteria live in tasks/T*/verify.sh (20260828i layout).
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
fail=0
for g in "$T"/tasks/T*/verify.sh; do
  echo "── $(basename "$(dirname "$g")") ──"
  bash "$g" || fail=1
done

[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
