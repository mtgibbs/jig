#!/usr/bin/env bash
# specs/20260831a-selftest-sweep/verify.sh — CONVERGENCE gate (per-task shape, 20260828i).
# Integration + end-state ONLY; the loop runs this once, at the end, under STRICT. The
# per-task criteria live in tasks/T01-sweep-script and tasks/T02-readme-bullet — no pend
# here or there. (This replaced the original monolithic pend-staged gate: Tuning log,
# 2026-08-31, the conversion.)
set -uo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

# end-1 · integration: the shipped script, run from the repo root, agrees with an
# independent enumeration of the real corpora.
if [ -x "$R/scripts/selftest-sweep.sh" ]; then
  _dry="$( (cd "$R" && bash scripts/selftest-sweep.sh --dry-run 2>/dev/null) | grep -c '^would run: ' )"
  _ind="$(find "$R/specs" -type d -name mutants -path '*/tasks/*' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$_ind" -lt 6 ]; then
    no "end-1: control — independent find sees only $_ind corpora; the comparison is degenerate"
  elif [ "$_dry" = "$_ind" ]; then
    ok "end-1: sweep --dry-run enumerates all $_ind real corpora from the repo root"
  else
    no "end-1: sweep --dry-run lists $_dry corpora, independent find sees $_ind"
  fi
else
  no "end-1: scripts/selftest-sweep.sh missing or not executable"
fi

# end-2 · end state: the README documents the command.
grep -q 'selftest-sweep.sh' "$R/.evidence/README.md" 2>/dev/null \
  && ok "end-2: .evidence/README.md documents the sweep" \
  || no "end-2: the README bullet is absent"

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
