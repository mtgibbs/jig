#!/usr/bin/env bash
# Gate for T03-ledger-surface (20260831v-work-mutation).
#
# The rows become the research surface: mutant-ledger.py renders a work-sensitivity
# section from worksens-*.jsonl — UNNOTICED first with diffs, verbally separated from the
# enforcement table (the header must say telemetry), and present-but-empty when no rows
# exist, because an absent section reads as an unbuilt feature, not an unmeasured fleet.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
ML="$R/scripts/mutant-ledger.py"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

mk_evid(){ # <with-worksens: yes|no> — a minimal evidence dir the ledger will accept
  local d
  d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  cat > "$d/selftest-fxspec.jsonl" <<'ROWS'
{"ts":"2026-09-01T00:00:00Z","run_id":"r1","spec":"fxspec","task":"T01-t","mutant":"m.sh","assertion":"ac1","target":"x.sh","why":"w","verdict":"KILLED","gate_rc":1,"diff":"-a\n+b","diff_lines":2,"instead":[]}
{"run_complete":true,"run_id":"r1","spec":"fxspec","task":"T01-t","killed":1,"survivor":0,"wrong_reason":0,"hung":0}
ROWS
  if [ "$1" = yes ]; then
    cat > "$d/worksens-fxspec.jsonl" <<'ROWS'
{"ts":"2026-09-01T00:00:01Z","run_id":"w1","spec":"fxspec","task":"T01-t","commit":"abc1234","operator":"drop-line","target":"noticed.txt","site":"line-3","verdict":"NOTICED","gate_rc":1,"diff":"-the load-bearing line","kind":"work"}
{"ts":"2026-09-01T00:00:02Z","run_id":"w1","spec":"fxspec","task":"T01-t","commit":"abc1234","operator":"revert-hunk","target":"quiet.txt","site":"hunk-1","verdict":"UNNOTICED","gate_rc":0,"diff":"SENTINEL-UNNOTICED-DIFF","kind":"work"}
{"run_complete":true,"run_id":"w1","spec":"fxspec","task":"T01-t","commit":"abc1234","noticed":1,"unnoticed":1,"hung":0,"kind":"work"}
ROWS
  fi
  printf '%s' "$d"
}

# ── ac1: rows render, UNNOTICED first, diff visible ──
E1="$(mk_evid yes)"; O1="$(mktemp -d)"; _FX="$_FX $O1"
python3 "$ML" --evid "$E1" --out "$O1" >/dev/null 2>&1
MD="$O1/mutant-ledger.md"
if [ ! -s "$MD" ]; then
  no "ac1: ledger did not render at all"
else
  grep -qi "work.sensitivity" "$MD" \
    && ok "ac1: the work-sensitivity section renders from worksens rows" \
    || no "ac1: no work-sensitivity section in the ledger"
  _un="$(grep -n "UNNOTICED" "$MD" | head -1 | cut -d: -f1)"
  _no="$(grep -n "quiet.txt\|noticed.txt" "$MD" >/dev/null; grep -n "NOTICED" "$MD" | grep -v UNNOTICED | head -1 | cut -d: -f1)"
  if [ -n "$_un" ] && [ -n "$_no" ] && [ "$_un" -lt "$_no" ]; then
    ok "ac1: UNNOTICED probes sort first — the leads are the headline"
  else
    no "ac1: UNNOTICED does not lead the section (unnoticed@${_un:-none}, noticed@${_no:-none})"
  fi
  grep -q "SENTINEL-UNNOTICED-DIFF" "$MD" \
    && ok "ac1: the unnoticed probe's diff is visible in the ledger" \
    || no "ac1: the probe diff is missing — a lead nobody can read is not a lead"
fi

# ── ac2: no rows -> the section says so instead of vanishing ──
E2="$(mk_evid no)"; O2="$(mktemp -d)"; _FX="$_FX $O2"
python3 "$ML" --evid "$E2" --out "$O2" >/dev/null 2>&1
if grep -qi "work.sensitivity" "$O2/mutant-ledger.md" 2>/dev/null; then
  ok "ac2: the section is present even with zero worksens rows"
else
  no "ac2: the section vanishes when unmeasured — reads as unbuilt, not unmeasured"
fi

# ── ac3: the section names its posture ──
grep -qi "telemetry" "$MD" 2>/dev/null \
  && ok "ac3: the section header names the telemetry posture" \
  || no "ac3: nothing says telemetry — sensitivity counts will be read as gate failures"

# ── ac4: the store is documented ──
if grep -q "worksens-" "$R/.evidence/README.md" 2>/dev/null && \
   grep -qi "telemetry" "$R/.evidence/README.md" 2>/dev/null; then
  ok "ac4: .evidence/README.md documents the worksens store and the posture"
else
  no "ac4: .evidence/README.md does not document worksens-*.jsonl with the enforcement/telemetry distinction"
fi

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T03 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
