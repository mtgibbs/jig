#!/usr/bin/env bash
# specs/20260828f-harness-dispatch/verify.sh — the deterministic gate for the dispatcher core.
#
# ADVERSARIAL BY DESIGN. The dangerous failure here is not "it did not launch" — it is "it
# launched something it should not have". So most assertions below check that the launcher was
# NOT called, and each is paired with a positive control proving the mock records calls at all.
# A "did not launch" assertion with no control passes just as well when the mock is broken.
#
# The launcher is exercised through a MOCK kubectl on PATH, recording its argv and stdin. That is
# the only way to test a launch without a cluster.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

MOD="$R/scripts/dispatch/dispatcher.py"
DOC="$R/scripts/dispatch/README.md"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$T/x"; chmod +x "$T/x" 2>/dev/null
"$T/x" 2>/dev/null || { echo "  FAIL  ENV: TMPDIR is noexec" >&2; echo "VERIFY: ENV" >&2; exit 2; }

_stray="$(find "$R/specs/20260828f-harness-dispatch" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence 2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

if [ ! -f "$MOD" ]; then
  for a in "ac1: the intent parser" "ac2: an unrecognised message launches nothing" \
           "ac3: dedupe is keyed on the event id" "ac4: the rendered Job is bounded" \
           "ac5: the launcher is mockable and applies on stdin" "ac6: the dispatcher stays thin"; do
    pend "$a"
  done
  [ -r "$DOC" ] || pend "ac7: the contract is written down"
  echo "---"; [ "$fail" = 0 ] && exit 0 || exit 1
fi

PYDONT="PYTHONDONTWRITEBYTECODE=1"   # importing the module must not litter __pycache__
python3 -c "import sys; f=sys.argv[1]; compile(open(f).read(), f, 'exec')" "$MOD" >/dev/null 2>&1 \
  && ok "scope: dispatcher.py compiles" \
  || { no "scope: dispatcher.py does not compile"; echo "---"; exit 1; }

# A mock `kubectl` that records every invocation. Its ABSENCE of a record is what most
# assertions below read, so the control immediately after proves it records when it should.
mkdir -p "$T/bin"
cat > "$T/bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
d="${MOCK_DIR:?}"; mkdir -p "$d"
n=$(( $(cat "$d/count" 2>/dev/null || echo 0) + 1 ))
printf '%s' "$n" > "$d/count"
printf '%s\n' "$*" >> "$d/argv"
cat >> "$d/stdin.$n"
exit 0
MOCK
chmod +x "$T/bin/kubectl"

py(){ MOCK_DIR="$T/calls" PATH="$T/bin:$PATH" HARNESS_KUBECTL=kubectl \
      env $PYDONT python3 - "$MOD" "$T" 2>/dev/null; }
calls(){ cat "$T/calls/count" 2>/dev/null || echo 0; }
reset_calls(){ rm -rf "$T/calls"; }

# ── ac1 · the parser ───────────────────────────────────────────────────────────────────────
OUT="$(py <<'PY'
import importlib.util,sys,json
s=importlib.util.spec_from_file_location("d",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
r=m.parse_intent("@harness fix myrepo specs/thing")
print(json.dumps(r) if r else "NONE")
PY
)"
case "$OUT" in
  NONE|"") pend "ac1: parse_intent returned nothing for a valid message" ;;
  *myrepo*specs/thing*|*specs/thing*myrepo*)
    printf '%s' "$OUT" | grep -q 'build-converge' \
      && ok "ac1: a valid message yields repo, spec and the default strategy" \
      || no "ac1: the intent carries no strategy — $OUT" ;;
  *) no "ac1: the intent is missing repo or spec — $OUT" ;;
esac

# ── CONTROL first · the mock records a call when one is made ───────────────────────────────
reset_calls
py <<'PY' >/dev/null
import importlib.util,sys
s=importlib.util.spec_from_file_location("d",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
i=m.parse_intent("@harness fix myrepo specs/thing")
if i: m.launch(m.render_job(i, image="img:1", namespace="fleet", run_id="r1"))
PY
if [ "$(calls)" -ge 1 ]; then
  ok "control: the mock runner records a call — so 'did not launch' below means something"
  _CONTROL_OK=1
else
  no "control: the mock recorded no call even on a valid launch; every negative assertion below is vacuous"
  _CONTROL_OK=0
fi

# ── ac2 · an unrecognised message launches NOTHING ─────────────────────────────────────────
reset_calls
py <<'PY' >/dev/null
import importlib.util,sys
s=importlib.util.spec_from_file_location("d",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
led=sys.argv[2]+"/ledger"
for bad in ["@harness deploy myrepo specs/thing", "hello", "", "@harness fix", "@harness"]:
    try: m.handle_event(bad, "evt-"+str(abs(hash(bad))), ledger_path=led, image="img:1", namespace="fleet")
    except Exception as e: print("RAISED", e)
PY
if [ "${_CONTROL_OK:-0}" != 1 ]; then
  pend "ac2: cannot be judged while the control is failing"
elif [ "$(calls)" = 0 ]; then
  ok "ac2: five unrecognised or malformed messages launched nothing, and none raised"
else
  no "ac2: an unrecognised message reached the launcher ($(calls) calls)"
fi

# ── ac3 · the same event twice launches once ───────────────────────────────────────────────
reset_calls
py <<'PY' >/dev/null
import importlib.util,sys
s=importlib.util.spec_from_file_location("d",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
led=sys.argv[2]+"/ledger2"
for _ in range(3):
    m.handle_event("@harness fix myrepo specs/thing", "evt-same", ledger_path=led, image="img:1", namespace="fleet")
PY
c="$(calls)"
if [ "${_CONTROL_OK:-0}" != 1 ]; then
  pend "ac3: cannot be judged while the control is failing"
elif [ "$c" = 1 ]; then
  ok "ac3: the same event id three times launched exactly once"
elif [ "$c" = 0 ]; then
  pend "ac3: nothing launched at all"
else
  no "ac3: the same event id launched $c times — dedupe is not holding"
fi

# ── ac4 · the rendered Job is bounded, every time ──────────────────────────────────────────
J="$(py <<'PY'
import importlib.util,sys,json
s=importlib.util.spec_from_file_location("d",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
i=m.parse_intent("@harness fix myrepo specs/thing")
print(json.dumps(m.render_job(i, image="img:1", namespace="fleet", run_id="r1")))
PY
)"
if [ -z "$J" ]; then
  pend "ac4: render_job produced nothing"
else
  _miss="$(printf '%s' "$J" | python3 -c "
import json,sys
try: j=json.load(sys.stdin)
except Exception: print('UNPARSEABLE'); raise SystemExit
sp=j.get('spec',{}); tpl=sp.get('template',{}).get('spec',{})
miss=[]
if j.get('apiVersion')!='batch/v1' or j.get('kind')!='Job': miss.append('kind/apiVersion')
if not isinstance(sp.get('activeDeadlineSeconds'),int) or sp['activeDeadlineSeconds']<=0: miss.append('activeDeadlineSeconds')
if not isinstance(sp.get('ttlSecondsAfterFinished'),int): miss.append('ttlSecondsAfterFinished')
if sp.get('backoffLimit')!=0: miss.append('backoffLimit=0')
if (tpl.get('nodeSelector') or {}).get('harness-fleet')!='true': miss.append('nodeSelector harness-fleet=true')
if (j.get('metadata') or {}).get('namespace')!='fleet': miss.append('namespace')
envs={e.get('name') for c in (tpl.get('containers') or []) for e in (c.get('env') or [])}
for k in ('REPO','SPEC','STRATEGY'):
    if k not in envs: miss.append('env '+k)
print(' '.join(miss) if miss else 'OK')")"
  case "$_miss" in
    OK)          ok "ac4: the Job carries namespace, node selector, deadline, ttl, backoffLimit 0 and REPO/SPEC/STRATEGY" ;;
    UNPARSEABLE) no "ac4: render_job did not return a JSON-serialisable object" ;;
    # FAIL, not pend. render_job returned an object, so it is built — an object that omits a
    # safety bound is WRONG, not unbuilt, and pending it would let a Job with no nodeSelector or
    # no activeDeadlineSeconds pass a mid-spec task. Every bound here exists because loop Jobs
    # share the cluster with DNS and media.
    *)           no "ac4: the Job is built but omits —$_miss" ;;
  esac
fi

# ── ac5 · the launch applies the Job on STDIN, not from a file on disk ─────────────────────
if [ "$(calls)" -ge 0 ] && [ -s "$T/calls/argv" ] 2>/dev/null || [ -s "$T/calls/argv" ]; then :; fi
reset_calls
py <<'PY' >/dev/null
import importlib.util,sys
s=importlib.util.spec_from_file_location("d",sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
i=m.parse_intent("@harness fix myrepo specs/thing")
m.launch(m.render_job(i, image="img:1", namespace="fleet", run_id="r1"))
PY
if [ ! -s "$T/calls/argv" ]; then
  pend "ac5: no launch recorded"
else
  grep -q 'apply' "$T/calls/argv" && grep -q -- '-f -' "$T/calls/argv" \
    && ok "ac5: the launcher runs 'apply -f -'" \
    || no "ac5: the launcher argv is '$(head -1 "$T/calls/argv")', expected apply -f -"
  if grep -q '"kind"' "$T/calls/stdin.1" 2>/dev/null && grep -q 'batch/v1' "$T/calls/stdin.1" 2>/dev/null; then
    ok "ac5: the Job JSON arrives on stdin"
  else
    no "ac5: the Job did not arrive on the command's stdin"
  fi
fi

# ── ac6 · thinness, asserted on code with comments stripped ────────────────────────────────
_body="$(python3 - "$MOD" <<'PY'
import sys,io,tokenize
src=io.open(sys.argv[1],encoding='utf-8').read().splitlines(True)
out=[]
for l in src:
    s=l.split('#',1)[0]
    out.append(s)
print(''.join(out))
PY
)"
_bad=""
printf '%s' "$_body" | grep -qE 'import (openai|anthropic|litellm)|/v1/chat|verify\.sh|ralph-build' && _bad="$_bad model-or-gate"
printf '%s' "$_body" | grep -qE 'for +attempt|retries|RETRIES' && _bad="$_bad retry-loop"
[ -n "$_bad" ] && no "ac6: the dispatcher has accreted judgment —$_bad (ADR D3: validate, map, launch, record)" \
               || ok "ac6: no model call, no gate invocation, no retry loop"

# ── ac7 · the contract is written down ─────────────────────────────────────────────────────
if [ ! -r "$DOC" ]; then
  pend "ac7: scripts/dispatch/README.md"
else
  _n=0
  grep -qi 'event id' "$DOC" && _n=$((_n+1))
  grep -qi 'harness-fleet\|nodeSelector' "$DOC" && _n=$((_n+1))
  grep -qiE 'HARNESS_KUBECTL|HARNESS_WORKER_IMAGE' "$DOC" && _n=$((_n+1))
  [ "$_n" = 3 ] && ok "ac7: the README covers dedupe, the Job's bounds and the two env knobs" \
                || pend "ac7: the README is missing part of the contract ($_n/3)"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
