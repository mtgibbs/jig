#!/usr/bin/env bash
# Convergence gate for 20260828n — end state only; runs after the task gates.
#
# The task gates each prove their own piece. This asks the only question none of them can: does the
# whole path hold together, and is the misleading answer that motivated the spec actually gone.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'fixture_stop 2>/dev/null; rm -rf "$T"' EXIT
. "$ROOT/specs/20260828n-mcp-reachable/lib/fixtures.sh"

SECRET="end-fixture-key-4a17"

# end-1 — the four endpoints produce four DIFFERENT classes. Asserted as a set rather than one at a
# time, because the failure mode being prevented is not "wrong class" but "one class for
# everything": a probe answering `unreachable` four times satisfies every individual
# did-it-fail assertion and is exactly the 2026-08-28 bug.
mkdir -p "$T/w"
classes=""
fixture_start ok
mkconfig "$T/c.json" homelab "$FIX_URL" MCP_FIXTURE_KEY
MCP_FIXTURE_KEY="$SECRET" probe homelab "$T/c.json"; classes="$classes $(printf '%s' "$PROBE_OUT" | head -1 | tr -cd '[:alnum:]-' )"
fixture_stop
fixture_start unauthorized
mkconfig "$T/c.json" homelab "$FIX_URL" MCP_FIXTURE_KEY
MCP_FIXTURE_KEY="$SECRET" probe homelab "$T/c.json"; classes="$classes $(printf '%s' "$PROBE_OUT" | head -1 | tr -cd '[:alnum:]-' )"
fixture_stop
fixture_start html404
mkconfig "$T/c.json" homelab "$FIX_URL" MCP_FIXTURE_KEY
MCP_FIXTURE_KEY="$SECRET" probe homelab "$T/c.json"; classes="$classes $(printf '%s' "$PROBE_OUT" | head -1 | tr -cd '[:alnum:]-' )"
fixture_stop
mkconfig "$T/c.json" homelab "$DEAD_URL" MCP_FIXTURE_KEY
MCP_FIXTURE_KEY="$SECRET" probe homelab "$T/c.json"; classes="$classes $(printf '%s' "$PROBE_OUT" | head -1 | tr -cd '[:alnum:]-' )"

distinct="$(printf '%s\n' $classes | sort -u | wc -l | tr -d ' ')"
if [ "$distinct" -lt 4 ]; then
  no "end-1: four different endpoints produced $distinct distinct classes [$classes] — collapsing them is the bug, not a rounding of it"
else
  ok "end-1: working, unauthorized, not-an-mcp and unreachable each get their own answer"
fi

# end-2 — the credential survives the whole path without being printed anywhere. Checked across the
# probe's own output AND anything the run left behind, because the leak that matters is the one in
# a file somebody later pastes.
fixture_start unauthorized
mkconfig "$T/c.json" homelab "$FIX_URL" MCP_FIXTURE_KEY
MCP_FIXTURE_KEY="$SECRET" probe homelab "$T/c.json"
if printf '%s' "$PROBE_OUT" | grep -qF "$SECRET" || grep -rqF "$SECRET" "$T" 2>/dev/null; then
  no "end-2: the credential's value was written somewhere during a failing probe"
else
  ok "end-2: a failing probe leaves the credential's value nowhere"
fi
fixture_stop

# end-3 — the laptop bar. Nothing in this spec may require infrastructure to exist for a run that
# asked for none. This is the guarantee that keeps run-loop.sh usable on a plane.
if grep -n 'mcp-probe' "$ROOT/scripts/run-loop.sh" >/dev/null 2>&1; then
  if awk '/MCP/,/^  fi$/' "$ROOT/scripts/run-loop.sh" | grep -q 'none'; then
    ok "end-3: the probe is reached only through the declared-and-not-none path"
  else
    no "end-3: run-loop.sh calls the probe but the none/absent short-circuit is not visible in that block — a spec that declares nothing must not dial anything"
  fi
else
  no "end-3: run-loop.sh does not call the probe — the preflight is still asking the filesystem"
fi

gate_done
