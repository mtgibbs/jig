#!/usr/bin/env bash
# T04 — the documentation.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT

DOC="$(grep -rl 'RALPH_FORCE_FROM' "$ROOT/docs" 2>/dev/null | head -1)"
if [ -z "$DOC" ]; then
  no "ac1: resume and the overrides are documented under docs/"
  no "ac2: the inbound constraint that shapes stop and pause is recorded"
  gate_done
fi
miss=""
grep -q 'RALPH_FORCE_ALL' "$DOC" || miss="$miss RALPH_FORCE_ALL"
grep -qiE 'satisfied|already passes'  "$DOC" || miss="$miss what-satisfied-means"
grep -qiE 'per-task'  "$DOC" || miss="$miss why-only-per-task-specs"
grep -qiE 'example|`RALPH_FORCE_FROM=' "$DOC" || miss="$miss example"
[ -z "$miss" ] && ok "ac1: resume and the overrides are documented under docs/" \
               || no "ac1: the doc is not enough to use resume —$miss ($DOC)"

if grep -qiE 'poll|outbound|cannot connect|not reachable|notice' "$DOC"; then
  ok "ac2: the inbound constraint that shapes stop and pause is recorded"
else
  no "ac2: the doc does not say why stop and pause must be NOTICED by a worker rather than sent to it — without that, the next person builds an endpoint nothing can reach ($DOC)"
fi
gate_done
