#!/usr/bin/env bash
# T5 — dispatch can ask for another strategy, and lands it on an image that can run it.
#
# Behavioural through the module's own API. `launch` is monkeypatched so nothing shells out to
# kubectl; the Job dict it is handed IS the assertion surface.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829a-executor-image-layer/lib/fixtures.sh"

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

def image_of(job):
    try:
        return job['spec']['template']['spec']['containers'][0]['image']
    except Exception:
        return None

def strategy_of(job):
    try:
        for e in job['spec']['template']['spec']['containers'][0]['env']:
            if e.get('name') == 'STRATEGY':
                return e.get('value')
    except Exception:
        pass
    return None

$1
" 2>&1 ) | tail -1
}

L="$T/ledger"

# ── ac1: a fifth field becomes the strategy ──────────────────────────────────────────────────
out="$(probe "
i = d.parse_intent('@harness fix myrepo myspec judge-refine')
print('R:' + (i or {}).get('strategy', 'NONE') if i else 'R:PARSE-FAILED')
")"
case "$out" in
  R:judge-refine) ok "ac1: a fifth field is returned as the strategy" ;;
  R:build-converge) no "ac1: a five-field intent parsed but the strategy is still hardcoded to build-converge — the field was accepted and thrown away, which is worse than rejecting it because the requester is told nothing" ;;
  R:PARSE-FAILED) no "ac1: '@harness fix myrepo myspec judge-refine' does not parse. The grammar still requires exactly four parts, so no other strategy can be requested over the text path" ;;
  *) no "ac1: unexpected probe result [$out]" ;;
esac

# ── ac2: four fields still mean build-converge ───────────────────────────────────────────────
# Absence-of-change assertion. Its POSITIVE CONTROL is ac1: the same probe already read a
# DIFFERENT strategy off a five-field intent, so 'build-converge' here is a real reading.
out="$(probe "
i = d.parse_intent('@harness fix myrepo myspec')
print('R:' + ((i or {}).get('strategy', 'NONE') if i else 'PARSE-FAILED'))
")"
[ "$out" = "R:build-converge" ] \
  && ok "ac2: a four-field intent still yields build-converge" \
  || no "ac2: the unchanged four-field form no longer yields build-converge — got [$out]. Every caller that exists today sends four fields"

# ── ac3: more than five fields is still a parse failure ──────────────────────────────────────
out="$(probe "
i = d.parse_intent('@harness fix myrepo myspec judge-refine and please hurry')
print('R:' + ('NONE' if i is None else i.get('strategy','?')))
")"
[ "$out" = "R:NONE" ] \
  && ok "ac3: more than five fields is still a parse failure" \
  || no "ac3: a six-field intent parsed to [$out]. Widening by one optional field must not turn the parser into a permissive one — an unbounded tail means a typo silently becomes a strategy name"

# ── ac4: the image is resolved from the requested strategy ───────────────────────────────────
out="$(probe "
os.environ['HARNESS_WORKER_IMAGE'] = 'ghcr.io/x/default:1'
os.environ['HARNESS_WORKER_IMAGE_BUILD_CODEX'] = 'ghcr.io/x/codex:1'
d.launch_run('r','s','build-codex','e-ac4', ledger_path='$L.a', image='ghcr.io/x/default:1', namespace='ns')
print('R:' + str(image_of(CAPTURED[0]) if CAPTURED else 'NO-JOB'))
")"
case "$out" in
  R:ghcr.io/x/codex:1) ok "ac4: a per-strategy image variable selects the image" ;;
  R:ghcr.io/x/default:1) no "ac4: the strategy was requested but the default image was used anyway. build-codex on the opencode image is a run that cannot possibly succeed, and it fails as a shell error inside the pod rather than as a dispatch refusal" ;;
  *) no "ac4: no Job reached launch, or its image could not be read [$out]" ;;
esac

# ── ac5: no per-strategy variable falls back to the single default ───────────────────────────
out="$(probe "
os.environ['HARNESS_WORKER_IMAGE'] = 'ghcr.io/x/default:1'
os.environ.pop('HARNESS_WORKER_IMAGE_BUILD_CONVERGE', None)
d.launch_run('r','s','build-converge','e-ac5', ledger_path='$L.b', image='ghcr.io/x/default:1', namespace='ns')
print('R:' + str(image_of(CAPTURED[0]) if CAPTURED else 'NO-JOB'))
")"
[ "$out" = "R:ghcr.io/x/default:1" ] \
  && ok "ac5: with no per-strategy variable the single default is used" \
  || no "ac5: the fallback to HARNESS_WORKER_IMAGE is broken — got [$out]. Today's deployment sets only that one variable"

# ── ac6: the Job's strategy and its image come from the SAME request ─────────────────────────
# The failure this task exists to make impossible: a run launched with one strategy's name on
# the env and another strategy's image. Both halves read as correct in isolation.
out="$(probe "
os.environ['HARNESS_WORKER_IMAGE'] = 'ghcr.io/x/default:1'
os.environ['HARNESS_WORKER_IMAGE_JUDGE_REFINE'] = 'ghcr.io/x/judge:1'
d.launch_run('r','s','judge-refine','e-ac6', ledger_path='$L.c', image='ghcr.io/x/default:1', namespace='ns')
j = CAPTURED[0] if CAPTURED else {}
print('R:' + str(strategy_of(j)) + '|' + str(image_of(j)))
")"
case "$out" in
  "R:judge-refine|ghcr.io/x/judge:1") ok "ac6: the Job's STRATEGY and its image come from the same requested strategy" ;;
  "R:judge-refine|ghcr.io/x/default:1") no "ac6: the Job names judge-refine but runs the DEFAULT image — the two halves disagree, which is the exact split this assertion exists to catch" ;;
  "R:build-converge|"*) no "ac6: the requested strategy never reached the Job env [$out]" ;;
  *) no "ac6: could not read strategy and image together [$out]" ;;
esac

gate_done
