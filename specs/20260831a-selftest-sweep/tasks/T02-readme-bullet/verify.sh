#!/usr/bin/env bash
# T2 — the README bullet's own gate. Per-task shape (20260828i): this task's criteria ONLY,
# no pend. The deliverable lives under .evidence/ — the loop's no-op guard defers to this
# gate precisely so that can work (20260831c).
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$ROOT/specs/lib/assert.sh"

RM="$ROOT/.evidence/README.md"
B1='- `scripts/selftest-sweep.sh` (run from anywhere) records every corpus above in one'
B2='  command and regenerates the ledger; `--dry-run` lists what it would run'

# ── ac05 · the §6b bullet, verbatim, in position ───────────────────────────────────────────
if [ ! -f "$RM" ]; then
  no "ac05: .evidence/README.md does not exist"
else
  _l1="$(grep -nF -e "$B1" "$RM" | head -1 | cut -d: -f1)"   # -e: the bullet starts with '- '
  if [ -z "$_l1" ]; then
    no "ac05: the sweep bullet's first line is not in the README (copy §6b verbatim)"
  else
    _next="$(sed -n "$((_l1 + 1))p" "$RM")"
    [ "$_next" = "$B2" ] \
      && ok "ac05: the bullet's two lines are verbatim (§6b)" \
      || no "ac05: the bullet's second line differs from §6b — got: $_next"
    _lm="$(grep -nF 'mutant-ledger.{md,html}' "$RM" | head -1 | cut -d: -f1)"
    if [ -z "$_lm" ]; then
      no "ac05: control — the mutant-ledger bullet is missing, so 'directly after' is unmeasurable"
    elif [ "$_l1" -gt "$_lm" ]; then
      ok "ac05: the bullet sits after the mutant-ledger bullet (line $_l1 > $_lm)"
    else
      no "ac05: the bullet is at line $_l1, BEFORE the mutant-ledger bullet at $_lm — §6b says directly after"
    fi
  fi
fi

gate_done
