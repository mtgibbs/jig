#!/usr/bin/env bash
# Gate for T01-mutate-tool (20260831v-work-mutation).
#
# The probe tool, proven on a real git fixture: a work commit adds marker.txt (which the
# fixture gate checks) and an inert line in base.txt (which it ignores). Probes derived
# from that commit must come back NOTICED where the gate really looks and UNNOTICED where
# it does not — both verdicts, each naming its file, or the instrument reads nothing.
# Determinism, tree-untouched, and the emission seam are each their own assertion.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
WM="$R/scripts/work-mutate.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

[ -f "$WM" ] || { no "ac5: scripts/work-mutate.sh does not exist"; echo "VERIFY: failures above" >&2; exit 1; }

mk_fx(){ # git fixture: base commit carries the spec+gate, work commit adds the probed diff
  local d
  d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs/20990101a-fx/tasks/T01-t"
  cat > "$d/specs/20990101a-fx/tasks/T01-t/verify.sh" <<'GATE'
#!/usr/bin/env bash
if grep -q MARKER-LINE marker.txt 2>/dev/null; then echo "  PASS  fx1"; exit 0; fi
echo "  FAIL  fx1: marker.txt must carry MARKER-LINE" >&2; exit 1
GATE
  chmod +x "$d/specs/20990101a-fx/tasks/T01-t/verify.sh"
  printf 'alpha\n' > "$d/base.txt"
  git -C "$d" add -A && git -C "$d" commit -qm base
  printf 'MARKER-LINE\n' > "$d/marker.txt"
  printf 'beta\n' >> "$d/base.txt"
  git -C "$d" add -A && git -C "$d" commit -qm work
  printf '%s' "$d"
}

run_wm(){ # <root> [env pairs...] — run the tool from the fixture root
  local d="$1"; shift
  ( cd "$d" && env -u SELFTEST_EVID "$@" bash "$WM" specs/20990101a-fx/tasks/T01-t 2>&1 )
}

FX="$(mk_fx)"

# snapshot the tree for ac3 (every file outside .git, hashed)
tree_hash(){ ( cd "$1" && find . -type f ! -path './.git/*' -print0 | sort -z | xargs -0 shasum | shasum | cut -d' ' -f1 ); }
_before="$(tree_hash "$FX")"

out="$(run_wm "$FX" RALPH_WORK_MUTANTS=10)"; rc=$?

# ── ac1: NOTICED where the gate looks, UNNOTICED where it does not ──
printf '%s' "$out" | grep "marker.txt" | grep -q "NOTICED" \
  && ok "ac1: a probe on marker.txt (the checked work) comes back NOTICED" \
  || no "ac1: no NOTICED verdict on marker.txt — the instrument missed the gate's real subject [rc=$rc]"
printf '%s' "$out" | grep "base.txt" | grep -q "UNNOTICED" \
  && ok "ac1: a probe on base.txt (the ignored work) comes back UNNOTICED" \
  || no "ac1: no UNNOTICED verdict on base.txt — either no probe reached it or the vocabulary is wrong"
[ "$rc" -eq 0 ] \
  && ok "ac1: verdicts are data — the tool exits 0 even with UNNOTICED present" \
  || no "ac1: tool exited $rc — an UNNOTICED probe must never read as tool failure"

# ── ac2: the probe set is deterministic at a fixed commit ──
# TWO comparisons on purpose. The full-set pair covers every probe LABEL (a mutant that
# taints only revert-hunk sites hid from the budgeted pair whenever the seeded sample
# happened to pick the two drop-line probes — found by this spec's own corpus, a
# sometimes-survivor whose flake tracked the fixture commit's timestamp); the budgeted
# pair covers the SAMPLER itself.
f1="$(run_wm "$FX" RALPH_WORK_MUTANTS=10 | grep -E "NOTICED|UNNOTICED|HUNG")"
f2="$(run_wm "$FX" RALPH_WORK_MUTANTS=10 | grep -E "NOTICED|UNNOTICED|HUNG")"
if [ -n "$f1" ] && [ "$f1" = "$f2" ]; then
  ok "ac2: two full runs at one commit printed identical probe lines — labels are reproducible"
else
  no "ac2: full probe sets differ between runs — a ledger row nobody can reproduce"
fi
p1="$(run_wm "$FX" RALPH_WORK_MUTANTS=2 | grep -E "NOTICED|UNNOTICED|HUNG")"
p2="$(run_wm "$FX" RALPH_WORK_MUTANTS=2 | grep -E "NOTICED|UNNOTICED|HUNG")"
if [ -n "$p1" ] && [ "$p1" = "$p2" ]; then
  ok "ac2: two budgeted runs chose the identical sample — the sampler is seeded, not lucky"
else
  no "ac2: budgeted probe sets differ between runs — the sample is not seeded by the commit"
fi

# ── ac3: the real tree is byte-identical after ──
_after="$(tree_hash "$FX")"
[ "$_before" = "$_after" ] \
  && ok "ac3: the fixture tree is byte-identical after all runs" \
  || no "ac3: the tool modified the real tree"

# ── ac4: emission seam — rows when SELFTEST_EVID is set, not one byte when unset ──
EV="$(mktemp -d)"; _FX="$_FX $EV"
( cd "$FX" && SELFTEST_EVID="$EV" RALPH_WORK_MUTANTS=10 bash "$WM" specs/20990101a-fx/tasks/T01-t >/dev/null 2>&1 )
# The kind check reads a PROBE row (one carrying "operator"), never the run_complete
# marker — the marker is a separate printf and stays marked even when the rows lose the
# field. Found by this spec's own first selftest: rows-without-kind.sh SURVIVED until
# this grep was scoped (same lesson as 20260831u's headerless-accepted, one spec later).
if [ -s "$EV/worksens-20990101a-fx.jsonl" ] \
   && grep '"operator"' "$EV/worksens-20990101a-fx.jsonl" | grep -q '"kind": *"work"' \
   && grep -q '"run_complete"' "$EV/worksens-20990101a-fx.jsonl"; then
  ok "ac4: rows + run_complete landed in worksens-<slug>.jsonl, probe rows marked kind=work"
else
  no "ac4: emission seam broken — no rows, no marker, or probe rows unmarked kind in $EV"
fi
ls "$FX"/.evidence/worksens-* >/dev/null 2>&1 \
  && no "ac4: rows written with SELFTEST_EVID unset — an unconfigured channel is not a degraded mode" \
  || ok "ac4: with SELFTEST_EVID unset, not one byte was written"

bash -n "$WM" && ok "ac5: work-mutate.sh passes bash -n" || no "ac5: work-mutate.sh fails bash -n"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T01 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
