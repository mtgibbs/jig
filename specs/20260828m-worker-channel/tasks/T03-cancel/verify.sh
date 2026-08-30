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

# ac4 — it stops PROMPTLY, measured against a slow executor.
#
# ac1 cannot see this. Its executor returns instantly, so "stops promptly" and "stops whenever the
# current attempt happens to end" produce the same reading, and an implementation that only checks
# between attempts passes it while taking up to RALPH_EXEC_TIMEOUT — 25 minutes by default — to
# notice. That is not a stop button, it is a request. Measured 2026-08-28: a run cancelled six
# minutes into an attempt kept running, with ac1 green.
cat > "$T/slowexec.sh" <<'X'
#!/usr/bin/env bash
echo "invoked" >> "$ROOT/execlog.txt"
sleep 120
echo a > "$ROOT/a.txt"
X
chmod +x "$T/slowexec.sh"
coord_start none
mkloop "$T/s"
( cd "$T/s" && bound 200 env HARNESS_REPORT_URL="$COORD_URL" RALPH_LOG=off RALPH_CANCEL_POLL=5     RALPH_EXEC_CMD="$T/slowexec.sh" RALPH_AGENT=gate     bash scripts/ralph-build.sh specs/fx ) > "$T/s.out" 2>&1 &
_lp=$!
sleep 20
coord_say cancel
_t0="$(date +%s)"
wait "$_lp"; _rc=$?
_el=$(( $(date +%s) - _t0 ))
coord_stop
if [ "$(grep -c invoked "$T/s/execlog.txt" 2>/dev/null || echo 0)" -lt 1 ]; then
  no "ac4: the slow executor never ran, so nothing was interrupted — the fixture is wrong, not the implementation"
elif [ "$_rc" = 124 ]; then
  no "ac4: the run never returned after a cancel was parked mid-executor"
elif [ "$_el" -gt 30 ]; then
  no "ac4: the run took ${_el}s to stop after a cancel was parked while the executor was running. A cancel collected only between attempts waits out the whole attempt, which is up to RALPH_EXEC_TIMEOUT"
elif ! grep -qi 'cancel' "$T/s.out"; then
  no "ac4: it stopped in ${_el}s but never said it was cancelled"
else
  ok "ac4: a cancel is collected mid-executor and stops the run within ${_el}s"
fi

gate_done
