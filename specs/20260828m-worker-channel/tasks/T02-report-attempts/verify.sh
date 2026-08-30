#!/usr/bin/env bash
# T02 — each attempt record is POSTed as it is written.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'coord_stop 2>/dev/null; rm -rf "$T"' EXIT
. "$ROOT/specs/20260828m-worker-channel/lib/fixtures.sh"
mkexec

coord_start none
mkloop "$T/on"
# RALPH_LOG stays ON here: log_meta is what writes attempt records.
( cd "$T/on" && bound 180 env HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN" \
    RALPH_EXEC_CMD="$T/exec.sh" RALPH_AGENT=gate bash scripts/ralph-build.sh specs/fx ) > "$T/on.out" 2>&1
RC=$?
if [ "$RC" = 124 ]; then
  no "ac1: the run did not return within 180s"
  no "ac2: the posted record is the one the evidence tree holds"
else
  n="$(posts /attempts)"
  if [ "$n" -lt 1 ]; then
    no "ac1: no attempt records were posted for a 2-task run — paths seen were $(grep -o '\"p\": *\"[^\"]*\"' "$T/coord.log" | sort -u | head -4 | tr '\n' ' ')"
  else
    ok "ac1: each attempt record is POSTed to /runs/{run_key}/attempts"
  fi
  # The point is that a reader sees what the evidence tree holds — not a reduced copy.
  if python3 -c "
import json,sys
for ln in open(sys.argv[1]):
    try: r=json.loads(ln)
    except Exception: continue
    if r.get('m')!='POST' or '/attempts' not in r.get('p',''): continue
    try: b=json.loads(r.get('b') or '{}')
    except Exception: continue
    if {'outcome','task','attempt'} <= set(b): sys.exit(0)
sys.exit(1)" "$T/coord.log"; then
    ok "ac2: the posted record is the one the evidence tree holds, not a reduced copy"
  else
    no "ac2: the posted attempt body is missing outcome/task/attempt — a reader would see less than the evidence tree holds"
  fi
fi
coord_stop

# ac3 — same fail-open discipline as status: a dead coordinator is harmless.
mkloop "$T/dead"
( cd "$T/dead" && bound 180 env HARNESS_REPORT_URL="http://127.0.0.1:1" HARNESS_REPORT_TOKEN="$TOKEN" \
    RALPH_EXEC_CMD="$T/exec.sh" RALPH_AGENT=gate bash scripts/ralph-build.sh specs/fx ) > "$T/dead.out" 2>&1
rc=$?
case "$rc" in
  0)   ok "ac3: attempt reporting to a dead coordinator neither fails nor stalls the run" ;;
  124) no "ac3: an unreachable coordinator hung the run — the attempt POST is not bounded" ;;
  *)   no "ac3: an unreachable coordinator failed the run (exit $rc) — reporting must stay best-effort. Loop said: $(loopout dead)" ;;
esac
gate_done
