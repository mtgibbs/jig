#!/usr/bin/env bash
# T02 gate — specs/TEMPLATE.md states the unconditional refusal and names no escape.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

grep -qi 'refuses a multi-task spec without a .tasks/. directory' "$R/specs/TEMPLATE.md" \
  && ok "ac1: TEMPLATE.md states the refusal" \
  || no "ac1: TEMPLATE.md no longer states the refusal"
grep -qi 'no override' "$R/specs/TEMPLATE.md" \
  && ok "ac1: TEMPLATE.md says there is no override" \
  || no "ac1: TEMPLATE.md does not state that no override exists"
grep -q 'ALLOW_MONOLITHIC' "$R/specs/TEMPLATE.md" \
  && no "ac2: TEMPLATE.md still offers the hatch" \
  || ok "ac2: TEMPLATE.md names no escape"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
