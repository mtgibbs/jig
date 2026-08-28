#!/usr/bin/env bash
# T03 — the loop notices a cancel while polling, and nothing else is ever read as one.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'coord_stop 2>/dev/null; rm -rf "$T"' EXIT
. "$ROOT/specs/20260828m-worker-channel/lib/fixtures.sh"
mkexec

# ac1 — a cancel stops the run, distinctly.
coord_start cancel
mkloop "$T/c"; runloop "$T/c" HARNESS_REPORT_URL="$COORD_URL"
if [ "$RC" = 124 ]; then
  no "ac1: the run did not return within 180s under a cancel intent"
elif [ "$RC" = 0 ]; then
  no "ac1: a cancel intent left the run reporting success — a cancelled run is neither a pass nor a gate failure. Loop said: $(loopout c)"
elif [ "$(execs "$T/c")" -ge 2 ]; then
  no "ac1: the run completed both tasks despite a cancel intent (executor ran $(execs "$T/c") times)"
elif ! grep -qi 'cancel' "$T/c.out"; then
  no "ac1: the run stopped but never said it was cancelled — a reader cannot tell it from a gate failure. Loop said: $(loopout c)"
else
  ok "ac1: a cancel intent stops the run cleanly and says so"
fi
if [ "$(posts /control)" -ge 1 ]; then
  ok "ac2: the loop polls for an intent rather than waiting to be told"
else
  no "ac2: no control poll reached the coordinator — nothing can connect INTO a worker, so an intent must be fetched"
fi
coord_stop

# ac3 — fail open on the channel, closed on the intent. Three ways to be unreadable, none a cancel.
for mode in 500 BROKEN dead; do
  if [ "$mode" = dead ]; then url="http://127.0.0.1:1"; else coord_start "$mode"; url="$COORD_URL"; fi
  mkloop "$T/x"; runloop "$T/x" HARNESS_REPORT_URL="$url"
  [ "$mode" = dead ] || coord_stop
  if [ "$RC" != 0 ]; then
    no "ac3: an unreadable control answer ($mode) stopped the run — fail open on the channel, closed on the intent. Loop said: $(loopout x)"
    bad=1; break
  fi
done
[ "${bad:-0}" = 1 ] || ok "ac3: a 500, an unparseable body and an absent coordinator are all 'carry on', never a cancel"
gate_done
