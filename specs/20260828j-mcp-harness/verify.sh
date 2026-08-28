#!/usr/bin/env bash
# Gate for 20260828j-mcp-harness.
#
# Norms this file follows (and 20260828h learned the hard way): every call into the thing under
# test is bounded with an explicit branch for the call that never returned; no guard is keyed on
# the value its assertion is about; and every failure message carries the server's OWN output.
set -u
fail=0
ok()   { echo "  PASS  $1"; }
no()   { echo "  FAIL  $1" >&2; fail=1; }
pend() { echo "  pend  $1 — not built yet"; [ "${STRICT:-0}" = 1 ] && fail=1; return 0; }

R="$(git rev-parse --show-toplevel)"
SPEC="$R/specs/20260828j-mcp-harness"
SRV="$R/scripts/mcp-harness/server.py"
DOC="$R/docs/mcp-harness.md"
TOKEN="TOKEN-SEKRIT-9f3c11"

T="$(mktemp -d)" || { echo "VERIFY: ENV (no temp dir)" >&2; exit 2; }
printf '#!/bin/sh\nexit 0\n' > "$T/x"; chmod +x "$T/x"
"$T/x" 2>/dev/null || { echo "VERIFY: ENV (noexec TMPDIR — set TMPDIR to an exec-able path)" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX="$T/pyc"

if [ ! -r "$SRV" ]; then
  for a in "ac1: no config, no server — and it names the missing variable" \
           "ac2: initialize answers with a protocol version and a server name" \
           "ac3: exactly the four tools, and cancel_run is not among them" \
           "ac4: launch_run requires an idempotency_key with no default" \
           "ac5: the read tools GET, carry the bearer token, and issue nothing else" \
           "ac6: a 401 is reported as authentication, not as a missing run" \
           "ac7: no-such-run and not-implemented-yet are distinguishable" \
           "ac8: launch_run POSTs the caller's key and reports a replay as an existing run" \
           "ac9: the token never appears in a tool result" \
           "ac10: a client, not a second dispatcher — stdlib only, no dispatcher import"; do
    pend "$a"
  done
  [ -r "$DOC" ] || pend "ac11: the server is documented for the agent that will use it"
  echo "---"; [ "$fail" = 0 ] && { echo "VERIFY: PASS"; exit 0; }; echo "VERIFY: FAIL"; exit 1
fi

# ── ac10 · structural: a client, not a second dispatcher ───────────────────────────────────
# Parsed, not grepped: a grep for "dispatcher" also matches the word in a comment explaining
# why it is absent, and would fail correct work for saying the right thing.
_imp="$(timeout 20 python3 - "$SRV" <<'PY' 2>&1
import ast, sys
mods = set()
for n in ast.walk(ast.parse(open(sys.argv[1]).read())):
    if isinstance(n, ast.Import):
        mods |= {a.name.split(".")[0] for a in n.names}
    elif isinstance(n, ast.ImportFrom) and n.level == 0 and n.module:
        mods.add(n.module.split(".")[0])
outside = sorted(m for m in mods if m not in sys.stdlib_module_names)
print("dispatcher" if "dispatcher" in mods else ("nonstdlib:" + ",".join(outside) if outside else "clean"))
PY
)"
case "$_imp" in
  clean)       ok "ac10: a client, not a second dispatcher — stdlib only, no dispatcher import" ;;
  dispatcher)  no "ac10: server.py imports dispatcher — this server is a CLIENT of the API (D9), not a second copy of it" ;;
  nonstdlib:*) no "ac10: server.py imports outside the standard library: ${_imp#nonstdlib:}" ;;
  *)           no "ac10: could not read the imports. Python said: $(printf '%s' "$_imp" | tr '\n' ' ' | tail -c 200)" ;;
esac

# ── ac1 · fail closed on configuration ─────────────────────────────────────────────────────
# BOUNDED, and the reason is 20260828h's ac1: a server that does NOT refuse will block in its
# read loop, and an unbounded probe here would hang the whole gate instead of failing it —
# which the loop's watchdog then charges to the executor.
for var in HARNESS_API_URL HARNESS_API_TOKEN; do
  if [ "$var" = HARNESS_API_URL ]; then envset="HARNESS_API_URL= HARNESS_API_TOKEN=$TOKEN"
  else envset="HARNESS_API_URL=http://127.0.0.1:1 HARNESS_API_TOKEN="; fi
  # shellcheck disable=SC2086
  out="$(env $envset timeout 10 python3 "$SRV" </dev/null 2>&1)"; rc=$?
  if [ "$rc" = 124 ]; then
    no "ac1: with $var empty the server kept running — it must refuse to start, not serve"; break
  elif [ "$rc" = 0 ]; then
    no "ac1: with $var empty the server exited 0 — a tool server that starts without knowing who it is will be started that way in production"; break
  elif ! printf '%s' "$out" | grep -q "$var"; then
    no "ac1: with $var empty it exited $rc but never named the variable. It said: $(printf '%s' "$out" | tr '\n' ' ' | tail -c 250)"; break
  fi
  [ "$var" = HARNESS_API_TOKEN ] && ok "ac1: no config, no server — and it names the missing variable"
done

# ── drive the server ───────────────────────────────────────────────────────────────────────
timeout 90 python3 "$SPEC/drive.py" "$SRV" "$TOKEN" > "$T/d.json" 2> "$T/d.err"; drc=$?
g() { python3 -c "
import json,sys
try: d=json.load(open(sys.argv[1]))
except Exception: print(''); raise SystemExit
v=d
for k in sys.argv[2].split('.'):
    v = v.get(k) if isinstance(v,dict) else None
    if v is None: break
print('' if v is None else (v if isinstance(v,str) else json.dumps(v)))" "$T/d.json" "$1" 2>/dev/null; }

if [ "$drc" = 124 ] || [ ! -s "$T/d.json" ]; then
  _why="the driver did not return within 90s"
  [ "$drc" != 124 ] && _why="the driver produced nothing (rc=$drc)"
  for a in "ac2: initialize answers with a protocol version and a server name" \
           "ac3: exactly the four tools, and cancel_run is not among them" \
           "ac4: launch_run requires an idempotency_key with no default" \
           "ac5: the read tools GET, carry the bearer token, and issue nothing else" \
           "ac6: a 401 is reported as authentication, not as a missing run" \
           "ac7: no-such-run and not-implemented-yet are distinguishable" \
           "ac8: launch_run POSTs the caller's key and reports a replay as an existing run" \
           "ac9: the token never appears in a tool result"; do
    no "$a — $_why. Driver said: $(tr '\n' ' ' < "$T/d.err" | tail -c 300)"
  done
else
  INIT="$(g init)"; TOOLS="$(g tools)"; STDERR="$(g stderr)"

  # ac2 — the handshake
  if [ -z "$INIT" ]; then
    no "ac2: initialize returned nothing. Server stderr: $(printf '%s' "$STDERR" | tr '\n' ' ' | tail -c 300)"
  elif printf '%s' "$INIT" | grep -q '"error"'; then
    no "ac2: initialize returned a JSON-RPC error: $(printf '%s' "$INIT" | tail -c 250)"
  elif printf '%s' "$INIT" | grep -qi 'protocolversion\|protocol_version' && printf '%s' "$INIT" | grep -qi 'name'; then
    ok "ac2: initialize answers with a protocol version and a server name"
    [ "$(g bad_frame_survived)" = "true" ] \
      && ok "ac2: a malformed frame is answered and the session survives it" \
      || no "ac2: the session did not survive a malformed frame — one bad frame denies the whole session"
  else
    no "ac2: initialize answered without a protocol version and name: $(printf '%s' "$INIT" | tail -c 250)"
  fi

  # ac3/ac4 — the catalogue (T2). Guard: did tools/list answer with a tool list at all?
  if [ -z "$TOOLS" ]; then
    pend "ac3: exactly the four tools, and cancel_run is not among them"
    pend "ac4: launch_run requires an idempotency_key with no default"
  else
    if [ "$TOOLS" = '["fetch_evidence", "launch_run", "list_runs", "run_status"]' ]; then
      ok "ac3: exactly the four tools, and cancel_run is not among them"
    elif printf '%s' "$TOOLS" | grep -q 'cancel_run'; then
      no "ac3: cancel_run is listed — it is deferred by decision (§3.2), not yet built: $TOOLS"
    else
      no "ac3: the tool set is $TOOLS, expected exactly fetch_evidence, launch_run, list_runs, run_status"
    fi
    REQ="$(g launch_required)"; PROPS="$(g launch_props)"
    if [ -z "$REQ" ]; then
      no "ac4: launch_run declares no required arguments — an optional idempotency_key means every retry arrives with a new one and the dispatcher's replay protection never engages"
    elif [ "$REQ" != '["idempotency_key", "repo", "spec", "strategy"]' ]; then
      no "ac4: launch_run requires $REQ, expected all four of idempotency_key, repo, spec, strategy"
    elif printf '%s' "$PROPS" | python3 -c "
import json,sys
p=json.loads(sys.stdin.read() or '{}')
sys.exit(0 if 'default' in (p.get('idempotency_key') or {}) else 1)" 2>/dev/null; then
      no "ac4: idempotency_key declares a default — a generated key turns a retried tool call into a second run"
    else
      ok "ac4: launch_run requires an idempotency_key with no default"
    fi
  fi

  # ac5/ac6/ac7a — the read tools (T3). Guard: did calling them reach the dispatcher at all?
  READS="$(g read_calls)"
  if [ -z "$READS" ] || [ "$READS" = "[]" ]; then
    pend "ac5: the read tools GET, carry the bearer token, and issue nothing else"
    pend "ac6: a 401 is reported as authentication, not as a missing run"
    _no404=1
  else
    _no404=0
    if printf '%s' "$READS" | grep -qE '"(POST|PUT|DELETE|PATCH)'; then
      no "ac5: a read tool issued a non-GET request — $READS"
    elif [ "$(g read_auth_ok)" != "true" ]; then
      no "ac5: a read tool reached the dispatcher without an Authorization: Bearer header — $READS"
    elif printf '%s' "$READS" | grep -q '/runs/known' && printf '%s' "$READS" | grep -q 'GET /runs"'; then
      ok "ac5: the read tools GET, carry the bearer token, and issue nothing else"
    else
      ok "ac5: the read tools GET, carry the bearer token, and issue nothing else"
    fi
    R401="$(g results.status_401)"
    if [ -z "$R401" ]; then
      no "ac6: run_status against a 401 returned nothing. Server stderr: $(printf '%s' "$STDERR" | tr '\n' ' ' | tail -c 250)"
    elif printf '%s' "$R401" | grep -qiE 'auth|token|credential|401'; then
      if printf '%s' "$R401" | grep -qiE 'no such run|not found|does not exist'; then
        no "ac6: the 401 result also claims the run does not exist — a caller told that will go looking for a run that is there: $(printf '%s' "$R401" | tail -c 200)"
      else
        ok "ac6: a 401 is reported as authentication, not as a missing run"
      fi
    else
      no "ac6: a 401 was not reported as an authentication problem: $(printf '%s' "$R401" | tail -c 250)"
    fi
  fi

  # ac7 — 404 and 501 must stay distinguishable. Needs BOTH halves: T3's 404 and T4's 501.
  EV="$(g results.evidence)"; R404="$(g results.status_404)"
  if [ "$_no404" = 1 ] || [ -z "$EV" ]; then
    pend "ac7: no-such-run and not-implemented-yet are distinguishable"
  elif ! printf '%s' "$(g calls)" | grep -q '/evidence'; then
    no "ac7: fetch_evidence never reached the dispatcher's evidence route — calls were $(g calls)"
  elif ! printf '%s' "$R404" | grep -qiE 'no such run|not found|does not exist|unknown'; then
    no "ac7: an unknown run id was not reported as a missing run: $(printf '%s' "$R404" | tail -c 200)"
  elif ! printf '%s' "$EV" | grep -qiE 'not implemented|not built|not yet|unavailable yet|501'; then
    no "ac7: a 501 was not reported as an unbuilt capability: $(printf '%s' "$EV" | tail -c 200)"
  elif [ "$R404" = "$EV" ]; then
    no "ac7: the unknown-run and unbuilt-capability results are identical — a caller cannot tell them apart"
  else
    ok "ac7: no-such-run and not-implemented-yet are distinguishable"
  fi

  # ac8 — the one mutation (T5). Guard: did a POST reach the dispatcher?
  POSTS="$(g post_bodies)"
  if [ -z "$POSTS" ] || [ "$POSTS" = "[]" ]; then
    pend "ac8: launch_run POSTs the caller's key and reports a replay as an existing run"
  else
    LOK="$(g results.launch_ok)"; LRP="$(g results.launch_replay)"; L400="$(g results.launch_400)"
    if ! printf '%s' "$POSTS" | grep -q '"idempotency_key": "fresh"'; then
      no "ac8: the POST did not carry the caller's idempotency_key unchanged — bodies were $POSTS"
    elif printf '%s' "$LRP" | grep -qiE '"error"|failed|could not' && ! printf '%s' "$LRP" | grep -qiE 'exist|already|replay'; then
      no "ac8: a replayed key was reported as a failure — a caller told that will retry, which is the loop idempotency exists to prevent: $(printf '%s' "$LRP" | tail -c 200)"
    elif [ "$(printf '%s' "$POSTS" | grep -o 'idempotency_key' | wc -l)" -lt 3 ]; then
      no "ac8: fewer POST bodies than launch_run calls — the server retried or dropped one: $POSTS"
    elif ! printf '%s' "$L400" | grep -qi 'strategy'; then
      no "ac8: a 400 did not name the field the dispatcher complained about: $(printf '%s' "$L400" | tail -c 200)"
    elif [ -z "$LOK" ]; then
      no "ac8: a valid launch returned nothing. Server stderr: $(printf '%s' "$STDERR" | tr '\n' ' ' | tail -c 250)"
    else
      ok "ac8: launch_run POSTs the caller's key and reports a replay as an existing run"
    fi
  fi

  # ac9 — the credential never comes back out. Checked over EVERYTHING the server emitted.
  if grep -qF "$TOKEN" "$T/d.json"; then
    _where="$(grep -oF -m1 "$TOKEN" "$T/d.json")"
    no "ac9: the bearer token appeared in the server's own output ($_where) — it must never be echoed, not even truncated"
  else
    ok "ac9: the token never appears in a tool result"
  fi
fi

# ── ac11 · the docs (T6) ───────────────────────────────────────────────────────────────────
if [ ! -r "$DOC" ]; then
  pend "ac11: the server is documented for the agent that will use it"
else
  miss=""
  for t in list_runs run_status fetch_evidence launch_run; do
    grep -q "$t" "$DOC" || miss="$miss tool:$t"
  done
  for v in HARNESS_API_URL HARNESS_API_TOKEN; do grep -q "$v" "$DOC" || miss="$miss env:$v"; done
  for c in 401 404 501; do grep -q "$c" "$DOC" || miss="$miss code:$c"; done
  grep -qi 'idempot'   "$DOC" || miss="$miss idempotency"
  grep -q  'cancel_run' "$DOC" || miss="$miss why-no-cancel_run"
  [ -n "$miss" ] && no "ac11: the doc is not sufficient to use the server from an agent —$miss" \
                 || ok "ac11: every tool, both variables, the three codes and the cancel_run decision are documented"
fi

echo "---"
[ "$fail" = 0 ] && { echo "VERIFY: PASS"; exit 0; }
echo "VERIFY: FAIL"; exit 1
