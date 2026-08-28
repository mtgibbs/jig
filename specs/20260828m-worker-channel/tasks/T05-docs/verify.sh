#!/usr/bin/env bash
# T05 — the documentation.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
DOC="$(grep -rl 'HARNESS_REPORT_URL' "$ROOT/docs" 2>/dev/null | head -1)"
if [ -z "$DOC" ]; then
  no "ac1: the channel, its endpoints and its guarantees are documented"
  no "ac2: the reason the channel is outbound in both directions is recorded"
  gate_done
fi
miss=""
grep -q 'HARNESS_REPORT_TOKEN' "$DOC" || miss="$miss token-var"
for e in status attempts control; do grep -q "$e" "$DOC" || miss="$miss endpoint:$e"; done
grep -qiE 'run.?key'            "$DOC" || miss="$miss run-key"
grep -qiE 'unset|not configured|no url' "$DOC" || miss="$miss unconfigured-guarantee"
grep -qiE 'fail open|best.effort|never fail' "$DOC" || miss="$miss failure-discipline"
[ -z "$miss" ] && ok "ac1: the channel, its endpoints and its guarantees are documented" \
               || no "ac1: the doc is not enough to run or trust the channel —$miss ($DOC)"
if grep -qiE 'poll|outbound|cannot connect|ephemeral|notice' "$DOC"; then
  ok "ac2: the reason the channel is outbound in both directions is recorded"
else
  no "ac2: the doc does not say why nothing can connect INTO a worker — without that, the next person builds an inbound endpoint nothing can reach ($DOC)"
fi
gate_done
