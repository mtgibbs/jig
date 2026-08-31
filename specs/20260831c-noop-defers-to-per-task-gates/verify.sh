#!/usr/bin/env bash
# Gate for 20260831c-noop-defers-to-per-task-gates. Single-task spec: one gate, no pend.
# Fixtures run the REAL ralph-build.sh with stub executors; the refusal message
# "changed nothing" is the probe, and ac3's legacy fixture is its positive control.
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

# mk_fx <per_task 0|1> <task_gate_body> — one-task fixture repo, physical path.
mk_fx() {
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs/fx" "$d/.evidence"
  echo '# fx spec' > "$d/specs/fx/spec.md"
  echo 'T1: do the thing' > "$d/specs/fx/tasks.txt"
  echo placeholder > "$d/.evidence/keep.txt"
  if [ "$1" = "1" ]; then
    mkdir -p "$d/specs/fx/tasks/T01-thing"
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "$d/specs/fx/tasks/T01-thing/verify.sh"
    # convergence gate: same assertion, end-state only
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "$d/specs/fx/verify.sh"
  else
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "$d/specs/fx/verify.sh"
  fi
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

NOOP_MSG='changed nothing'

# ── ac1: per-task + empty attempt → no refusal message, gate feedback instead ──
GATE_RED='echo "  FAIL  fx: the thing is missing" >&2; exit 1'
FX1="$(mk_fx 1 "$GATE_RED")"
S_EMPTY="$(mk_stub ':')"
out1="$(run_fx "$FX1" "$S_EMPTY")"; rc1=$?
printf '%s' "$out1" | grep -q "$NOOP_MSG" \
  && no "ac1: per-task empty attempt still hit the no-op refusal" \
  || ok "ac1: no no-op refusal for the per-task empty attempt"
# The gate's own lines go to the evidence log and the retry feedback, not loop stdout;
# the loop's stdout marks a gate-judged failure with "verify failed" — that is the probe.
printf '%s' "$out1" | grep -q 'verify failed' \
  && ok "ac1: the empty attempt was judged by its GATE (loop reports 'verify failed', not a refusal)" \
  || no "ac1: no 'verify failed' in loop output — the attempt was not judged by the gate (rc=$rc1)"
[ "$rc1" -eq 2 ] \
  && ok "ac1: the empty per-task attempt still fails the run (exit 2)" \
  || no "ac1: expected exit 2, got $rc1"

# ── ac2: per-task task whose only change is under .evidence/ passes ──
GATE_EVID='grep -q bullet "$(git rev-parse --show-toplevel)/.evidence/note.md" 2>/dev/null || { echo "  FAIL  fx: no bullet" >&2; exit 1; }; echo "  PASS  fx: bullet present"; exit 0'
FX2="$(mk_fx 1 "$GATE_EVID")"
S_EVID="$(mk_stub 'echo bullet >> "$ROOT/.evidence/note.md"')"
out2="$(run_fx "$FX2" "$S_EVID")"; rc2=$?
[ "$rc2" -eq 0 ] \
  && ok "ac2: an .evidence-only deliverable passes under a per-task gate (the #91 blind spot is closed here)" \
  || no "ac2: .evidence-only attempt did not pass (rc=$rc2) — $(printf '%s' "$out2" | grep -E 'FAIL|✗' | head -2 | tr '\n' ' ')"
printf '%s' "$out2" | grep -q "$NOOP_MSG" \
  && no "ac2: the blind-spot refusal fired on the deliverable" \
  || ok "ac2: no no-op refusal on the .evidence deliverable"

# ── ac3: monolithic legacy path unchanged — refusal fires (positive control) ──
# The fixture gate is RED: since 20260831h a green single-task gate skips before the
# executor is ever dispatched, and this control needs a dispatched empty attempt.
FX3="$(mk_fx 0 'echo "  FAIL  fx: nothing built" >&2; exit 1')"
out3="$(run_fx "$FX3" "$S_EMPTY")"; rc3=$?
printf '%s' "$out3" | grep -q "$NOOP_MSG" \
  && ok "ac3: monolithic empty attempt still refused (positive control for the ac1/ac2 probe)" \
  || no "ac3: legacy no-op refusal did not fire (rc=$rc3)"

# ── ac4 ──
bash -n "$RB" \
  && ok "ac4: ralph-build.sh passes bash -n" \
  || no "ac4: bash -n fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
