#!/usr/bin/env bash
# specs/20260828g-dispatch-core/verify.sh — the gate for the transport seam.
#
# The property under test is STRUCTURAL: there must be exactly one copy of the
# dedupe-render-launch-record sequence, and every transport must reach it. A functional test
# alone cannot see the defect this spec exists to remove — two copies of the sequence behave
# identically until they drift. So the seam assertions read the AST and ask which functions each
# adapter calls, and the functional assertions prove the behaviour did not change while it moved.
#
# Negative assertions ("launched nothing") are each paired with a positive control, because a
# no-launch assertion passes just as well when the mock is broken.
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

_stray="$(find "$R/specs/20260828g-dispatch-core" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence 2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

[ -f "$MOD" ] || { echo "  FAIL  scope: dispatcher.py is missing — this spec refactors it" >&2; echo "---"; exit 1; }
python3 -c "import sys; f=sys.argv[1]; compile(open(f).read(), f, 'exec')" "$MOD" >/dev/null 2>&1 \
  && ok "scope: dispatcher.py compiles" \
  || { no "scope: dispatcher.py does not compile"; echo "---"; exit 1; }

export PYTHONDONTWRITEBYTECODE=1
export PYTHONPYCACHEPREFIX="$T/pyc"

# --- HAVE probe: which functions exist. Guards below key on the task that SATISFIES them. ------
HAVE="$(python3 - "$MOD" <<'PY' 2>/dev/null
import ast, sys
t = ast.parse(open(sys.argv[1]).read())
names = {n.name for n in t.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))}
print(" ".join(sorted(names)))
PY
)"
have(){ case " $HAVE " in *" $1 "*) return 0;; *) return 1;; esac; }

# --- The AST oracle. Emits, per function: its params and the bare names it calls. --------------
CALLS="$T/calls.json"
python3 - "$MOD" > "$CALLS" 2>/dev/null <<'PY'
import ast, json, sys
t = ast.parse(open(sys.argv[1]).read())
out = {}
for n in t.body:
    if not isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
        continue
    a = n.args
    params = [p.arg for p in (a.posonlyargs + a.args + a.kwonlyargs)]
    calls = set()
    for sub in ast.walk(n):
        if isinstance(sub, ast.Call):
            f = sub.func
            if isinstance(f, ast.Name):
                calls.add(f.id)
            elif isinstance(f, ast.Attribute):
                calls.add(f.attr)
    out[n.name] = {"params": params, "calls": sorted(calls)}
json.dump(out, sys.stdout)
PY
[ -s "$CALLS" ] || { no "scope: could not read the module's call graph"; echo "---"; exit 1; }

q(){ python3 - "$CALLS" "$@" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
fn, kind = sys.argv[2], sys.argv[3]
print(" ".join(d.get(fn, {}).get(kind, [])))
PY
}

# --- ac1: the core takes an intent, never a chat string ----------------------------------------
if ! have dispatch; then pend "ac1: a transport-agnostic dispatch core exists"; else
  p="$(q dispatch params)"
  miss=""
  case " $p " in *" intent "*) ;; *) miss="$miss no-intent-param";; esac
  for bad in text message msg body chat line; do
    case " $p " in *" $bad "*) miss="$miss takes-$bad";; esac
  done
  # the sequence must actually live here
  c="$(q dispatch calls)"
  for need in already_seen render_job launch record_seen; do
    case " $c " in *" $need "*) ;; *) miss="$miss missing-$need";; esac
  done
  [ -n "$miss" ] && no "ac1: dispatch is not the transport-agnostic core —$miss" \
                 || ok "ac1: dispatch takes an intent and holds the whole sequence"
fi

# --- ac2: the chat adapter decides nothing -----------------------------------------------------
if ! have dispatch; then pend "ac2: the chat path reaches the core instead of duplicating it"; else
  c="$(q handle_event calls)"
  miss=""
  case " $c " in *" dispatch "*) ;; *) miss="$miss does-not-call-dispatch";; esac
  case " $c " in *" parse_intent "*) ;; *) miss="$miss does-not-parse";; esac
  for bad in render_job launch already_seen record_seen record_run; do
    case " $c " in *" $bad "*) miss="$miss still-calls-$bad";; esac
  done
  [ -n "$miss" ] && no "ac2: handle_event is not a thin adapter —$miss" \
                 || ok "ac2: handle_event parses, then delegates — one copy of the sequence"
fi

# --- ac3: the value-taking adapter exists and does not route through chat grammar ---------------
if ! have launch_run; then pend "ac3: a caller with values can dispatch without chat text"; else
  p="$(q launch_run params)"; c="$(q launch_run calls)"
  miss=""
  for need in repo spec strategy; do
    case " $p " in *" $need "*) ;; *) miss="$miss no-$need-param";; esac
  done
  case " $c " in *" dispatch "*) ;; *) miss="$miss does-not-call-dispatch";; esac
  for bad in parse_intent render_job launch already_seen record_seen; do
    case " $c " in *" $bad "*) miss="$miss reimplements-$bad";; esac
  done
  [ -n "$miss" ] && no "ac3: launch_run is not a clean adapter —$miss" \
                 || ok "ac3: launch_run takes values and delegates to the core"
fi

# --- the mock cluster --------------------------------------------------------------------------
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
export PATH="$T/bin:$PATH" HARNESS_KUBECTL=kubectl

# runner: $1 = mock dir name, rest = python snippet on stdin. Prints the launch count.
count(){ cat "$T/$1/count" 2>/dev/null || echo 0; }

drive(){ # $1 = mock dir, stdin = snippet
  local d="$T/$1"; rm -rf "$d"; mkdir -p "$d"
  MOCK_DIR="$d" PYTHONPATH="$R/scripts/dispatch" python3 - "$d" >"$d/out" 2>"$d/err"
  return $?
}

# --- ac4: behaviour did not change while it moved ----------------------------------------------
if ! have dispatch; then pend "ac4: the chat path still launches once, and only when it should"; else
  drive m_pos <<'PY'
import sys, dispatcher as D
d = sys.argv[1]
print(D.handle_event("@harness fix myrepo myspec", "evt-1",
      ledger_path=d+"/ledger", image="img:1", namespace="harness-fleet"))
PY
  drive m_replay <<'PY'
import sys, dispatcher as D
d = sys.argv[1]
for _ in range(2):
    D.handle_event("@harness fix myrepo myspec", "evt-1",
      ledger_path=d+"/ledger", image="img:1", namespace="harness-fleet")
PY
  drive m_junk <<'PY'
import sys, dispatcher as D
d = sys.argv[1]
for msg in ["@harness deploy myrepo myspec", "hey everyone", "", "@harness fix onlyrepo"]:
    D.handle_event(msg, "evt-junk", ledger_path=d+"/ledger",
      image="img:1", namespace="harness-fleet")
PY
  cp="$(count m_pos)"; cr="$(count m_replay)"; cj="$(count m_junk)"
  # the positive control is what makes the two zeros meaningful
  if [ "$cp" != 1 ]; then
    no "ac4: control failed — a valid message launched $cp times, expected 1 (zeros below prove nothing)"
  elif [ "$cr" != 1 ]; then
    no "ac4: a replayed event id launched $cr times, expected 1"
  elif [ "$cj" != 0 ]; then
    no "ac4: unparseable messages launched $cj times, expected 0"
  else
    ok "ac4: chat launches once, replays once, junk never — control held"
  fi
fi

# --- ac5: every launched run is recorded, and only launched runs ------------------------------
if ! have record_run || ! have read_runs; then pend "ac5: launched runs land in the registry"; else
  drive m_reg <<'PY'
import sys, json, dispatcher as D
d = sys.argv[1]
kw = dict(ledger_path=d+"/ledger", image="img:1", namespace="harness-fleet",
          registry_path=d+"/registry.jsonl")
D.handle_event("@harness fix myrepo myspec", "evt-A", **kw)
D.handle_event("@harness fix myrepo myspec", "evt-A", **kw)   # replay: no second record
D.handle_event("nonsense", "evt-B", **kw)                     # no intent: no record
print(json.dumps(D.read_runs(d+"/registry.jsonl")))
PY
  rows="$(cat "$T/m_reg/out" 2>/dev/null)"
  v="$(python3 - <<PY 2>/dev/null
import json
try: rows = json.loads(r'''$rows''')
except Exception: print("unreadable"); raise SystemExit
if len(rows) != 1: print("rowcount=%d" % len(rows)); raise SystemExit
r = rows[0]
need = {"repo": "myrepo", "spec": "myspec", "strategy": "build-converge"}
miss = []
vals = {str(x) for x in r.values()}
for k, want in need.items():
    if want not in vals: miss.append("no-"+k)
if "evt-A" not in vals: miss.append("no-event-id")
if not any(isinstance(x, str) and x.startswith("run-") for x in r.values()): miss.append("no-job-name")
if not any(isinstance(x, str) and x in ("launched", "failed") for x in r.values()): miss.append("no-status")
if len(r) != 6: miss.append("fields=%d" % len(r))
print(" ".join(miss) if miss else "ok")
PY
)"
  [ "$v" = ok ] && ok "ac5: one record per launched run, six fields, no record for replays or junk" \
                || no "ac5: registry record is wrong — ${v:-no output}"
fi

# --- ac6: the ledger stays the dedupe mechanism, uncontaminated by the registry ----------------
if ! have record_run; then pend "ac6: ledger and registry are separate stores"; else
  miss=""
  for f in already_seen record_seen; do
    c="$(q $f calls)"
    for bad in record_run read_runs get_run; do
      case " $c " in *" $bad "*) miss="$miss $f-touches-$bad";; esac
    done
  done
  # the ledger on disk must still be bare ids, not JSON records
  if [ -f "$T/m_reg/ledger" ]; then
    grep -q '{' "$T/m_reg/ledger" && miss="$miss ledger-holds-json"
    grep -qx 'evt-A' "$T/m_reg/ledger" || miss="$miss ledger-missing-bare-id"
  else
    miss="$miss no-ledger-written"
  fi
  [ -n "$miss" ] && no "ac6: the two stores are entangled —$miss" \
                 || ok "ac6: ledger holds bare ids; registry is a separate store"
fi

# --- ac7: the second transport reaches the same launch ----------------------------------------
if ! have launch_run; then pend "ac7: launch_run produces the same Job the chat path does"; else
  drive m_api <<'PY'
import sys, dispatcher as D
d = sys.argv[1]
D.launch_run("myrepo", "myspec", "build-converge", "evt-api",
    ledger_path=d+"/ledger", image="img:1", namespace="harness-fleet")
PY
  ca="$(count m_api)"
  if [ "$ca" != 1 ]; then
    no "ac7: launch_run launched $ca times, expected 1"
  else
    j="$T/m_api/stdin.1"
    miss=""
    for k in '"myrepo"' '"myspec"' '"build-converge"' '"harness-fleet"' '"Never"' '"batch/v1"'; do
      grep -q -- "$k" "$j" || miss="$miss missing:$k"
    done
    grep -q '"backoffLimit": *0' "$j" || miss="$miss missing:backoffLimit"
    [ -n "$miss" ] && no "ac7: the Job launch_run produced is not the bounded Job —$miss" \
                   || ok "ac7: launch_run yields the same bounded Job as chat"
  fi
fi

# --- ac8: thinness survived the refactor -------------------------------------------------------
_thin="$(grep -nE '^[[:space:]]*(import|from)[[:space:]]+(openai|anthropic|litellm|requests|httpx|urllib|http)\b' "$MOD" | head -3)"
_gate="$(grep -nE 'verify\.sh|ralph-build|run-loop' "$MOD" | head -3)"
_retry="$(grep -nE '\b(for|while)\b[^\n]*\b(attempt|retry|retries|backoff)\b' "$MOD" | head -3)"
if [ -n "$_thin" ] || [ -n "$_gate" ] || [ -n "$_retry" ]; then
  no "ac8: the dispatcher gained judgment — ${_thin}${_gate}${_retry}"
else
  ok "ac8: no model client, no gate invocation, no retry loop"
fi

# --- ac9: the seam is written down -------------------------------------------------------------
# NOTE: README.md already exists from the previous spec, so its PRESENCE cannot gate this —
# the guard would never open and a T5 assertion would fail every task before T5. The signal is
# the content, and a missing update is a `pend`: lenient while earlier tasks run, promoted to a
# failure by STRICT on the final task, which is exactly where "T5 never happened" must bite.
if [ ! -r "$DOC" ]; then pend "ac9: the seam is documented"; else
  miss=""
  grep -qiE 'adapter' "$DOC" || miss="$miss adapters"
  grep -qiE 'registry' "$DOC" || miss="$miss registry"
  grep -qiE 'ledger' "$DOC" || miss="$miss ledger"
  grep -qiE 'launch_run' "$DOC" || miss="$miss launch_run"
  grep -qiE 'evidence' "$DOC" || miss="$miss evidence-caveat"
  [ -n "$miss" ] && pend "ac9: README does not yet describe the seam —$miss" \
                 || ok "ac9: README describes adapters, both stores, and the evidence caveat"
fi

echo "---"
[ "$fail" = 0 ] && { echo "VERIFY: PASS"; exit 0; } || { echo "VERIFY: FAIL"; exit 1; }
