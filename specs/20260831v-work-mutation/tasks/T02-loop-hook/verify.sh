#!/usr/bin/env bash
# Gate for T02-loop-hook (20260831v-work-mutation).
#
# The loop measures sensitivity at the moment trust is minted — after first green, after
# the corpus selftest, after the commit LANDS — and it can NEVER change a run. Proven on
# the REAL ralph-build.sh: the same fixture runs with the hook on and off, and exit code
# and commit history must be byte-identical; an UNNOTICED probe (the stub deliberately
# writes an inert file the gate ignores) stops nothing.
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

mk_fx(){ # one-task fixture spec, real killer corpus, gate checks marker.txt only
  local d td
  d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs"
  bash "$NS" --root "$d" --id 20990101a fx greet >/dev/null 2>&1 || return 1
  td="$(ls -d "$d"/specs/20990101a-fx/tasks/T01-* 2>/dev/null | head -1)" || return 1
  cat > "$td/verify.sh" <<'GATE'
#!/usr/bin/env bash
if grep -q MARKER-LINE marker.txt 2>/dev/null; then echo "  PASS  fx1"; exit 0; fi
echo "  FAIL  fx1: marker.txt must carry MARKER-LINE" >&2; exit 1
GATE
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/specs/20990101a-fx/verify.sh"
  rm -rf "$td/mutants"; mkdir -p "$td/mutants"
  { printf '# MUTANT: fx1\n# TARGET: marker.txt\n# WHY: wrong deliverable\n'
    printf 'not-the-marker\n'; } > "$td/mutants/marker.txt"
  git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null
  printf '%s' "$d"
}

# the stub writes the CHECKED marker and an inert file the gate ignores — the inert file
# is what guarantees at least one UNNOTICED probe, which is exactly what must not stop a run
STUB="$(mktemp)"; _FX="$_FX $STUB"
printf '#!/usr/bin/env bash\n: "${ROOT:?}"\nprintf "MARKER-LINE\\n" > "$ROOT/marker.txt"\nprintf "inert data\\n" > "$ROOT/inert.txt"\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' > "$STUB"

run_loop(){ # <root> [extra env...]
  local d="$1"; shift
  ( cd "$d" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN -u SELFTEST_EVID "$@" \
      RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
      RALPH_EXEC_CMD="bash $STUB" bash "$RB" specs/20990101a-fx 2>&1 )
}

# ── ac1: the run output carries exactly one work-sensitivity summary line ──
FX1="$(mk_fx)" || no "ac1: fixture scaffold failed"
out1="$(run_loop "$FX1")"; rc1=$?
n1="$(printf '%s' "$out1" | grep -c "work-sensitivity:")"
[ "$n1" -eq 1 ] \
  && ok "ac1: one work-sensitivity summary line per committed task" \
  || no "ac1: expected exactly 1 work-sensitivity line, got $n1 (rc=$rc1)"

# ── ac2: the hook is provably outcome-neutral ──
FX2="$(mk_fx)" || no "ac2: fixture scaffold failed"
out2="$(run_loop "$FX2" RALPH_WORK_MUTANTS=0)"; rc2=$?
[ "$rc1" -eq "$rc2" ] && [ "$rc1" -eq 0 ] \
  && ok "ac2: exit codes identical with the hook on ($rc1) and off ($rc2)" \
  || no "ac2: hook changed the run's outcome — on=$rc1 off=$rc2"
c1="$(git -C "$FX1" log --oneline | grep -c "ralph(")"
c2="$(git -C "$FX2" log --oneline | grep -c "ralph(")"
[ "$c1" -eq "$c2" ] && [ "$c1" -eq 1 ] \
  && ok "ac2: commit history identical with the hook on and off (1 task commit each)" \
  || no "ac2: commits differ — on=$c1 off=$c2"
printf '%s' "$out2" | grep -q "work-sensitivity:" \
  && no "ac2: RALPH_WORK_MUTANTS=0 still printed a sensitivity line — 0 must disable" \
  || ok "ac2: RALPH_WORK_MUTANTS=0 disables the hook entirely"

# ── ac3: UNNOTICED probes stop nothing ──
_sum="$(printf '%s' "$out1" | grep "work-sensitivity:" | head -1)"
_n="$(printf '%s' "$_sum" | sed -n 's/.*work-sensitivity: *\([0-9]*\)\/\([0-9]*\).*/\1/p')"
_m="$(printf '%s' "$_sum" | sed -n 's/.*work-sensitivity: *\([0-9]*\)\/\([0-9]*\).*/\2/p')"
if [ -n "$_n" ] && [ -n "$_m" ] && [ "$_n" -lt "$_m" ]; then
  [ "$rc1" -eq 0 ] \
    && ok "ac3: unnoticed probes present ($_n/$_m noticed) and the run still converged" \
    || no "ac3: unnoticed probes stopped the run (rc=$rc1) — telemetry became enforcement"
else
  no "ac3: could not parse an unnoticed-bearing summary from [$_sum] — the inert file produced no unnoticed probe"
fi

bash -n "$RB" && ok "ac4: ralph-build.sh passes bash -n" || no "ac4: ralph-build.sh fails bash -n"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T02 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
