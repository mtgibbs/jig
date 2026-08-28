#!/usr/bin/env bash
# T04 — pause holds without spinning, stays visible, and releases.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'coord_stop 2>/dev/null; kill %1 2>/dev/null; rm -rf "$T"' EXIT
. "$ROOT/specs/20260828m-worker-channel/lib/fixtures.sh"
mkexec

# Hold for a while, then release: the loop must wait and then finish the work.
coord_start pause
mkloop "$T/p"
( sleep 25; coord_say none ) &
_t0=$(date +%s)
( cd "$T/p" && env HARNESS_REPORT_URL="$COORD_URL" RALPH_EXEC_CMD="$T/exec.sh" RALPH_AGENT=gate \
    timeout 180 bash scripts/ralph-build.sh specs/fx ) > "$T/p.out" 2>&1
RC=$?; _t1=$(date +%s); el=$((_t1-_t0))
if [ "$RC" = 124 ]; then
  no "ac1: the run never returned — a pause must hold, not hang forever"
  no "ac2: a paused run is visibly paused"
elif [ "$RC" != 0 ]; then
  no "ac1: the run failed under a pause that was later released (exit $RC). Loop said: $(loopout p)"
elif [ "$el" -lt 20 ]; then
  no "ac1: the run finished in ${el}s despite a 25s pause — the intent was not honoured"
elif [ "$(execs "$T/p")" -lt 2 ]; then
  no "ac1: the run was released but did not finish its work (executor ran $(execs "$T/p") times)"
else
  ok "ac1: a pause holds the loop and it resumes when the intent clears (${el}s)"
fi

# ac2 — visibly paused, and polling rather than spinning. A paused run that looks identical to a
# hung one is the failure this exists to avoid.
np="$(posts /control)"
if grep -qi 'pause' "$T/p.out" || grep -rqi 'paused' "$T/p/.evidence" 2>/dev/null; then
  if [ "$np" -gt 200 ]; then
    no "ac2: the loop polled $np times while paused — it is spinning, not sleeping between polls"
  else
    ok "ac2: a paused run says so and re-polls on an interval ($np polls)"
  fi
else
  no "ac2: nothing in the run's output or heartbeat says it was paused — indistinguishable from hung. Loop said: $(loopout p)"
fi
gate_done
