#!/usr/bin/env bash
# Gate for T02-corpus-required (20260831u-mutants-always-run).
#
# The refusal policy, both sides shown: a corpus-era spec (date prefix >= 20260831u)
# without a mutant corpus is refused UP FRONT, the monolithic-refusal way; a legacy spec
# proceeds with exactly one loud warn line — stated, never silently skipped, and never
# backfilled. A corpus that is still the scaffold template (sentinel TARGET) counts as
# unauthored: refusing it late, at first green, would waste the whole build.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
NS="$R/scripts/new-spec.sh"
RB="$R/scripts/ralph-build.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

# mk_fx <id> <corpus-mode: none|template|real> — one-task fixture spec, green stub gate.
mk_fx(){
  local d td
  d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs"
  bash "$NS" --root "$d" --id "$1" fx greet >/dev/null 2>&1 || return 1
  td="$(ls -d "$d"/specs/"$1"-fx/tasks/T01-* 2>/dev/null | head -1)" || return 1
  cat > "$td/verify.sh" <<'GATE'
#!/usr/bin/env bash
if grep -q hello greeting.txt 2>/dev/null; then echo "  PASS  fx1"; exit 0; fi
echo "  FAIL  fx1: greeting.txt must say hello" >&2; exit 1
GATE
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/specs/$1-fx/verify.sh"
  case "$2" in
    none)     rm -rf "$td/mutants" ;;
    template) : ;;   # whatever the scaffolder emitted stays — the unreplaced-stub case
    real)
      rm -rf "$td/mutants"; mkdir -p "$td/mutants"
      printf '# MUTANT: fx1\n# TARGET: greeting.txt\n# WHY: wrong deliverable\ngoodbye\n' \
        > "$td/mutants/greeting.txt" ;;
  esac
  git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null
  printf '%s' "$d"
}

STUB="$(mktemp)"; _FX="$_FX $STUB"
printf '#!/usr/bin/env bash\n: "${ROOT:?}"\nprintf "hello world\\n" > "$ROOT/greeting.txt"\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' > "$STUB"

run_loop(){ # <root> <spec-rel>
  ( cd "$1" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN -u SELFTEST_EVID \
      RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
      RALPH_EXEC_CMD="bash $STUB" bash "$RB" "$2" 2>&1 )
}

# ── ac1: corpus-era spec, no corpus -> refused up front, nothing runs ──
FX1="$(mk_fx 20990101a none)" || no "ac1: fixture scaffold failed"
out1="$(run_loop "$FX1" specs/20990101a-fx)"; rc1=$?
[ "$rc1" -eq 3 ] \
  && ok "ac1: corpus-era spec without mutants/ is refused up front (rc=3, spec-needs-attention)" \
  || no "ac1: expected rc=3, got rc=$rc1 — a corpus-less new spec was allowed to run"
printf '%s' "$out1" | grep -q "mutants" \
  && ok "ac1: the refusal names the missing corpus" \
  || no "ac1: refusal does not mention mutants — the author cannot tell what is missing"
[ ! -f "$FX1/greeting.txt" ] \
  && ok "ac1: the executor never ran — the refusal is preflight, not mid-run" \
  || no "ac1: the executor RAN before the refusal — work was built against an unproven ruler"

# ── ac2: legacy spec, no corpus -> proceeds, warned exactly once ──
FX2="$(mk_fx 20250101a none)" || no "ac2: fixture scaffold failed"
out2="$(run_loop "$FX2" specs/20250101a-fx)"; rc2=$?
[ "$rc2" -eq 0 ] \
  && ok "ac2: a legacy spec without a corpus still runs (rc=0) — history is not backfilled" \
  || no "ac2: legacy spec refused (rc=$rc2) — the boundary is rewriting history's obligations"
_warns="$(printf '%s' "$out2" | grep -c "no mutant corpus")"
[ "$_warns" -eq 1 ] \
  && ok "ac2: the legacy run warned exactly once — loud, never silent, never spammed" \
  || no "ac2: expected exactly 1 'no mutant corpus' warn line, got $_warns"

# ── ac3: a corpus that is still the scaffold template is refused as unauthored ──
FX3="$(mk_fx 20990101b template)" || no "ac3: fixture scaffold failed"
if ls "$FX3"/specs/20990101b-fx/tasks/T01-*/mutants/* >/dev/null 2>&1; then
  out3="$(run_loop "$FX3" specs/20990101b-fx)"; rc3=$?
  [ "$rc3" -eq 3 ] \
    && ok "ac3: an unreplaced scaffold-template corpus is refused up front (rc=$rc3)" \
    || no "ac3: the scaffold template counted as an authored corpus (rc=$rc3) — a placeholder is not a poison pill"
  printf '%s' "$out3" | grep -qi "template" \
    && ok "ac3: the refusal says the corpus is still the template" \
    || no "ac3: refusal does not say 'template' — the author cannot tell authored-badly from not-authored"
else
  no "ac3: the scaffolder emitted no template corpus at all (T03 not built) — nothing to judge"
fi

# ── ac4: a real corpus on a corpus-era spec passes preflight and converges ──
FX4="$(mk_fx 20990101c real)" || no "ac4: fixture scaffold failed"
run_loop "$FX4" specs/20990101c-fx >/dev/null 2>&1; rc4=$?
[ "$rc4" -eq 0 ] \
  && ok "ac4: a corpus-era spec WITH a real corpus runs and converges (rc=0)" \
  || no "ac4: the policy refused a spec that satisfies it (rc=$rc4)"

bash -n "$RB" && ok "ac5: ralph-build.sh passes bash -n" || no "ac5: ralph-build.sh fails bash -n"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T02 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
