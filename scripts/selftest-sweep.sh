#!/usr/bin/env bash
# scripts/selftest-sweep.sh — record every mutant corpus in one command and regenerate the ledger.
#
# Usage: ./selftest-sweep.sh [--dry-run]
#
# The sweep finds every corpus (specs/*/tasks/*/mutants), runs gate-selftest.sh on each with
# SELFTEST_EVID pointing at .evidence/, then regenerates the ledger with mutant-ledger.py.
# Exit 0 only if every corpus was clean AND the ledger regenerated; any failure makes the sweep
# exit 1 — the ledger still regenerates first, because a red sweep is when the record matters.
set -uo pipefail

_SD="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$_SD/.." && pwd)"

dry_run=0
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=1
fi

worst=0

while IFS= read -r corpus_dir; do
  task_dir="$(dirname "$corpus_dir")"
  repo_rel="${task_dir#$R/}"

  if [ "$dry_run" = 1 ]; then
    echo "would run: $repo_rel"
    continue
  fi

  echo "== $repo_rel"
  SELFTEST_EVID="$R/.evidence" bash "$_SD/gate-selftest.sh" "$task_dir"
  _rc=$?
  if [ "$_rc" -ne 0 ]; then
    worst=$_rc
  fi
done < <(find "$R/specs" -type d -name mutants -path '*/tasks/*' | sort)

echo "== regenerating ledger"
python3 "$_SD/mutant-ledger.py" --evid "$R/.evidence" --out "$R/.evidence"
_ledger_rc=$?
if [ "$_ledger_rc" -ne 0 ]; then
  worst=$_ledger_rc
fi

exit $worst
