#!/usr/bin/env bash
# Convergence gate for 20260828l — end state only; runs after the task gates.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
. "$ROOT/specs/20260828l-run-control/lib/fixtures.sh"
mkexec

# AC-END-1 — the whole point: an interrupted run is picked up where it stopped.
mkloop "$T/r" yes
echo a > "$T/r/a.txt"; ( cd "$T/r" && git add -A && git commit -qm part ) >/dev/null 2>&1
runloop "$T/r"
if [ "$RC" != 0 ]; then
  no "end-1: re-running a partially complete spec exited $RC. Loop said: $(loopout r)"
elif [ ! -f "$T/r/b.txt" ]; then
  no "end-1: the loop did not reach the incomplete task — b.txt was never built. Loop said: $(loopout r)"
elif [ "$(execs "$T/r")" != 1 ]; then
  no "end-1: the executor ran $(execs "$T/r") times; exactly the one incomplete task should have run"
else
  ok "end-1: an interrupted run resumes at the first incomplete task, paying for nothing already done"
fi

# AC-END-2 — the fallback stays exactly as it was.
mkloop "$T/m" no
runloop "$T/m"
if [ "$RC" != 0 ]; then
  no "end-2: a spec with no tasks/ exited $RC. Loop said: $(loopout m)"
elif [ "$(execs "$T/m")" -lt 2 ]; then
  no "end-2: a spec with no tasks/ ran the executor $(execs "$T/m") times — monolithic specs must be untouched"
else
  ok "end-2: a spec with no per-task gates behaves exactly as before"
fi
gate_done
