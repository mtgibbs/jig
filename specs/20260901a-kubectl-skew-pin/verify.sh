#!/usr/bin/env bash
# Convergence gate for 20260901a-kubectl-skew-pin: runs every task gate in order and owns no checks
# of its own beyond end-state convergence. Nothing is staged for later here.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
fail=0
for g in "$T"/tasks/T*/verify.sh; do
  echo "── $(basename "$(dirname "$g")") ──"
  bash "$g" || fail=1
done
[ "$fail" -eq 0 ] && { echo "VERIFY: all task gates passed"; exit 0; }
echo "VERIFY: task-gate failures above" >&2
exit 1
