#!/usr/bin/env bash
# Convergence gate for 20260828m — end state only; runs after the task gates.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'kill %1 2>/dev/null; rm -rf "$T"' EXIT
. "$ROOT/specs/20260828m-worker-channel/lib/fixtures.sh"
mkexec

# AC-END-1 — the portability guarantee, against the control that defines it.
mkloop "$T/off"; runloop "$T/off"
mkloop "$T/ctl"
git -C "$ROOT" show origin/main:scripts/ralph-status.sh > "$T/ctl/scripts/ralph-status.sh" 2>/dev/null
git -C "$ROOT" show origin/main:scripts/ralph-log.sh    > "$T/ctl/scripts/ralph-log.sh" 2>/dev/null
git -C "$ROOT" show origin/main:scripts/ralph-build.sh  > "$T/ctl/scripts/ralph-build.sh" 2>/dev/null
runloop "$T/ctl"
norm() { sed -e 's/\b[0-9a-f]\{4,\}\b//g' -e 's/[0-9]\+//g' -e 's#/tmp/[^ ]*##g' "$1" | grep -av '^$'; }
if [ "$RC" != 0 ]; then
  no "end-1: the control run itself failed ($RC) — the comparison is meaningless"
elif diff -q <(norm "$T/off.out") <(norm "$T/ctl.out") >/dev/null 2>&1; then
  ok "end-1: with nothing configured, a run is line-for-line the run it is today"
else
  no "end-1: an unconfigured run differs from main: $(diff <(norm "$T/off.out") <(norm "$T/ctl.out") | head -4 | tr '\n' ' ' | cut -c1-260)"
fi

# AC-END-2 — a coordinator that ACCEPTS and never answers. Harsher than one that is absent:
# a refused connection returns instantly, a black hole is what actually finds a missing timeout.
python3 - "$T/hang.port" <<'PYX' &
import socket, sys, threading
s=socket.socket(); s.bind(("127.0.0.1",0)); s.listen(16)
open(sys.argv[1],"w").write(str(s.getsockname()[1]))
def hold():
    while True:
        try: c,_=s.accept()
        except Exception: return
        threading.Timer(600, c.close).start()   # accept, then never answer
threading.Thread(target=hold,daemon=True).start()
threading.Event().wait(3600)
PYX
i=0; while [ ! -s "$T/hang.port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
mkloop "$T/hang"
_t0=$(date +%s); runloop "$T/hang" HARNESS_REPORT_URL="http://127.0.0.1:$(cat "$T/hang.port")"; _t1=$(date +%s)
if [ "$RC" = 124 ]; then
  no "end-2: a coordinator that accepts and never answers hung the run — a bound is missing somewhere"
elif [ "$RC" != 0 ]; then
  no "end-2: a silent coordinator failed the run (exit $RC). Loop said: $(loopout hang)"
elif [ "$(execs "$T/hang")" -lt 2 ]; then
  no "end-2: the run completed but did not do its work against a silent coordinator"
else
  ok "end-2: a coordinator that accepts and never answers costs the run nothing but time ($((_t1-_t0))s)"
fi
gate_done
