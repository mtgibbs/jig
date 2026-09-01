#!/usr/bin/env bash
# Gate for T02-artifact-read (20260831s-live-board-evidence).
#
# The coordinator has stored artifacts since 20260828o and served none of them: /api/artifact
# answered 400 "key required" for every request including well-formed ones, and the /artifact/
# branch above it looked a run up, discarded it, and 404'd. This gate drives the REAL
# coordinator.py over a real socket — a grep of the source proves nothing here, because the
# source already contains every string this route needs (Trap A).
#
# ac8's "the board is unchanged" is measured by diffing /api/runs across the 404, not by
# grepping for RUNS.get: `_touch` and `RUNS.get` both appear in the file today (Trap A).
# ac9's "no token needed" ships a positive control — a POST without the token must be REFUSED
# in the same server, or "the GET worked" only proves the token was never in effect (Trap B).
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
# shellcheck source=/dev/null
. "$R/specs/lib/assert.sh"

COORD="$R/scripts/dispatch/coordinator.py"

_TMP=""
_PID=""
cleanup() {
  [ -n "$_PID" ] && kill "$_PID" 2>/dev/null
  for d in $_TMP; do rm -rf "$d"; done
}
trap cleanup EXIT

W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"; _TMP="$_TMP $W"

[ -f "$COORD" ] || { no "gate: $COORD missing"; gate_done; }

# A free port, chosen by the kernel and released immediately. Racy in principle, reliable in
# practice, and the only portable way to avoid colliding with a coordinator someone is
# already running on 8877 — which is exactly the machine this gate runs on.
PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
case "$PORT" in ''|*[!0-9]*) no "gate: could not pick a free port"; gate_done ;; esac
URL="http://127.0.0.1:$PORT"
TOK="t0ken-for-this-gate"

# The token is SET, so the write boundary is live. That makes ac9 a real relaxation being
# measured rather than an unconfigured server answering everything.
COORD_PORT="$PORT" HARNESS_REPORT_TOKEN="$TOK" python3 "$COORD" > "$W/coord.out" 2>&1 &
_PID=$!
_n=0
while [ "$_n" -lt 60 ]; do
  curl -s -o /dev/null --connect-timeout 1 "$URL/api/runs" && break
  _n=$((_n+1)); sleep 0.1
done
curl -s -o /dev/null --connect-timeout 1 "$URL/api/runs" \
  || { no "gate: coordinator did not come up on $PORT (see $W/coord.out)"; gate_done; }

KEY="fxhost/fxagent-4242"
NAME="T01-fx/1/selftest"
PAYLOAD='{"verdict":"SURVIVOR","why":"the <b>plausible</b> wrong thing"}'
printf '%s\n' "$PAYLOAD" > "$W/payload"

# status <method> <url> [extra curl args...] — HTTP code only; body lands in $W/body,
# headers in $W/hdr.
status() {
  local m="$1" u="$2"; shift 2
  curl -s -o "$W/body" -D "$W/hdr" -w '%{http_code}' -X "$m" --connect-timeout 2 "$@" "$u"
}

# ── the write, so there is something to read ────────────────────────────────────────────────
_c="$(status POST "$URL/runs/$KEY/attempts/T01-fx/1/artifacts/selftest" \
      -H "Authorization: Bearer $TOK" --data-binary "@$W/payload")"
[ "$_c" = "200" ] \
  || { no "gate: seeding the artifact failed (POST returned $_c) — nothing to read back"; gate_done; }

# ── ac9 positive control: the write boundary really is armed ────────────────────────────────
_c="$(status POST "$URL/runs/$KEY/attempts/T01-fx/1/artifacts/selftest" --data-binary "@$W/payload")"
[ "$_c" = "401" ] \
  && ok "ac9 control: an unauthenticated WRITE is refused (401) — the token is in effect" \
  || no "ac9 control: an unauthenticated write returned $_c, expected 401 — with the token inert, 'reads need no token' would pass for free"

# ── ac6 : a stored artifact reads back verbatim ─────────────────────────────────────────────
_c="$(status GET "$URL/api/artifact?key=fxhost%2Ffxagent-4242&name=T01-fx%2F1%2Fselftest")"
[ "$_c" = "200" ] \
  && ok "ac6: GET /api/artifact returns 200 for a stored artifact" \
  || no "ac6: GET /api/artifact returned $_c — the route is still the 400 stub"

if [ "$_c" = "200" ]; then
  grep -q 'plausible' "$W/body" \
    && ok "ac6: the response carries the artifact's bytes" \
    || no "ac6: the 200 body is not the stored artifact"
  # Verbatim, not re-serialised: a route that JSON-wraps the bytes breaks every non-JSON kind
  # (prompt, patch, diff, log) that shares this route.
  if diff -q "$W/payload" "$W/body" >/dev/null 2>&1; then
    ok "ac6: the bytes are returned verbatim, not re-wrapped"
  else
    no "ac6: the body differs from what was stored — prompt/patch/diff/log share this route and are not JSON"
  fi
fi

# The unencoded slash is legal in a query value and is what a human types with curl.
_c="$(status GET "$URL/api/artifact?key=$KEY&name=$NAME")"
[ "$_c" = "200" ] \
  && ok "ac6: an unencoded run key in the query resolves too" \
  || no "ac6: the unencoded key returned $_c — parse the query, do not split the path"

# ── ac10 : text/plain, never markup ─────────────────────────────────────────────────────────
grep -qi '^content-type:[[:space:]]*text/plain; *charset=utf-8' "$W/hdr" \
  && ok "ac10: artifacts are served text/plain; charset=utf-8" \
  || no "ac10: wrong Content-Type — worker bytes served as html execute in the board's own origin"

# ── ac7 : a missing parameter is named ──────────────────────────────────────────────────────
_c="$(status GET "$URL/api/artifact?name=$NAME")"
[ "$_c" = "400" ] \
  && ok "ac7: a request with no key is 400" \
  || no "ac7: missing key returned $_c, expected 400"
grep -q 'key' "$W/body" \
  && ok "ac7: the 400 names the missing parameter (key)" \
  || no "ac7: the 400 does not name 'key' — an error that does not say which parameter is a guess"

_c="$(status GET "$URL/api/artifact?key=$KEY")"
[ "$_c" = "400" ] \
  && ok "ac7: a request with no name is 400" \
  || no "ac7: missing name returned $_c, expected 400"
grep -q 'name' "$W/body" \
  && ok "ac7: the 400 names the missing parameter (name)" \
  || no "ac7: the 400 does not name 'name' — the stub's single 'key required' answers both cases wrongly"

# ── ac8 : an unknown artifact 404s, and does not touch the board ────────────────────────────
curl -s --connect-timeout 2 "$URL/api/runs" > "$W/runs.before"
grep -q "$KEY" "$W/runs.before" \
  && ok "ac8 control: /api/runs reports the seeded run before the 404s" \
  || no "ac8 control: the seeded run is not on the board — the before/after comparison would be vacuous"

_c="$(status GET "$URL/api/artifact?key=ghost%2Fghost-1&name=$NAME")"
[ "$_c" = "404" ] \
  && ok "ac8: an unknown run is 404" \
  || no "ac8: unknown run returned $_c, expected 404"

_c="$(status GET "$URL/api/artifact?key=fxhost%2Ffxagent-4242&name=T99-nope%2F9%2Fnope")"
[ "$_c" = "404" ] \
  && ok "ac8: a known run with an unknown artifact is 404" \
  || no "ac8: unknown artifact returned $_c, expected 404"

curl -s --connect-timeout 2 "$URL/api/runs" > "$W/runs.after"
if diff -q "$W/runs.before" "$W/runs.after" >/dev/null 2>&1; then
  ok "ac8: the set of runs the board reports is byte-identical across the 404s"
else
  no "ac8: /api/runs changed across a 404 — a read called _touch, which creates a ghost row AND evicts oldest-first (harness#46)"
fi

# ── ac9 : the read itself needs no token ────────────────────────────────────────────────────
_c="$(status GET "$URL/api/artifact?key=fxhost%2Ffxagent-4242&name=T01-fx%2F1%2Fselftest")"
[ "$_c" = "200" ] \
  && ok "ac9: an artifact read succeeds with no Authorization header, matching /api/runs" \
  || no "ac9: the read returned $_c without a token — the board is a browser and cannot send one"

gate_done
