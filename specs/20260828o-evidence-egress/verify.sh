#!/usr/bin/env bash
# Convergence gate — the finished end state, not any one task's criteria.
# The per-task gates under tasks/ carry the detail; this asserts only what is true once all of
# them are done, which is the question "is the spec finished" rather than "is task N done".
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260828o-evidence-egress/lib/fixtures.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

# One run, every kind. A reader opening a finished attempt should find all of it there.
coord_start
mkexec_loud; mkloop_logged "$T/all"
runloop_logged "$T/all" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN"
missing=""
for k in prompt gate patch meta log; do
  [ "$(arts "$k")" -gt 0 ] 2>/dev/null || missing="$missing $k"
done
if [ "$RC" != 0 ]; then
  no "ac1: a reporting run exited $RC. Loop said: $(loopout all)"
elif [ -n "$missing" ]; then
  no "ac1: a finished attempt did not ship:$missing. Arrived: [$(grep -o '/artifacts/[a-z]*' "$T/coord.log" | sort -u | tr '\n' ' ')]"
else
  ok "ac1: every artifact a passing attempt produces reaches the coordinator"
fi
coord_stop

# The failing path ships its diff — the artifact a reader most needs and the only one that
# exists nowhere else once the reset has run.
coord_start
mkexec_fail; mkloop_logged "$T/bad"
runloop_logged "$T/bad" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN"
if [ "$(arts diff)" -lt 1 ] 2>/dev/null; then
  no "ac2: a failing attempt shipped no diff — the work it discarded left no trace anywhere"
else
  ok "ac2: a failing attempt ships the diff of what it discarded"
fi
coord_stop

# Portability: the bar the whole design exists to preserve.
mkexec_loud; mkloop_logged "$T/off"; runloop_logged "$T/off"
if [ "$RC" != 0 ]; then
  no "ac3: with no coordinator configured the run exited $RC. Loop said: $(loopout off)"
elif grep -qiE 'curl:|urlopen|connection refused|traceback' "$T/off.out"; then
  no "ac3: an unconfigured run printed transport noise: $(grep -iE 'curl:|urlopen|traceback' "$T/off.out" | head -1 | cut -c1-160)"
else
  ok "ac3: with no coordinator configured the loop runs exactly as it always did"
fi

DOC="$(grep -rl '/artifacts/' "$ROOT/docs" 2>/dev/null | head -1)"
if [ -z "$DOC" ]; then
  no "ac4: the channel is not documented anywhere under docs/"
else
  ok "ac4: the channel is documented in $(basename "$DOC")"
fi

gate_done
