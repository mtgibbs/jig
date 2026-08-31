#!/usr/bin/env bash
# T03 gate — the b/c/h gates that pinned the hatch or the guard are reworked (they run
# GREEN against the new loop) and each spec's Tuning log records why.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

for s in 20260831b-scrub-monolithic-gates 20260831c-noop-defers-to-per-task-gates 20260831h-single-task-resume; do
  out="$(bash "$R/specs/$s/verify.sh" 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] \
    && ok "ac1: $s's gate is green against the hatchless loop" \
    || no "ac1: $s's gate fails (rc=$rc): $(printf '%s' "$out" | grep FAIL | head -2 | tr '\n' ' ')"
  grep -q '20260831p' "$R/specs/$s/spec.md" \
    && ok "ac2: $s's Tuning log records the change" \
    || no "ac2: $s's spec.md has no Tuning entry citing 20260831p"
done

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
