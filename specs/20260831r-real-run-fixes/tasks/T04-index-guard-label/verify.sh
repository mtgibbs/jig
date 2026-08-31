#!/usr/bin/env bash
# Gate for T04-index-guard-label (20260831r-real-run-fixes).
# The index-row guard probes with the bare task label ("T1"), matching what
# loop-index.py writes — not the colon-bearing first word of the task line.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
RB="$R/scripts/ralph-build.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

# ── ac1: the colon-keeping expansion is gone from the guard (and the file) ──
n_old="$(grep -cF '${HB_TASK%% *}' "$RB" || true)"
[ "${n_old:-0}" -eq 0 ] \
  && ok "ac1: no first-word expansion (colon kept) remains in ralph-build.sh" \
  || no "ac1: $n_old use(s) of the colon-keeping expansion remain — the guard probes for a label the indexer never writes"

# ── ac2: the guard block uses the bare-label expansion, same as the metrics call ──
blk="$(sed -n '/no row for/,+0p;/the record was not collected/,+0p;/has no row/,+0p' "$RB")"
guard_uses="$(grep -F 'no row for' "$RB"; grep -F 'the record was not collected' "$RB")"
echo "$guard_uses" | grep -qF '${HB_TASK%%:*}' \
  && ok "ac2: the guard's WARN lines use the bare label expansion" \
  || no "ac2: the guard's WARN lines do not use the bare label expansion"
grep -F '\"task\": *' "$RB" | grep -qF '${HB_TASK%%:*}' \
  && ok "ac2: the row probe greps for the bare label" \
  || no "ac2: the row probe still greps for a label with the colon"

# ── ac3: the expansion produces what the indexer writes (semantics pin) ──
HB_TASK='T1: ONE Live Activity contract, and the island shows the marker count.'
lbl="${HB_TASK%%:*}"
idx="$(mktemp)"; trap 'rm -f "$idx"' EXIT
printf '{"task": "T1", "landed": true}\n' > "$idx"
grep -q "\"task\": *\"$lbl\"" "$idx" \
  && ok "ac3: bare-label probe matches a real indexer row (label '$lbl')" \
  || no "ac3: bare-label probe fails against a real indexer row"

bash -n "$RB" && ok "ac4: ralph-build.sh passes bash -n" || no "ac4: ralph-build.sh fails bash -n"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T04 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
