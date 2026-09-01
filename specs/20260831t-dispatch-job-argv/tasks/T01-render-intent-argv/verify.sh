#!/usr/bin/env bash
# T1 — the intent rides argv, and the argv actually parses (20260831t, issue #117).
#
# Behavioural through the module's own API with `launch` monkeypatched, asserted on the
# rendered DICT — same shape as 20260830a T01, which says why (a field rendered as None
# serialises to a line a text grep reads as present).
#
# The check that makes this gate different from a shape pin is ac3: the rendered argv is fed
# to the REAL scripts/run-task.sh. #117 existed precisely because each side read as correct
# alone — the renderer had an env for everything, the parser had a flag for everything — so
# this gate refuses to look at either side alone. HARNESS_DIR points at a path that does not
# exist, which run-task.sh refuses with exit 66 AFTER its parser: past-the-parser is provable
# with no network, no clone, no harness checkout. ac4 is the control that keeps ac3 honest —
# empty argv must still die at the parser (64), or "got past it" stops meaning anything.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

D="$ROOT/scripts/dispatch/dispatcher.py"
RT="$ROOT/scripts/run-task.sh"
EP="$ROOT/scripts/entrypoint.sh"
[ -f "$D" ]  || { no "ac0: scripts/dispatch/dispatcher.py is missing"; gate_done; }
[ -f "$RT" ] || { no "ac0: scripts/run-task.sh is missing"; gate_done; }

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

$1
" 2>&1 ) | tail -1
}

L="$T/ledger"

# ── ac1: the container carries the intent as run-task.sh's argv ──────────────────────────────
out="$(probe "
d.launch_run('myrepo','specs/thing','build-converge','e1', ledger_path='$L.1', image='img:1', namespace='ns')
c = container(CAPTURED[0]) if CAPTURED else {}
print('R:' + json.dumps(c.get('args'), separators=(',',':')))
")"
expect='R:["specs/thing","--repo","myrepo","--strategy","build-converge"]'
if [ "$out" = "$expect" ]; then
  ok "ac1: args is [<spec>, --repo, <repo>, --strategy, <strategy>] — the one documented calling convention"
else
  no "ac1: rendered args are not run-task.sh's convention — expected $expect got [$out]"
fi

# ── ac2: the dead env convention is gone, and ENTRYPOINT stays in charge ─────────────────────
# No REPO/SPEC/STRATEGY env (nothing in the worker ever read them, and a second convention
# is how #117 survived review) and no `command` key (a command displaces tini → entrypoint.sh,
# which writes the clone credential before the loop starts).
out="$(probe "
d.launch_run('myrepo','specs/thing','build-converge','e2', ledger_path='$L.2', image='img:1', namespace='ns')
c = container(CAPTURED[0]) if CAPTURED else {}
envn = sorted(e.get('name') for e in c.get('env', []) if e.get('name') in ('REPO','SPEC','STRATEGY'))
print('R:' + json.dumps(envn, separators=(',',':')) + '|' + ('CMD' if 'command' in c else 'NOCMD'))
")"
case "$out" in
  'R:[]|NOCMD') ok "ac2: no REPO/SPEC/STRATEGY env and no command — one convention, entrypoint in charge" ;;
  'R:[]|CMD')   no "ac2: the container sets command — that bypasses the entrypoint that writes the clone credential" ;;
  *)            no "ac2: the env convention is still rendered — [$out]. Nothing in the worker reads it; it is the reads-as-correct-from-either-side surface #117 hid behind" ;;
esac

# ── ac3: THE SEAM — the rendered argv gets past the real parser ──────────────────────────────
argv_tsv="$(probe "
d.launch_run('myrepo','specs/thing','build-converge','e3', ledger_path='$L.3', image='img:1', namespace='ns')
c = container(CAPTURED[0]) if CAPTURED else {}
print('\t'.join(c.get('args') or []))
")"
if [ -z "$argv_tsv" ]; then
  no "ac3: no argv rendered — nothing to hand the parser"
else
  old_ifs="$IFS"; IFS="$(printf '\t')"
  # shellcheck disable=SC2086
  set -- $argv_tsv
  IFS="$old_ifs"
  seam_err="$T/seam.err"
  HARNESS_DIR="$T/nowhere" HARNESS_WORKSPACE="$T/ws" bash "$RT" "$@" >"$T/seam.out" 2>"$seam_err"
  rc=$?
  if [ "$rc" -eq 66 ] && ! grep -q "is required\|unknown flag" "$seam_err"; then
    ok "ac3: the rendered argv passed run-task.sh's parser (refused later on HARNESS_DIR, exit 66)"
  elif [ "$rc" -eq 64 ]; then
    no "ac3: run-task.sh exited 64 — the rendered argv died AT the parser, which is exactly #117: $(tail -1 "$seam_err" 2>/dev/null)"
  else
    no "ac3: expected exit 66 (past the parser, no such HARNESS_DIR) — got $rc: $(tail -1 "$seam_err" 2>/dev/null)"
  fi
fi

# ── ac4: the control — empty argv still dies at the parser ───────────────────────────────────
HARNESS_DIR="$T/nowhere" bash "$RT" >/dev/null 2>"$T/ctl.err"
rc=$?
if [ "$rc" -eq 64 ] && grep -q "is required" "$T/ctl.err"; then
  ok "ac4: empty argv exits 64 — the parser really rejects what the old renderer produced"
else
  no "ac4: empty argv no longer exits 64 (got $rc) — a defaulting parser would mask a renderer regression and rot ac3 into a tautology"
fi

# ── ac5: the entrypoint still passes a Job's args through ────────────────────────────────────
if [ -f "$EP" ] && grep -Fq 'exec "$(dirname "$0")/run-task.sh" "$@"' "$EP"; then
  ok "ac5: entrypoint.sh execs run-task.sh \"\$@\" — the bridge argv rides is intact"
else
  no "ac5: entrypoint.sh no longer execs run-task.sh \"\$@\" — a Job's args have nowhere to land"
fi

gate_done
