#!/usr/bin/env bash
# specs/20260828h-dispatch-api/verify.sh — the gate for the HTTP surface.
#
# Two kinds of assertion, and both are needed.
#   STRUCTURAL: a handler must be an adapter. It may parse a request and format a response; it may
#   not dedupe, render or launch. Only the AST can see that — a handler that reimplements the
#   sequence behaves correctly right up until it drifts.
#   FUNCTIONAL: the server is actually started, on a real port, against a MOCK kubectl, and driven
#   with real requests. Idempotency and fail-closed auth are properties of a running server; a
#   unit test of a handler function would not have exercised either.
#
# Every "nothing was launched" assertion is paired with a positive control in the same run.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

API="$R/scripts/dispatch/api.py"
DISP="$R/scripts/dispatch"
DOC="$R/docs/dispatch-api.md"
README="$R/scripts/dispatch/README.md"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$T/x"; chmod +x "$T/x" 2>/dev/null
"$T/x" 2>/dev/null || { echo "  FAIL  ENV: TMPDIR is noexec" >&2; echo "VERIFY: ENV" >&2; exit 2; }

_stray="$(find "$R/specs/20260828h-dispatch-api" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence 2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

export PYTHONDONTWRITEBYTECODE=1

# The core this surface sits on must be present, or nothing below means anything.
python3 - "$DISP/dispatcher.py" <<'PY' >/dev/null 2>&1
import ast, sys
t = ast.parse(open(sys.argv[1]).read())
names = {n.name for n in t.body if isinstance(n, ast.FunctionDef)}
assert {"dispatch", "launch_run", "read_runs", "get_run"} <= names
PY
[ $? = 0 ] || { no "scope: the dispatch core is missing launch_run/read_runs/get_run — this spec builds on it"; echo "---"; exit 1; }
ok "scope: the dispatch core exposes the seam this surface calls"

if [ ! -f "$API" ]; then
  for a in "ac1: the server refuses to run without a token" \
           "ac2: an unauthenticated request reaches nothing" \
           "ac3: a request with values starts exactly one run" \
           "ac4: the same idempotency key starts one run" \
           "ac5: runs can be listed and read" \
           "ac6: a run can be cancelled" \
           "ac7: the evidence gap is declared, not faked" \
           "ac8: handlers are adapters, not a second core"; do pend "$a"; done
  [ -r "$DOC" ] || pend "ac9: the API is documented for its MCP client"
  echo "---"; [ "$fail" = 0 ] && exit 0 || exit 1
fi

python3 -c "import sys; f=sys.argv[1]; compile(open(f).read(), f, 'exec')" "$API" >/dev/null 2>&1 \
  && ok "scope: api.py compiles" \
  || { no "scope: api.py does not compile"; echo "---"; exit 1; }

# --- mock kubectl: records argv so apply and delete are both observable --------------------------
mkdir -p "$T/bin"
cat > "$T/bin/kubectl" <<'MOCK'
#!/usr/bin/env bash
d="${MOCK_DIR:?}"; mkdir -p "$d"
printf '%s\n' "$*" >> "$d/argv"
[ "${1:-}" = apply ] && cat >/dev/null
exit 0
MOCK
chmod +x "$T/bin/kubectl"
export PATH="$T/bin:$PATH" HARNESS_KUBECTL=kubectl

# --- ac1: fail closed at startup ----------------------------------------------------------------
# BOUNDED: an implementation that does NOT refuse to start will bind and serve_forever,
# and an unbounded call here would hang the whole gate rather than fail it. A hanging gate
# is worse than a failing one — the loop's watchdog kills the attempt and blames the executor.
MOCK_DIR="$T/m_noenv" HARNESS_API_TOKEN= \
  timeout 10 python3 -c "import sys; sys.path.insert(0,'$DISP'); import api; api.serve(0)" >"$T/noenv.out" 2>&1
rc=$?
if [ "$rc" = 124 ]; then
  no "ac1: serve() kept running with no HARNESS_API_TOKEN — it must refuse to start, not serve"
elif [ "$rc" = 0 ]; then
  no "ac1: serve() returned success with no HARNESS_API_TOKEN — it must refuse to start"
elif ! grep -qi 'HARNESS_API_TOKEN' "$T/noenv.out"; then
  no "ac1: it refused to start but never named HARNESS_API_TOKEN — $(head -c 120 "$T/noenv.out")"
else
  ok "ac1: no token, no server — and it says which variable is missing"
fi

# --- ac8: the handlers are adapters --------------------------------------------------------------
AC="$(python3 - "$API" <<'PY' 2>/dev/null
import ast, sys
t = ast.parse(open(sys.argv[1]).read())
calls = set()
for n in ast.walk(t):
    if isinstance(n, ast.Call):
        f = n.func
        if isinstance(f, ast.Name): calls.add(f.id)
        elif isinstance(f, ast.Attribute): calls.add(f.attr)
print(" ".join(sorted(calls)))
PY
)"
miss=""
# only demand a call once the task that adds it has had its chance; the forbidden list below
# is always checked, because reimplementing the core is wrong at every point in the run.
_want=""
hasfn(){ case " $AC " in *" $1 "*) return 0;; *) return 1;; esac; }
grep -q 'do_POST'   "$API" && _want="$_want launch_run"
grep -q 'do_GET'    "$API" && _want="$_want read_runs get_run"
for need in $_want; do
  hasfn "$need" || miss="$miss never-calls-$need"
done
for bad in render_job already_seen record_seen record_run parse_intent handle_event dispatch; do
  case " $AC " in *" $bad "*) miss="$miss reimplements-$bad";; esac
done
_fw="$(grep -nE '^[[:space:]]*(import|from)[[:space:]]+(flask|fastapi|django|aiohttp|starlette|tornado|bottle|uvicorn)\b' "$API" | head -2)"
[ -n "$_fw" ] && miss="$miss third-party-framework"
if [ -n "$miss" ]; then
  case "$miss" in
    *reimplements*|*third-party*) no "ac8: api.py is not a thin adapter layer —$miss" ;;
    *) pend "ac8: handlers do not yet reach the core —$miss" ;;
  esac
else
  ok "ac8: handlers call the core's seam and nothing beneath it; stdlib only"
fi

# --- the live driver: one server, the whole request sequence -------------------------------------
cat > "$T/drive.py" <<'PY'
import json, os, socket, subprocess, sys, time, urllib.error, urllib.request

disp, mock, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
TOKEN = "s3cret-test-token"

s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()

env = dict(os.environ)
env.update({
    "HARNESS_API_TOKEN": TOKEN,
    "HARNESS_LEDGER_PATH": tmp + "/ledger",
    "HARNESS_REGISTRY_PATH": tmp + "/registry.jsonl",
    "HARNESS_WORKER_IMAGE": "img:test",
    "HARNESS_NAMESPACE": "harness-fleet",
    "HARNESS_KUBECTL": "kubectl",
    "MOCK_DIR": mock,
    "PYTHONDONTWRITEBYTECODE": "1",
})
proc = subprocess.Popen(
    [sys.executable, "-c",
     "import sys; sys.path.insert(0, %r); import api; api.serve(%d)" % (disp, port)],
    env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)

def up():
    for _ in range(100):
        if proc.poll() is not None:
            return False
        try:
            socket.create_connection(("127.0.0.1", port), 0.2).close()
            return True
        except OSError:
            time.sleep(0.1)
    return False

res = {}
def calls():
    try:
        return open(mock + "/argv").read().splitlines()
    except OSError:
        return []

def req(method, path, body=None, token=TOKEN):
    url = "http://127.0.0.1:%d%s" % (port, path)
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(url, data=data, method=method)
    if token:
        r.add_header("Authorization", "Bearer " + token)
    r.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(r, timeout=10) as f:
            return f.status, f.read().decode()
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()
    except Exception as e:
        return -1, str(e)

try:
    if not up():
        print(json.dumps({"error": "server did not start",
                          "out": (proc.stdout.read().decode()[-400:] if proc.stdout else "")}))
        raise SystemExit

    KEY = "idem-key-1"
    RUN = {"repo": "myrepo", "spec": "myspec", "strategy": "build-converge",
           "idempotency_key": KEY}

    res["noauth"]        = req("POST", "/runs", RUN, token=None)[0]
    res["after_noauth"]  = len([c for c in calls() if c.startswith("apply")])
    res["create"]        = req("POST", "/runs", RUN)[0]
    res["after_create"]  = len([c for c in calls() if c.startswith("apply")])
    res["replay"]        = req("POST", "/runs", RUN)[0]
    res["after_replay"]  = len([c for c in calls() if c.startswith("apply")])
    res["badreq"]        = req("POST", "/runs", {"repo": "myrepo"})[0]
    res["after_badreq"]  = len([c for c in calls() if c.startswith("apply")])

    st, body = req("GET", "/runs")
    res["list"] = st
    try:
        d = json.loads(body)
        rows = d if isinstance(d, list) else next(
            (v for v in d.values() if isinstance(v, list)), None)
        res["list_bare_array"] = isinstance(d, list)
        res["list_rows"] = len(rows) if rows is not None else -1
        res["list_has_repo"] = bool(rows) and "myrepo" in json.dumps(rows)
    except Exception:
        res["list_rows"] = -1

    res["get_one"]     = req("GET", "/runs/" + KEY)[0]
    res["get_missing"] = req("GET", "/runs/no-such-run")[0]
    res["evidence"]    = req("GET", "/runs/" + KEY + "/evidence")[0]

    before_del = len([c for c in calls() if c.startswith("delete")])
    res["del_missing"] = req("DELETE", "/runs/no-such-run")[0]
    res["del_missing_ran"] = len([c for c in calls() if c.startswith("delete")]) - before_del
    res["cancel"] = req("DELETE", "/runs/" + KEY)[0]
    dels = [c for c in calls() if c.startswith("delete")]
    res["cancel_ran"] = len(dels) - before_del - res["del_missing_ran"]
    res["cancel_argv"] = dels[-1] if dels else ""
finally:
    proc.kill()

print(json.dumps(res))
PY

rm -rf "$T/m_live"; mkdir -p "$T/m_live"
python3 "$T/drive.py" "$DISP" "$T/m_live" "$T" > "$T/live.json" 2>"$T/live.err"
LIVE="$(cat "$T/live.json" 2>/dev/null)"

g(){ python3 -c "
import json,sys
try: d=json.loads(sys.argv[1])
except Exception: print(''); raise SystemExit
print(d.get(sys.argv[2], ''))" "$LIVE" "$1" 2>/dev/null; }

if [ -z "$LIVE" ] || [ -n "$(g error)" ]; then
  for a in "ac2: an unauthenticated request reaches nothing" \
           "ac3: a request with values starts exactly one run" \
           "ac4: the same idempotency key starts one run" \
           "ac5: runs can be listed and read" \
           "ac6: a run can be cancelled" \
           "ac7: the evidence gap is declared, not faked"; do
    # Surface the server's OWN output, not just "it did not start". A NameError at import and
    # a port collision are the same sentence to the executor unless the traceback is in the
    # feedback it retries against — and a retry with no clue is three attempts spent guessing.
    no "$a — the server never served: $(g error). Server said: $(g out | tr '\n' ' ' | tail -c 400)$(head -c 200 "$T/live.err" 2>/dev/null)"
  done
else
  # ac3 first: it is the positive control that makes ac2's zero mean anything.
  if ! hasfn launch_run; then pend "ac3: a request with values starts exactly one run"
  elif [ "$(g after_create)" != 1 ] || [ "$(g create)" -lt 200 ] 2>/dev/null || [ "$(g create)" -ge 300 ] 2>/dev/null; then
    no "ac3: an authenticated create returned $(g create) and launched $(g after_create) — expected 2xx and 1"
  elif [ "$(g badreq)" != 400 ] || [ "$(g after_badreq)" != 1 ]; then
    no "ac3: a body missing 'spec' returned $(g badreq) and left the count at $(g after_badreq) — expected 400 and no launch"
  else
    ok "ac3: a valid create launches exactly one run; an incomplete one launches none"
  fi

  if [ "$(g create)" = 401 ]; then
    no "ac2: control failed — an AUTHENTICATED request also got 401, so the 401 below proves nothing"
  elif [ "$(g noauth)" != 401 ]; then
    no "ac2: an unauthenticated request returned $(g noauth), expected 401"
  elif [ "$(g after_noauth)" != 0 ]; then
    no "ac2: an unauthenticated request launched $(g after_noauth) run(s)"
  else
    ok "ac2: no bearer token, no launch — 401 before any dispatcher call"
  fi

  if ! hasfn launch_run; then pend "ac4: the same idempotency key starts one run"
  elif [ "$(g after_replay)" != 1 ]; then
    no "ac4: the same idempotency key launched $(g after_replay) times, expected 1"
  else
    ok "ac4: replaying an idempotency key starts no second run"
  fi

  if ! hasfn read_runs || ! hasfn get_run; then pend "ac5: runs can be listed and read"
  elif [ "$(g list)" != 200 ] || [ "$(g list_rows)" -lt 1 ] 2>/dev/null; then
    no "ac5: GET /runs returned $(g list) with $(g list_rows) row(s)"
  elif [ "$(g list_bare_array)" = True ]; then
    no "ac5: GET /runs returns a bare top-level array — it must be under a named key"
  elif [ "$(g list_has_repo)" != True ]; then
    no "ac5: the listed run does not carry its repo"
  elif [ "$(g get_one)" != 200 ] || [ "$(g get_missing)" != 404 ]; then
    no "ac5: GET /runs/<id> returned $(g get_one) and an unknown id returned $(g get_missing) — expected 200 and 404"
  else
    ok "ac5: runs list under a named key; a known id reads, an unknown one 404s"
  fi

  if ! grep -q 'do_DELETE' "$API"; then pend "ac6: a run can be cancelled"
  elif [ "$(g cancel)" -lt 200 ] 2>/dev/null || [ "$(g cancel)" -ge 300 ] 2>/dev/null; then
    no "ac6: cancelling a known run returned $(g cancel)"
  elif [ "$(g cancel_ran)" != 1 ]; then
    no "ac6: cancelling ran the command $(g cancel_ran) times, expected 1"
  elif ! printf '%s' "$(g cancel_argv)" | grep -q 'harness-fleet'; then
    no "ac6: the delete did not name the namespace — $(g cancel_argv)"
  elif [ "$(g del_missing)" != 404 ] || [ "$(g del_missing_ran)" != 0 ]; then
    no "ac6: cancelling an unknown run returned $(g del_missing) and ran $(g del_missing_ran) command(s) — expected 404 and none"
  else
    ok "ac6: a known run is deleted in its namespace; an unknown one 404s and runs nothing"
  fi

  # Guard on the ROUTE existing, never on the 501 itself: a guard that keys on the answer
  # it is asserting cannot fail. Keying it on '501' meant an implementation returning 404
  # made the guard read 'not built yet' and skip — the assertion was unfalsifiable.
  if ! grep -q 'evidence' "$API"; then pend "ac7: the evidence gap is declared, not faked"
  elif [ "$(g evidence)" != 501 ]; then
    no "ac7: the evidence route returned $(g evidence), expected 501 — a 404 would claim the run does not exist"
  else
    ok "ac7: evidence returns 501, naming a capability that does not exist yet"
  fi
fi


# --- ac9: the contract is written for its client -------------------------------------------------
if [ ! -r "$DOC" ]; then pend "ac9: the API is documented for its MCP client"; else
  miss=""
  for route in '/runs' 'evidence'; do grep -q -- "$route" "$DOC" || miss="$miss route:$route"; done
  for verb in POST GET DELETE; do grep -q "$verb" "$DOC" || miss="$miss verb:$verb"; done
  grep -qi 'idempot' "$DOC" || miss="$miss idempotency"
  grep -qi 'bearer\|HARNESS_API_TOKEN' "$DOC" || miss="$miss auth"
  grep -q '501' "$DOC" || miss="$miss 501"
  grep -q '401' "$DOC" || miss="$miss 401"
  [ -r "$README" ] && { grep -qi 'dispatch-api' "$README" || miss="$miss readme-pointer"; }
  [ -n "$miss" ] && no "ac9: the API doc is not sufficient to write a client against —$miss" \
                 || ok "ac9: every route, both failure codes, auth and idempotency are documented"
fi

echo "---"
[ "$fail" = 0 ] && { echo "VERIFY: PASS"; exit 0; } || { echo "VERIFY: FAIL"; exit 1; }
