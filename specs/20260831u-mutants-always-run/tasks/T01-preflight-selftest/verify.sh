#!/usr/bin/env bash
# Gate for T01-preflight-selftest (20260831u-mutants-always-run).
#
# The loop proves a task's gate can fail — for the right reason — at the moment that gate
# first goes green, BEFORE the commit its green would bless. Proven against the REAL
# ralph-build.sh on git fixtures whose specs carry real corpora: one fixture whose mutant
# the gate kills (the run converges, verdict visible), one whose mutant survives (the run
# refuses with a distinct exit, commits nothing, and says plainly that the GATE failed —
# never that the work did).
#
# Why first-green and not before attempt 1: gate-selftest measures a gate against BUILT
# work. Pristine, a red-first gate fails everything and every mutant "dies" vacuously —
# selftest before the build proves nothing (spec §14 v1.1 records the tuning).
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

# mk_fx <mutant-body> — git fixture: one-task spec whose gate checks greeting.txt says
# hello; the corpus holds ONE mutant replacing greeting.txt with <mutant-body>. A body the
# fixture gate rejects is a killer; one it accepts is a survivor. The task gate names its
# assertion id (fx1) in its FAIL line — kill = non-zero AND that id, per 20260828k.
mk_fx(){
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
if grep -q hello greeting.txt 2>/dev/null; then echo "  PASS  fx1"; exit 0; fi
echo "  FAIL  fx1: greeting.txt must say hello" >&2; exit 1
GATE
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/specs/20990101a-fx/verify.sh"
  rm -rf "$td/mutants"; mkdir -p "$td/mutants"
  { printf '# MUTANT: fx1\n# TARGET: greeting.txt\n# WHY: the plausible wrong deliverable\n'
    printf '%s\n' "$1"; } > "$td/mutants/greeting.txt"
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

# ── ac1: an all-killed corpus converges, with the verdict visible in the run output ──
FX1="$(mk_fx 'goodbye world')" || no "ac1: fixture scaffold failed"
out1="$(run_loop "$FX1" specs/20990101a-fx)"; rc1=$?
[ "$rc1" -eq 0 ] \
  && ok "ac1: gate green + corpus killed -> the run converges (rc=0)" \
  || no "ac1: all-killed corpus should converge, got rc=$rc1 — the loop never ran selftest, or refused a clean corpus"
printf '%s' "$out1" | grep -q "killed=1" \
  && ok "ac1: the selftest verdict (killed=1) is visible in the run output" \
  || no "ac1: no selftest verdict in the run output — the corpus did not run at gate-green"

# ── ac2: a SURVIVOR refuses the run with a distinct exit, and commits nothing ──
FX2="$(mk_fx 'hello sailor')" || no "ac2: fixture scaffold failed"
out2="$(run_loop "$FX2" specs/20990101a-fx)"; rc2=$?
[ "$rc2" -eq 6 ] \
  && ok "ac2: a surviving mutant refuses the run with the distinct exit (rc=6)" \
  || no "ac2: expected rc=6 on a survivor, got rc=$rc2 — a gate that cannot fail just blessed a commit"
if git -C "$FX2" log --oneline | grep -q "ralph("; then
  no "ac2: the task was COMMITTED despite the surviving mutant — the refusal came too late"
else
  ok "ac2: nothing was committed — the refusal landed before the commit the green would bless"
fi
printf '%s' "$out2" | grep -q "SURVIVOR" \
  && ok "ac2: the refusal names the surviving mutant's verdict" \
  || no "ac2: the survivor is not named in the output — undiagnosable refusal"

# ── ac3: the refusal blames the GATE, in words distinct from work failing a gate ──
printf '%s' "$out2" | grep -qi "gate failed its selftest" \
  && ok "ac3: the wording says the GATE failed its selftest, not the work" \
  || no "ac3: refusal wording missing 'gate failed its selftest' — an operator will read this as the executor's failure"

# ── ac4: the selftest rows land in the worked repo's .evidence/ by default ──
if ls "$FX2"/.evidence/selftest-*.jsonl >/dev/null 2>&1 || ls "$FX1"/.evidence/selftest-*.jsonl >/dev/null 2>&1; then
  ok "ac4: selftest rows landed in the worked repo's .evidence/ (SELFTEST_EVID defaulted)"
else
  no "ac4: no selftest-*.jsonl in the worked repo — the research rows are not being recorded"
fi

bash -n "$RB" && ok "ac5: ralph-build.sh passes bash -n" || no "ac5: ralph-build.sh fails bash -n"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T01 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
