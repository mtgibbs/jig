#!/usr/bin/env bash
# T01 — the probe tells four failures apart, and still says yes to a working server.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'fixture_stop 2>/dev/null; rm -rf "$T"' EXIT
. "$ROOT/specs/20260828n-mcp-reachable/lib/fixtures.sh"

SECRET="probe-fixture-key-2f8c1d"

if [ ! -f "$ROOT/scripts/mcp-probe.sh" ]; then
  no "ac1-6: scripts/mcp-probe.sh does not exist"
  gate_done
fi

# ac1 — green is REACHABLE. Without this the other five assertions are satisfied by a probe that
# refuses everything, which would pass a one-direction test and disable every MCP-declaring spec.
fixture_start ok
mkconfig "$T/exec-qwen.json" homelab "$FIX_URL" MCP_FIXTURE_KEY
MCP_FIXTURE_KEY="$SECRET" probe homelab "$T/exec-qwen.json"
if [ "$PROBE_RC" != 0 ]; then
  no "ac1: a server that answers initialize correctly was rejected (rc=$PROBE_RC): $(echo "$PROBE_OUT" | head -2 | tr '\n' ' ')"
elif ! echo "$PROBE_OUT" | grep -qi '\bok\b'; then
  no "ac1: exit 0 but the class line does not say ok: $(echo "$PROBE_OUT" | head -1)"
else
  ok "ac1: a working server classifies ok and exits 0"
fi

# ac1b — the other interpolation spelling. Both {env:NAME} and ${NAME} are in live use here, and a
# probe that reads only one calls a good config `unconfigured` — a false negative that would abort
# runs for no reason.
mkconfig "$T/dollar.json" homelab "$FIX_URL" MCP_FIXTURE_KEY dollar
MCP_FIXTURE_KEY="$SECRET" probe homelab "$T/dollar.json"
if [ "$PROBE_RC" != 0 ]; then
  no "ac1b: the \${NAME} interpolation form was not understood (rc=$PROBE_RC): $(echo "$PROBE_OUT" | head -1)"
else
  ok "ac1b: both {env:NAME} and \${NAME} resolve to the same credential"
fi
fixture_stop

# ac2 — connection refused is unreachable, and it is bounded.
mkconfig "$T/dead.json" homelab "$DEAD_URL" MCP_FIXTURE_KEY
_t0=$(date +%s); MCP_FIXTURE_KEY="$SECRET" probe homelab "$T/dead.json"; _t1=$(date +%s)
if [ "$PROBE_RC" = 124 ]; then
  no "ac2: the probe hung against a dead endpoint — the call is not bounded"
elif [ "$PROBE_RC" = 0 ]; then
  no "ac2: a refused connection was reported as usable"
elif ! echo "$PROBE_OUT" | grep -qi 'unreachable'; then
  no "ac2: a refused connection did not classify unreachable: $(echo "$PROBE_OUT" | head -1)"
elif [ $((_t1-_t0)) -ge 20 ]; then
  no "ac2: correct class, but it took $((_t1-_t0))s — the bound is too loose to sit in a preflight"
else
  ok "ac2: a refused connection classifies unreachable, bounded"
fi

# ac3 — 401 is unauthorized, NOT unreachable. This is the assertion that separates a real
# classification from a cosmetic one.
fixture_start unauthorized
mkconfig "$T/401.json" homelab "$FIX_URL" MCP_FIXTURE_KEY
MCP_FIXTURE_KEY="$SECRET" probe homelab "$T/401.json"
if [ "$PROBE_RC" = 0 ]; then
  no "ac3: a 401 was reported as usable"
elif echo "$PROBE_OUT" | grep -qi 'unreachable'; then
  no "ac3: a 401 classified as unreachable — this is exactly the collapse the spec exists to stop: $(echo "$PROBE_OUT" | head -1)"
elif ! echo "$PROBE_OUT" | grep -qi 'unauthorized'; then
  no "ac3: a 401 did not classify unauthorized: $(echo "$PROBE_OUT" | head -1)"
else
  ok "ac3: a 401 classifies unauthorized, not unreachable"
fi

# ac6 — the credential never comes back out. Checked here, while a real key is in the environment
# and the probe has just failed: the failure path is where a value gets echoed "to help".
if echo "$PROBE_OUT" | grep -qF "$SECRET"; then
  no "ac6: the credential's VALUE appeared in the probe's output on the failure path"
else
  ok "ac6: the credential's value never appears in output"
fi
fixture_stop

# ac4 — an HTML body is not an MCP answer. `Cannot POST /register` cost an hour by reading as
# "the server is down"; it must classify as an endpoint/credential problem instead.
fixture_start html404
mkconfig "$T/html.json" homelab "$FIX_URL" MCP_FIXTURE_KEY
MCP_FIXTURE_KEY="$SECRET" probe homelab "$T/html.json"
if [ "$PROBE_RC" = 0 ]; then
  no "ac4: an HTML 404 was reported as usable"
elif echo "$PROBE_OUT" | grep -qi 'unreachable'; then
  no "ac4: an HTML 404 classified as unreachable — that reading is what sent 2026-08-28 to the cluster instead of the config: $(echo "$PROBE_OUT" | head -1)"
elif ! echo "$PROBE_OUT" | grep -qi 'not-an-mcp-endpoint'; then
  no "ac4: an HTML 404 did not classify not-an-mcp-endpoint: $(echo "$PROBE_OUT" | head -1)"
else
  ok "ac4: an HTML body classifies not-an-mcp-endpoint"
fi
fixture_stop

# ac5 — an unset credential variable is a LOCAL mistake and must say so. Reporting it as a network
# problem is what sent the 2026-08-28 diagnosis at the cluster for an hour. The fixture endpoint is
# live and correct here on purpose: the only thing wrong is the variable, so `unreachable` or `ok`
# would both be lies.
fixture_start ok
mkconfig "$T/unset.json" homelab "$FIX_URL" MCP_FIXTURE_KEY
PROBE_OUT="$( (cd "$T" && unset MCP_FIXTURE_KEY; gate_timeout 30 bash "$ROOT/scripts/mcp-probe.sh" homelab "$T/unset.json") 2>&1 )"; PROBE_RC=$?
if [ "$PROBE_RC" = 0 ]; then
  no "ac5: an unset credential variable was reported as usable"
elif ! echo "$PROBE_OUT" | grep -qi 'unconfigured'; then
  no "ac5: an unset credential variable did not classify unconfigured: $(echo "$PROBE_OUT" | head -1)"
else
  ok "ac5: an unset credential variable classifies unconfigured"
fi

# ac5b — a server the config does not mention is unconfigured, not unreachable.
MCP_FIXTURE_KEY="$SECRET" probe kiwix "$T/unset.json"
if [ "$PROBE_RC" = 0 ]; then
  no "ac5b: a server absent from the config was reported as usable"
elif ! echo "$PROBE_OUT" | grep -qi 'unconfigured'; then
  no "ac5b: a server absent from the config did not classify unconfigured: $(echo "$PROBE_OUT" | head -1)"
else
  ok "ac5b: a server absent from the config classifies unconfigured"
fi
fixture_stop

gate_done
