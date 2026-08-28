#!/usr/bin/env bash
# T01 — the loop reports its status outward, and is unchanged when nothing is listening for it.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'coord_stop 2>/dev/null; rm -rf "$T"' EXIT
. "$ROOT/specs/20260828m-worker-channel/lib/fixtures.sh"
mkexec

# ac1 — the portability bar, asserted against a CONTROL rather than against wordings I imagined.
# "Behaves exactly as today" is only checkable by running today's code: the same fixture with
# main's ralph-status.sh, compared line for line with digits stripped. An earlier version of this
# grepped for phrases like "coordinator" and survived a mutant that announced itself as
# "reporting to http://..." — enumerating spellings only detects the spellings you thought of.
mkloop "$T/off"; runloop "$T/off"
mkloop "$T/ctl"
git -C "$ROOT" show origin/main:scripts/ralph-status.sh > "$T/ctl/scripts/ralph-status.sh" 2>/dev/null
runloop "$T/ctl"
# Normalise what is inherently per-run: commit sha, pid, timestamp, temp path. Hex tokens go
# first — an earlier version stripped only digits and tripped on the commit line.
norm() { sed -e 's/\b[0-9a-f]\{4,\}\b//g' -e 's/[0-9]\+//g' -e 's#/tmp/[^ ]*##g' "$1" | grep -av '^$'; }
if [ "$RC" != 0 ]; then
  no "ac1: with no coordinator configured the run exited $RC — an unconfigured channel is not a degraded mode. Loop said: $(loopout off)"
elif ! [ -s "$T/ctl/scripts/ralph-status.sh" ]; then
  no "ac1: could not fetch main's ralph-status.sh for the control — the comparison did not run"
elif ! diff -q <(norm "$T/off.out") <(norm "$T/ctl.out") >/dev/null 2>&1; then
  no "ac1: an unconfigured run differs from the same run on main's ralph-status.sh: $(diff <(norm "$T/off.out") <(norm "$T/ctl.out") | head -4 | tr '\n' ' ' | cut -c1-260)"
else
  ok "ac1: with no coordinator configured the loop is line-for-line the run it is today"
fi

# ac2 — the record goes out, keyed by the identity the loop already has.
coord_start none
mkloop "$T/on"; runloop "$T/on" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN"
n="$(posts /status)"
if [ "$RC" != 0 ]; then
  no "ac2: the run exited $RC with a coordinator configured. Loop said: $(loopout on)"
elif [ "$n" -lt 2 ]; then
  no "ac2: only $n status posts arrived for a 2-task run — every hb_write must also report. Coordinator saw: $(cut -c1-160 "$T/coord.log" | head -3 | tr '\n' ' ')"
elif ! grep -q '"p": *"/runs/[^"]*/status"' "$T/coord.log"; then
  no "ac2: status posts did not go to /runs/{run_key}/status — paths were $(grep -o '"p": *"[^"]*"' "$T/coord.log" | sort -u | head -3 | tr '\n' ' ')"
elif ! grep -q '"auth": *"Bearer ' "$T/coord.log"; then
  no "ac2: the status post carried no Authorization: Bearer header"
elif ! python3 -c "
import json,sys
# The body is JSON-ENCODED INSIDE the log line, so a grep for '\"phase\"' never matches it —
# decode rather than pattern-match, or this assertion fails a correct implementation.
for ln in open(sys.argv[1]):
    try: rec = json.loads(ln)
    except Exception: continue
    if rec.get('m') != 'POST' or '/status' not in rec.get('p',''): continue
    try: body = json.loads(rec.get('b') or '{}')
    except Exception: continue
    if 'phase' in body and 'task_index' in body: sys.exit(0)
sys.exit(1)" "$T/coord.log"; then
  no "ac2: the posted body is not the status record — no phase/task_index. Body was: $(python3 -c "
import json,sys
for ln in open(sys.argv[1]):
    try: r=json.loads(ln)
    except Exception: continue
    if '/status' in r.get('p',''): print((r.get('b') or '')[:150]); break" "$T/coord.log")"
else
  ok "ac2: every status is POSTed to /runs/{run_key}/status with the bearer token and the record intact"
fi
coord_stop

# ac3 — fail open. A coordinator that is not there must never stop a build.
mkloop "$T/dead"
_t0=$(date +%s)
runloop "$T/dead" HARNESS_REPORT_URL="http://127.0.0.1:1" HARNESS_REPORT_TOKEN="$TOKEN"
_t1=$(date +%s)
if [ "$RC" = 124 ]; then
  no "ac3: an unreachable coordinator hung the run — every call must be bounded"
elif [ "$RC" != 0 ]; then
  no "ac3: an unreachable coordinator failed the run (exit $RC) — reporting is observability, and a build that dies because a dashboard is down is worse than no dashboard. Loop said: $(loopout dead)"
elif [ $((_t1-_t0)) -ge 150 ]; then
  no "ac3: the run took $((_t1-_t0))s against a dead coordinator — it completed, but the calls are not bounded tightly enough to be free"
else
  ok "ac3: an unreachable coordinator neither fails nor stalls the run"
fi

# ac4 — the credential never comes back out, in any file the run leaves behind.
if grep -rqF "$TOKEN" "$T/on.out" "$T/on/.evidence" 2>/dev/null; then
  no "ac4: the bearer token appeared in the loop's own output or evidence — it must never be echoed"
else
  ok "ac4: the token never appears in the loop's output or evidence"
fi
gate_done
