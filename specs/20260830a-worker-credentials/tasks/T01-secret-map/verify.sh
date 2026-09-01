#!/usr/bin/env bash
# T1 — the per-strategy secret map, and the field it renders.
#
# Behavioural through the module's own API. `launch` is monkeypatched so nothing shells out to
# kubectl; the Job dict it is handed IS the assertion surface. Same shape as 20260829a T05, which
# is the gate this one is modelled on — a second style for the same module would mean two ways to
# read a dispatcher failure.
#
# Asserted on the rendered DICT, never on serialised YAML. A field rendered as None serialises to
# a line a text grep reads as present, which is exactly how an absence assertion goes blind.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

D="$ROOT/scripts/dispatch/dispatcher.py"
[ -f "$D" ] || { no "ac0: scripts/dispatch/dispatcher.py is missing"; gate_done; }

# probe <python-body> — run against the real module, print one line, never raise.
probe() {
  ( cd "$ROOT/scripts/dispatch" && python3 -c "
import sys, os, json
sys.path.insert(0, '.')
import dispatcher as d

CAPTURED = []
d.launch = lambda job, **kw: (CAPTURED.append(job), 0)[1]

def container(job):
    try:
        return job['spec']['template']['spec']['containers'][0]
    except Exception:
        return {}

def secret_of(job):
    try:
        return container(job)['envFrom'][0]['secretRef']['name']
    except Exception:
        return None

def has_envfrom(job):
    return 'envFrom' in container(job)

def image_of(job):
    return container(job).get('image')

# Amended 2026-08-31 (20260831t / issue #117): the intent moved from REPO/SPEC/STRATEGY env
# to argv in run-task.sh's calling convention — the env was a convention nothing in the
# worker read. The strategy now sits after --strategy in the container's args.
def strategy_of(job):
    a = container(job).get('args') or []
    for i, v in enumerate(a[:-1]):
        if v == '--strategy':
            return a[i + 1]
    return None

def clear():
    for k in list(os.environ):
        if k.startswith('HARNESS_WORKER_SECRET') or k.startswith('HARNESS_WORKER_IMAGE'):
            os.environ.pop(k, None)

$1
" 2>&1 ) | tail -1
}

L="$T/ledger"

# ── ac1: a per-strategy variable selects the secret ──────────────────────────────────────────
out="$(probe "
clear()
os.environ['HARNESS_WORKER_SECRET_BUILD_CODEX'] = 'worker-codex'
d.launch_run('r','s','build-codex','e1', ledger_path='$L.1', image='img:1', namespace='ns')
print('R:' + str(secret_of(CAPTURED[0]) if CAPTURED else 'NO-JOB'))
")"
case "$out" in
  R:worker-codex) ok "ac1: a per-strategy variable selects the worker secret" ;;
  R:None) no "ac1: the per-strategy variable was set and the Job carries no envFrom — the map does not exist, or it does not reach render_job" ;;
  *) no "ac1: unexpected probe result [$out]" ;;
esac

# ── ac2: the shared default covers every strategy ────────────────────────────────────────────
out="$(probe "
clear()
os.environ['HARNESS_WORKER_SECRET'] = 'worker-shared'
d.launch_run('r','s','judge-refine','e2', ledger_path='$L.2', image='img:1', namespace='ns')
print('R:' + str(secret_of(CAPTURED[0]) if CAPTURED else 'NO-JOB'))
")"
[ "$out" = "R:worker-shared" ] \
  && ok "ac2: with no per-strategy variable the shared default is used" \
  || no "ac2: the fallback to HARNESS_WORKER_SECRET is broken — got [$out]. A deployment that mints one secret for the whole fleet is the state this must not break"

# ── ac3: nothing configured renders NO envFrom key at all ────────────────────────────────────
# The absence AND the completeness, in one check. An absence assertion passes for free against a
# Job that failed to render, so "no envFrom" is only meaningful alongside "and the rest is here".
out="$(probe "
clear()
d.launch_run('r','s','build-converge','e3', ledger_path='$L.3', image='img:1', namespace='ns')
j = CAPTURED[0] if CAPTURED else {}
c = container(j)
# Amended 2026-08-31 (20260831t / #117): completeness reads args, not env — the intent
# rides argv now, and a container with no args is exactly the Job that cannot run.
complete = bool(c.get('image')) and bool(c.get('args')) and bool(j.get('spec',{}).get('template'))
print('R:' + ('ENVFROM-PRESENT' if has_envfrom(j) else 'ABSENT') + '|' + ('COMPLETE' if complete else 'INCOMPLETE'))
")"
case "$out" in
  "R:ABSENT|COMPLETE") ok "ac3: with nothing configured the Job carries no envFrom key, and is otherwise complete" ;;
  "R:ABSENT|INCOMPLETE") no "ac3: no envFrom, but the Job did not render either — the absence proves nothing. This is the control that stops a broken renderer reading as a clean one" ;;
  "R:ENVFROM-PRESENT|"*) no "ac3: an unconfigured dispatcher rendered an envFrom. An envFrom of [] or of None is a DIFFERENT object from no envFrom, and every deployment that exists today sets neither variable" ;;
  *) no "ac3: could not read the rendered Job [$out]" ;;
esac

# ── ac4: one strategy's secret is never another's ────────────────────────────────────────────
out="$(probe "
clear()
os.environ['HARNESS_WORKER_SECRET_BUILD_CODEX'] = 'worker-codex'
d.launch_run('r','s','build-converge','e4', ledger_path='$L.4', image='img:1', namespace='ns')
print('R:' + str(secret_of(CAPTURED[0]) if CAPTURED else 'NO-JOB'))
")"
case "$out" in
  R:None) ok "ac4: a sibling strategy's secret is not inherited" ;;
  R:worker-codex) no "ac4: build-converge was handed build-codex's secret. Falling back to a sibling is worse than falling back to nothing: every worker would carry every provider's key, which is the single thing this spec exists to prevent" ;;
  *) no "ac4: unexpected probe result [$out]" ;;
esac

# ── ac5: env, image and secret all come from the SAME requested strategy ─────────────────────
# The failure this task exists to make impossible, and all three halves read as correct alone.
out="$(probe "
clear()
os.environ['HARNESS_WORKER_IMAGE_BUILD_CODEX']  = 'ghcr.io/x/codex:1'
os.environ['HARNESS_WORKER_SECRET_BUILD_CODEX'] = 'worker-codex'
d.launch_run('r','s','build-codex','e5', ledger_path='$L.5', image='ghcr.io/x/default:1', namespace='ns')
j = CAPTURED[0] if CAPTURED else {}
print('R:' + str(strategy_of(j)) + '|' + str(image_of(j)) + '|' + str(secret_of(j)))
")"
case "$out" in
  "R:build-codex|ghcr.io/x/codex:1|worker-codex")
    ok "ac5: the Job's STRATEGY, its image and its secret come from the same requested strategy" ;;
  *) no "ac5: the three halves disagree [$out] — a run on one strategy's image carrying another's secret is the split this assertion exists to catch" ;;
esac

# ── ac6: no other key of the rendered Job moved ──────────────────────────────────────────────
out="$(probe "
clear()
d.launch_run('r','s','build-converge','e6', ledger_path='$L.6', image='img:1', namespace='ns')
j = CAPTURED[0] if CAPTURED else {}
c = container(j)
top = sorted(j.keys())
spec = sorted(j.get('spec', {}).keys())
pod  = sorted(j.get('spec', {}).get('template', {}).get('spec', {}).keys())
cont = sorted(c.keys())
# Amended 2026-08-31 (20260831t / #117): env → args. The assertion is the same one this
# task shipped with — no OTHER key of the rendered Job moved — re-pinned to the shape in
# which the intent actually reaches run-task.sh.
argv = c.get('args') or []
print('R:' + json.dumps([top, spec, pod, cont, argv], separators=(',',':')))
")"
expect='R:[["apiVersion","kind","metadata","spec"],["activeDeadlineSeconds","backoffLimit","template","ttlSecondsAfterFinished"],["containers","nodeSelector","restartPolicy"],["args","image","name"],["s","--repo","r","--strategy","build-converge"]]'
if [ "$out" = "$expect" ]; then
  ok "ac6: with nothing configured every other key of the rendered Job is unchanged"
else
  no "ac6: the rendered Job's shape moved. expected $expect got $out — this task adds one optional field and touches nothing else"
fi

gate_done
