#!/usr/bin/env bash
# Gate for 20260831e-unknown-route-writes-nothing. Single-task spec: one gate, no pend.
# Boots the REAL coordinator on an ephemeral port with a test token; curl is the probe.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../.." && pwd -P)"
CO="$R/scripts/dispatch/coordinator.py"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

PORT=$(( 20000 + RANDOM % 20000 ))
TOK="gate-test-token"
HARNESS_REPORT_TOKEN="$TOK" COORD_PORT="$PORT" COORD_STATE_PATH="" \
  python3 "$CO" >/dev/null 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null' EXIT

_up=0
for _i in $(seq 1 50); do
  curl -sf "http://127.0.0.1:$PORT/api/runs" >/dev/null 2>&1 && { _up=1; break; }
  sleep 0.1
done
[ "$_up" = 1 ] || { no "setup: coordinator did not come up on :$PORT"; echo; echo "VERIFY: failures above" >&2; exit 1; }

B="http://127.0.0.1:$PORT"

# ── ac1: authed POST to an unknown sub-route → 404, board byte-identical ──
before="$(curl -s "$B/api/runs")"
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $TOK" \
  -d '{}' "$B/runs/probe/x/bogus")"
after="$(curl -s "$B/api/runs")"
[ "$code" = 404 ] \
  && ok "ac1: the unknown sub-route 404s" \
  || no "ac1: expected 404 for /runs/probe/x/bogus, got $code"
[ "$before" = "$after" ] \
  && ok "ac1: /api/runs is byte-identical after the 404'd POST — no ghost row, no eviction" \
  || no "ac1: the 404'd POST changed the board — before: $before after: $after"

# ── ac2: positive control — a known route still creates the row ──
code2="$(curl -s -o /dev/null -w '%{http_code}' -X POST -H "Authorization: Bearer $TOK" \
  -d '{"phase":"running"}' "$B/runs/probe/x/status")"
after2="$(curl -s "$B/api/runs")"
[ "$code2" = 200 ] \
  && ok "ac2: control — POST /status returns 200" \
  || no "ac2: control — POST /status returned $code2"
printf '%s' "$after2" | grep -q '"probe/x"' \
  && ok "ac2: control — the row appears on the board (ac1's probe can see a created row)" \
  || no "ac2: control — no probe/x row after a valid status POST; ac1 is unmeasurable"

# ── ac3: the auth boundary is undisturbed — unauthed write 401s and writes nothing ──
before3="$(curl -s "$B/api/runs")"
code3="$(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{}' "$B/runs/ghost/y/status")"
after3="$(curl -s "$B/api/runs")"
[ "$code3" = 401 ] \
  && ok "ac3: an unauthed run-data write still 401s" \
  || no "ac3: expected 401, got $code3"
[ "$before3" = "$after3" ] \
  && ok "ac3: the 401'd POST wrote nothing" \
  || no "ac3: the unauthed POST changed the board"

# ── ac4 ──
python3 -m py_compile "$CO" 2>/dev/null \
  && ok "ac4: coordinator.py compiles" \
  || no "ac4: py_compile fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
