#!/usr/bin/env bash
# T03 — the document answers the questions a reader actually arrives with.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT

DOC="$ROOT/docs/loop-container.md"
[ -f "$DOC" ] || { no "t03: docs/loop-container.md does not exist"; gate_done; }

# A docs gate can only check that the load-bearing FACTS are present — it cannot judge prose, and
# pretending otherwise produces a gate that rewards keyword stuffing. So: assert the handful of
# strings a reader would grep for and could not reconstruct, and nothing about how they are phrased.

if grep -q 'mcp-homelab\.mcp-homelab\.svc\.cluster\.local:3000' "$DOC"; then
  ok "t03-1: the in-cluster Service endpoint is written down"
else
  no "t03-1: the in-cluster endpoint mcp-homelab.mcp-homelab.svc.cluster.local:3000 is absent — it is the one address a Job needs and cannot guess"
fi

if grep -q 'mcp\.lab\.mtgibbs\.dev' "$DOC"; then
  ok "t03-2: the ingress endpoint is still documented for laptop use"
else
  no "t03-2: the laptop's ingress URL is absent — documenting only the in-cluster URL implies the ingress path was removed"
fi

if grep -q 'MCP_HOMELAB_API_KEY' "$DOC"; then
  ok "t03-3: the credential variable is named"
else
  no "t03-3: MCP_HOMELAB_API_KEY is not named in the doc"
fi

# The synonym may appear ONLY as the recorded mistake, which is exactly where it belongs. So this
# asserts it is not presented as usable, rather than asserting it is absent.
if grep -q 'MCP_HOMELAB_KEY\b' "$DOC" && ! grep -qi 'MCP_HOMELAB_KEY.*\(wrong\|not\|fault\|mistake\|never\)\|\(wrong\|not\|fault\|mistake\|never\).*MCP_HOMELAB_KEY' "$DOC"; then
  no "t03-4: the doc mentions MCP_HOMELAB_KEY without marking it as the wrong name — a reader will copy it"
else
  ok "t03-4: the synonym is either absent or marked as the mistake it was"
fi

if grep -q 'mcp-homelab-secrets\|mcp-homelab/api-key' "$DOC"; then
  ok "t03-5: the credential's existing source is recorded, so nobody mints a second one"
else
  no "t03-5: the doc does not say where the key comes from (1Password mcp-homelab/api-key via the mcp-homelab-secrets ExternalSecret) — reuse-before-mint is unenforceable if the reader cannot find the existing item"
fi

if grep -q 'not-an-mcp-endpoint' "$DOC"; then
  ok "t03-6: the failure class a reader will actually be staring at is explained"
else
  no "t03-6: not-an-mcp-endpoint is not explained — it is the class that looks like an outage and is not one"
fi

# The portability guarantee has to be stated as a guarantee. A reader who is unsure whether a
# no-MCP spec still runs offline will not risk it.
if grep -qi 'none' "$DOC" && grep -qi 'no probe\|no network call\|exactly as\|unchanged' "$DOC"; then
  ok "t03-7: the doc states that a spec declaring no MCP causes no probe and no network call"
else
  no "t03-7: the doc does not state the guarantee that declaring no MCP (or none) leaves behaviour unchanged with no network call"
fi

gate_done
