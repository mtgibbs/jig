#!/usr/bin/env bash
# Convergence gate for 20260830a-worker-credentials.
#
# ralph runs this after every task and once more with STRICT=1. Checks here are whole-spec
# outcomes, not per-task criteria — the per-task gates under tasks/ own those.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"; else echo "  pend  $1 (not built yet)"; fi; }

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  end-0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

D="$ROOT/scripts/dispatch/dispatcher.py"
[ -f "$D" ] || { no "end-0: scripts/dispatch/dispatcher.py is missing"; gate_done; }

# end-1 — Outcome 5: the resolution exists and is a MAP, not a chain. Presence-gated on the
# artifact so it arms as soon as T1 lands, in whatever order the model builds.
if ! grep -q 'def worker_secret' "$D"; then
  pend "end-1: worker_secret()"
else
  probe() { ( cd "$ROOT/scripts/dispatch" && python3 -c "
import sys, os; sys.path.insert(0,'.')
import dispatcher as d
$1" 2>&1 ) | tail -1; }
  out="$(probe "
for k in list(os.environ):
    if k.startswith('HARNESS_WORKER_SECRET'): os.environ.pop(k, None)
os.environ['HARNESS_WORKER_SECRET_A_B'] = 'sa'
print('R:%s|%s|%s' % (d.worker_secret('a-b',''), d.worker_secret('other',''), d.worker_secret('','')))
")"
  case "$out" in
    "R:sa||") ok "end-1: worker_secret resolves per strategy, and resolves to nothing otherwise" ;;
    *)        no "end-1: worker_secret is not a plain per-strategy map [$out] — a fallback chain is what makes one worker able to hold another's credentials" ;;
  esac
fi

# end-2 — Outcome 1 & the §7 norm: only NAMES are rendered, never a value. Asserted by handing the
# resolver a value-shaped string and checking the Job carries the NAME it was given and nothing
# resembling a secret body.
if ! grep -q 'def worker_secret' "$D"; then
  pend "end-2: no rendered Job to inspect"
else
  out="$( cd "$ROOT/scripts/dispatch" && python3 -c "
import sys, os, json; sys.path.insert(0,'.')
import dispatcher as d
CAP=[]; d.launch = lambda job, **kw: (CAP.append(job), 0)[1]
for k in list(os.environ):
    if k.startswith('HARNESS_WORKER_SECRET'): os.environ.pop(k, None)
os.environ['HARNESS_WORKER_SECRET'] = 'worker-creds'
d.launch_run('r','s','build-converge','end2', ledger_path='$T/l', image='i:1', namespace='ns')
blob = json.dumps(CAP[0]) if CAP else ''
print('R:' + ('NAME-ONLY' if 'worker-creds' in blob and 'value' not in blob.lower().split('secretref')[-1][:80] else 'CHECK'))
" 2>&1 | tail -1 )"
  [ "$out" = "R:NAME-ONLY" ] \
    && ok "end-2: the Job carries the secret's NAME and no credential value" \
    || no "end-2: could not confirm the rendered Job carries only a name [$out]"
fi

# end-3 — Outcome 2 & 3, the regression guard. Always armed: this is behaviour that already works,
# not a staged deliverable. An unconfigured dispatcher must render exactly what it renders today,
# which is what lets a laptop and a local container ignore every Kubernetes concept in this spec.
out="$( cd "$ROOT/scripts/dispatch" && python3 -c "
import sys, os; sys.path.insert(0,'.')
import dispatcher as d
CAP=[]; d.launch = lambda job, **kw: (CAP.append(job), 0)[1]
for k in list(os.environ):
    if k.startswith('HARNESS_WORKER_SECRET') or k.startswith('HARNESS_WORKER_IMAGE'): os.environ.pop(k, None)
d.launch_run('r','s','build-converge','end3', ledger_path='$T/l3', image='i:1', namespace='ns')
c = CAP[0]['spec']['template']['spec']['containers'][0] if CAP else {}
print('R:' + ('CLEAN' if 'envFrom' not in c and c.get('image')=='i:1' else 'DIRTY'))
" 2>&1 | tail -1 )"
[ "$out" = "R:CLEAN" ] \
  && ok "end-3: an unconfigured dispatcher renders the Job it renders today" \
  || no "end-3: an unconfigured dispatcher no longer renders today's Job [$out]. Every deployment that exists sets neither variable"

gate_done
