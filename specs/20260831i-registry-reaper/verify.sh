#!/usr/bin/env bash
# Gate for 20260831i-registry-reaper. Single-task spec: one gate, no pend.
# A fake kubectl answers by job name and logs its calls; the api test boots the REAL
# api.py on an ephemeral port. The dispatch-core gate is the separate regression control.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../.." && pwd -P)"
DP="$R/scripts/dispatch/dispatcher.py"
AP="$R/scripts/dispatch/api.py"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"
SRV=""
cleanup(){ [ -n "$SRV" ] && kill "$SRV" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT

# Fake kubectl: `kubectl get job <name> -n <ns> -o json`. Answers by name, logs calls.
KUBECTL="$W/kubectl"
cat > "$KUBECTL" <<EOF
#!/usr/bin/env bash
echo "\$3" >> "$W/kubectl.calls"
case "\$3" in
  run-gone)   echo 'Error from server (NotFound)' >&2; exit 1 ;;
  run-active) echo '{"status":{"active":1}}' ;;
  run-sad)    echo '{"status":{"failed":1}}' ;;
  run-happy)  echo '{"status":{"succeeded":1}}' ;;
  run-fresh)  echo '{"status":{}}' ;;
  *)          echo '{"status":{"active":1}}' ;;
esac
EOF
chmod +x "$KUBECTL"

REG="$W/registry.jsonl"
mk_reg(){
  cat > "$REG" <<'EOF'
{"event_id":"e-gone","repo":"r","spec":"s","strategy":"build-converge","job_name":"run-gone","status":"launched"}
{"event_id":"e-active","repo":"r","spec":"s","strategy":"build-converge","job_name":"run-active","status":"launched"}
{"event_id":"e-sad","repo":"r","spec":"s","strategy":"build-converge","job_name":"run-sad","status":"launched"}
{"event_id":"e-happy","repo":"r","spec":"s","strategy":"build-converge","job_name":"run-happy","status":"launched"}
{"event_id":"e-fresh","repo":"r","spec":"s","strategy":"build-converge","job_name":"run-fresh","status":"launched"}
{"event_id":"e-settled","repo":"r","spec":"s","strategy":"build-converge","job_name":"run-settled","status":"failed"}
EOF
}
mk_reg
cp "$REG" "$W/registry.before"

run_reap(){
  ( cd "$R/scripts/dispatch" && HARNESS_KUBECTL="$KUBECTL" python3 -c "
import json, dispatcher
print(json.dumps(dispatcher.reap_runs('$REG', 'harness-fleet')))
" )
}

if ! grep -q 'def reap_runs' "$DP" 2>/dev/null; then
  no "ac1..ac7: reap_runs does not exist in dispatcher.py"
else
  : > "$W/kubectl.calls"
  summary="$(run_reap 2>&1)"; rc=$?
  [ "$rc" -eq 0 ] || no "reap_runs raised or exited $rc — $summary"

  status_of(){ # <event_id> -> effective status via get_run (last-wins is part of the contract)
    ( cd "$R/scripts/dispatch" && python3 -c "
import dispatcher
r = dispatcher.get_run('$REG', '$1')
print((r or {}).get('status', 'MISSING'), (r or {}).get('reason', ''))
" )
  }

  # ── ac1: absent job → failed, reaped reason, get_run sees it ──
  s="$(status_of e-gone)"
  case "$s" in
    "failed reaped: job absent"*) ok "ac1: absent job reaped to failed and get_run returns the superseding record" ;;
    *) no "ac1: e-gone reads as '$s' after a reap" ;;
  esac

  # ── ac2: active job untouched; indeterminate status untouched ──
  s="$(status_of e-active)"
  case "$s" in
    launched*) ok "ac2: active job left alone" ;;
    *) no "ac2: e-active reads as '$s' — a live run was reaped" ;;
  esac
  s="$(status_of e-fresh)"
  case "$s" in
    launched*) ok "ac2: indeterminate job status left for the next pass" ;;
    *) no "ac2: e-fresh reads as '$s' — an indeterminate status was guessed at" ;;
  esac

  # ── ac3: failed/succeeded jobs get matching terminal records ──
  s="$(status_of e-sad)"
  case "$s" in
    "failed reaped: job failed"*) ok "ac3: failed job reaped to failed" ;;
    *) no "ac3: e-sad reads as '$s'" ;;
  esac
  s="$(status_of e-happy)"
  case "$s" in
    "succeeded reaped: job succeeded"*) ok "ac3: succeeded job reaped to succeeded" ;;
    *) no "ac3: e-happy reads as '$s'" ;;
  esac

  # ── ac4: settled records are not re-queried ──
  grep -q 'run-settled' "$W/kubectl.calls" \
    && no "ac4: the reaper queried a settled record's job" \
    || ok "ac4: settled records were not re-queried"

  # ── ac7: append-only — the original lines survive byte-identical ──
  head -6 "$REG" | cmp -s - "$W/registry.before" \
    && ok "ac7: the reap appended; prior lines are byte-identical" \
    || no "ac7: the reap rewrote existing registry lines"

  # ── ac5: broken kubectl appends nothing ──
  mk_reg
  _n_before="$(wc -l < "$REG" | tr -d ' ')"
  ( cd "$R/scripts/dispatch" && HARNESS_KUBECTL="$W/kubectl-missing" python3 -c "
import dispatcher
dispatcher.reap_runs('$REG', 'harness-fleet')
" ) >/dev/null 2>&1
  _n_after="$(wc -l < "$REG" | tr -d ' ')"
  [ "$_n_before" = "$_n_after" ] \
    && ok "ac5: a broken kubectl marks nothing (no signal is not a verdict)" \
    || no "ac5: kubectl failure appended records ($_n_before -> $_n_after)"
fi

# ── ac6: POST /reap on the real api.py ──
mk_reg
PORT=$(( 21000 + RANDOM % 20000 ))
TOK="gate-test-token"
( cd "$R/scripts/dispatch" && \
  HARNESS_API_TOKEN="$TOK" HARNESS_REGISTRY_PATH="$REG" HARNESS_KUBECTL="$KUBECTL" \
  DISPATCH_PORT="$PORT" python3 api.py >/dev/null 2>&1 ) &
SRV=$!
_up=0
for _i in $(seq 1 50); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/runs" 2>/dev/null && { _up=1; break; }
  sleep 0.1
done
if [ "$_up" != 1 ]; then
  no "ac6: api.py did not come up on :$PORT"
else
  code_noauth="$(curl -s -o /dev/null -w '%{http_code}' -X POST "http://127.0.0.1:$PORT/reap")"
  [ "$code_noauth" = 401 ] \
    && ok "ac6: /reap without the token 401s" \
    || no "ac6: expected 401 without token, got $code_noauth"
  body="$(curl -s -X POST -H "Authorization: Bearer $TOK" "http://127.0.0.1:$PORT/reap")"
  printf '%s' "$body" | grep -q '"checked"' && printf '%s' "$body" | grep -q '"reaped"' \
    && ok "ac6: /reap returns {checked, reaped}" \
    || no "ac6: /reap body: $body"
  grep -q 'reaped: job absent' "$REG" \
    && ok "ac6: the route's reap reached the registry" \
    || no "ac6: no reaped record in the registry after POST /reap"
fi

# ── ac8 ──
python3 -m py_compile "$DP" "$AP" 2>/dev/null \
  && ok "ac8: dispatcher.py and api.py compile" \
  || no "ac8: py_compile fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
