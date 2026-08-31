#!/usr/bin/env bash
# Gate for 20260831g-portable-satisfied-bound. Single-task spec: one gate, no pend.
# On macOS (no timeout(1)) ac1/ac2 exercise the perl fallback through the REAL loop;
# on Linux they exercise the timeout path — both machines get a meaningful run, and
# ac3 pins the call site statically so neither platform can regress the other.
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

# mk_fx <task-gate-body> — one-task per-task fixture; convergence gate always green.
mk_fx() {
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs/fx/tasks/T01-thing" "$d/.evidence"
  echo '# fx spec' > "$d/specs/fx/spec.md"
  echo 'T1: the thing' > "$d/specs/fx/tasks.txt"
  echo keep > "$d/.evidence/keep.txt"
  printf '#!/usr/bin/env bash\n%s\n' "$1" > "$d/specs/fx/tasks/T01-thing/verify.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/specs/fx/verify.sh"
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

# ── ac1: a green gate means SKIP — the executor never runs ──
FX1="$(mk_fx 'echo "  PASS  fx: satisfied"; exit 0')"
M1="$FX1.ran"; _FX="$_FX $M1"
S1="$(mk_stub 'touch "$MARK"')"
out1="$(run_fx "$FX1" "$S1" MARK="$M1")"; rc1=$?
printf '%s' "$out1" | grep -q 'skipped (gate already passed)' \
  && ok "ac1: the satisfied task was skipped" \
  || no "ac1: no skip — the satisfied task was dispatched (rc=$rc1)"
[ -f "$M1" ] \
  && no "ac1: the executor ran despite a green gate" \
  || ok "ac1: the executor was never invoked"
[ "$rc1" -eq 0 ] \
  && ok "ac1: the all-skipped green run exits 0" \
  || no "ac1: expected exit 0, got $rc1"

# ── ac2: a hanging gate is bounded — answered false, the task runs ──
# The fixture gate hangs until the deliverable exists, so only the PRE-dispatch
# satisfied check ever sees the hang; post-attempt verify passes instantly.
FX2="$(mk_fx 'test -f "$(git rev-parse --show-toplevel)/ok.txt" && { echo "  PASS  fx: built"; exit 0; }; sleep 300')"
S2="$(mk_stub 'echo done > "$ROOT/ok.txt"')"
out2="$(run_fx "$FX2" "$S2" RALPH_SATISFIED_TIMEOUT=3)"; rc2=$?
printf '%s' "$out2" | grep -q 'did not finish within 3s' \
  && ok "ac2: the hanging gate was bounded (did-not-finish within 3s reported)" \
  || no "ac2: no bound report — the hang was misread or unbounded (rc=$rc2)"
[ "$rc2" -eq 0 ] \
  && ok "ac2: the task ran and the run completed (fail-closed skip, then real work)" \
  || no "ac2: expected exit 0 after the bounded skip check, got $rc2"

# ── ac3: the call site is the portable bound, statically ──
grep -q 'bound "\$_bound" bash "\$g"' "$RB" \
  && ok "ac3: _task_satisfied bounds the gate with bound()" \
  || no "ac3: _task_satisfied does not call bound()"
grep -q 'timeout "\$_bound"' "$RB" \
  && no "ac3: a bare timeout(1) call survives in ralph-build.sh" \
  || ok "ac3: no bare timeout(1) call remains"
grep -q 'bound\.sh' "$RB" \
  && ok "ac3: ralph-build.sh sources bound.sh" \
  || no "ac3: bound.sh is not sourced"

# ── ac4 ──
bash -n "$RB" \
  && ok "ac4: ralph-build.sh passes bash -n" \
  || no "ac4: bash -n fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
