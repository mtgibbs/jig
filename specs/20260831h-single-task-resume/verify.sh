#!/usr/bin/env bash
# Gate for 20260831h-single-task-resume. Single-task spec: one gate, no pend.
# Fixtures run the REAL ralph-build.sh with stub executors; markers live OUTSIDE the
# fixture repos (the loop's failure path runs `git clean -fd`).
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../.." && pwd -P)"
RB="$R/scripts/ralph-build.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

# mk_single <spec-gate-body> [seed] — a single-task spec with NO tasks/ dir (the
# 20260828i exemption). seed=done pre-commits the deliverable (a finished run to resume).
mk_single() {
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs/fx" "$d/.evidence"
  echo '# fx spec' > "$d/specs/fx/spec.md"
  echo 'T1: write done into ok.txt' > "$d/specs/fx/tasks.txt"
  echo keep > "$d/.evidence/keep.txt"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$d/specs/fx/verify.sh"
  [ "${2:-}" = done ] && echo done > "$d/ok.txt"
  git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null
  printf '%s' "$d"
}

mk_stub() { # <body> -> path
  local s; s="$(mktemp)"; _FX="$_FX $s"
  printf '#!/usr/bin/env bash\n: "${ROOT:?}"\n%s\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' "$1" > "$s"
  printf '%s' "$s"
}

run_fx() { # <dir> <stub> [env...]
  local d="$1" s="$2"; shift 2
  ( cd "$d" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN -u RALPH_ALLOW_MONOLITHIC \
      "$@" RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
      RALPH_EXEC_CMD="bash $s" bash "$RB" specs/fx 2>&1 )
}

GATE_OK='grep -q done "$(git rev-parse --show-toplevel)/ok.txt" 2>/dev/null || { echo "  FAIL  fx: ok.txt missing" >&2; exit 1; }; echo "  PASS  fx: ok.txt present"; exit 0'

# ── ac1: finished single-task spec resumes as a skip ──
FX1="$(mk_single "$GATE_OK" done)"
M1="$FX1.ran"; _FX="$_FX $M1"
S_MARK="$(mk_stub 'touch "$MARK"')"
out1="$(run_fx "$FX1" "$S_MARK" MARK="$M1")"; rc1=$?
printf '%s' "$out1" | grep -q 'skipped (gate already passed)' \
  && ok "ac1: the finished task was skipped on resume" \
  || no "ac1: no skip — the finished single-task spec was re-dispatched (rc=$rc1)"
[ -f "$M1" ] \
  && no "ac1: the executor ran on a finished spec" \
  || ok "ac1: the executor was never invoked"
printf '%s' "$out1" | grep -q 'changed nothing' \
  && no "ac1: the resume still died as a no-op (issue #30's exact signature)" \
  || ok "ac1: no no-op death"
[ "$rc1" -eq 0 ] \
  && ok "ac1: the resumed run exits 0" \
  || no "ac1: expected exit 0, got $rc1"

# ── ac2: unfinished single-task spec still dispatches (no false skip) ──
FX2="$(mk_single "$GATE_OK")"
S_WORK="$(mk_stub 'echo done > "$ROOT/ok.txt"')"
out2="$(run_fx "$FX2" "$S_WORK")"; rc2=$?
printf '%s' "$out2" | grep -q 'skipped (gate already passed)' \
  && no "ac2: an unfinished spec was falsely skipped" \
  || ok "ac2: no false skip on an unfinished spec"
[ "$rc2" -eq 0 ] \
  && ok "ac2: the executor was dispatched and the run completed (rc=0)" \
  || no "ac2: the unfinished run did not complete (rc=$rc2)"

# ── ac3: lenient-only green must not read as satisfied ──
# A legacy pend-shaped gate: green normally, red under STRICT — a skip here would let
# a resume bless unbuilt work.
GATE_PEND='if [ "${STRICT:-0}" = 1 ]; then echo "  FAIL  fx: pend promoted" >&2; exit 1; fi; echo "  PASS  fx: lenient"; exit 0'
FX3="$(mk_single "$GATE_PEND")"
M3="$FX3.ran"; _FX="$_FX $M3"
out3="$(run_fx "$FX3" "$S_MARK" MARK="$M3")"; rc3=$?
printf '%s' "$out3" | grep -q 'skipped (gate already passed)' \
  && no "ac3: a lenient-only green was read as satisfied — STRICT is not being applied" \
  || ok "ac3: the lenient-only gate did not skip (STRICT applied to the satisfied question)"
[ -f "$M3" ] \
  && ok "ac3: the task was dispatched instead" \
  || no "ac3: the task was neither skipped nor dispatched (rc=$rc3)"

# ── ac4: multi-task monolithic never reaches the skip question at all — it is refused
# up front (20260831p removed the legacy allow-env this check used to ride) ──
FX4="$(mk_single 'exit 0')"
printf 'T1: thing one\nT2: thing two\n' > "$FX4/specs/fx/tasks.txt"
git -C "$FX4" add -A && git -C "$FX4" commit -qm two >/dev/null
M4="$FX4.ran"; _FX="$_FX $M4"
out4="$(run_fx "$FX4" "$S_MARK" MARK="$M4" RALPH_ALLOW_MONOLITHIC=1)"; rc4=$?
printf '%s' "$out4" | grep -q 'skipped (gate already passed)' \
  && no "ac4: a multi-task monolithic spec skipped — the unanswerable rule broke" \
  || ok "ac4: multi-task monolithic never skips (green whole-spec gate says the SPEC is done, not task N)"
[ "$rc4" -eq 3 ] && [ ! -f "$M4" ] \
  && ok "ac4: it is refused before dispatch (exit 3, no executor)" \
  || no "ac4: expected up-front refusal (exit 3, no marker), got rc=$rc4"

# ── ac5 ──
bash -n "$RB" \
  && ok "ac5: ralph-build.sh passes bash -n" \
  || no "ac5: bash -n fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
