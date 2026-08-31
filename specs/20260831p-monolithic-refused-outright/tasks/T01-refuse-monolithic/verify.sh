#!/usr/bin/env bash
# T01 gate — the loop refuses monolithic multi-task specs unconditionally, and the
# dead no-op guard is deleted. Fixtures run the REAL ralph-build.sh (20260831c idiom).
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
RB="$R/scripts/ralph-build.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

mk_repo() {
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  printf '.evidence/runs/\n' > "$d/.gitignore"
  printf '%s' "$d"
}

mk_stub() { # <body> -> path
  local s; s="$(mktemp)"; _FX="$_FX $s"
  printf '#!/usr/bin/env bash\n: "${ROOT:?}"\n%s\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' "$1" > "$s"
  printf '%s' "$s"
}

run_fx() { # <dir> <stub> [env...]
  local d="$1" s="$2"; shift 2
  ( cd "$d" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN \
      "$@" RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
      RALPH_EXEC_CMD="bash $s" bash "$RB" specs/fx 2>&1 )
}

# ── ac1: multi-task monolithic → exit 3, even with the old hatch env set ──
FX1="$(mk_repo)"
mkdir -p "$FX1/specs/fx"
echo '# fx' > "$FX1/specs/fx/spec.md"
printf 'T1: one\nT2: two\n' > "$FX1/specs/fx/tasks.txt"
printf '#!/usr/bin/env bash\necho "  PASS  fx"\nexit 0\n' > "$FX1/specs/fx/verify.sh"
git -C "$FX1" add -A && git -C "$FX1" commit -qm fx >/dev/null
M1="$(mktemp)"; rm -f "$M1"; _FX="$_FX $M1"
S_MARK="$(mk_stub 'touch "$MARK"')"
out1="$(run_fx "$FX1" "$S_MARK" MARK="$M1" RALPH_ALLOW_MONOLITHIC=1)"; rc1=$?
[ "$rc1" -eq 3 ] \
  && ok "ac1: multi-task monolithic refused with exit 3 DESPITE RALPH_ALLOW_MONOLITHIC=1" \
  || no "ac1: expected exit 3 with the hatch set, got $rc1 — the hatch still opens"
[ ! -f "$M1" ] \
  && ok "ac1: no executor ran" \
  || no "ac1: the executor was dispatched before the refusal"
printf '%s' "$out1" | grep -qi 'per-task\|20260828i' \
  && ok "ac1: the refusal names the convention" \
  || no "ac1: refusal does not name per-task gates"

# ── ac2: a task whose deliverable lives under .evidence/ passes (the guard's blind spot, gone) ──
FX2="$(mk_repo)"
mkdir -p "$FX2/specs/fx/tasks/T01-readme"
echo '# fx' > "$FX2/specs/fx/spec.md"
echo 'T1: write the evidence corpus README' > "$FX2/specs/fx/tasks.txt"
GATE_EV='grep -q "the corpus" "$(git rev-parse --show-toplevel)/.evidence/README.md" 2>/dev/null || { echo "  FAIL  fx: .evidence/README.md missing or wrong" >&2; exit 1; }; echo "  PASS  fx: the evidence README exists"; exit 0'
printf '#!/usr/bin/env bash\n%s\n' "$GATE_EV" > "$FX2/specs/fx/tasks/T01-readme/verify.sh"
printf '#!/usr/bin/env bash\n%s\n' "$GATE_EV" > "$FX2/specs/fx/verify.sh"
git -C "$FX2" add -A && git -C "$FX2" commit -qm fx >/dev/null
S_EV="$(mk_stub 'mkdir -p "$ROOT/.evidence"; echo "the corpus" > "$ROOT/.evidence/README.md"')"
out2="$(run_fx "$FX2" "$S_EV")"; rc2=$?
[ "$rc2" -eq 0 ] \
  && ok "ac2: an .evidence-dwelling deliverable passes (rc=0)" \
  || no "ac2: refused (rc=$rc2) — $(printf '%s' "$out2" | grep -E 'changed nothing|FAIL|✗' | head -2 | tr '\n' ' ')"
git -C "$FX2" show --stat HEAD 2>/dev/null | grep -q '.evidence/README.md' \
  && ok "ac2: the deliverable is committed" \
  || no "ac2: .evidence/README.md not in the task commit"
printf '%s' "$out2" | grep -q 'changed nothing' \
  && no "ac2: the no-op guard fired on a task that did its work" \
  || ok "ac2: no 'changed nothing' refusal"

# ── ac3: the guard and the hatch are GONE from the loop, not disabled ──
grep -q 'changed nothing' "$RB" \
  && no "ac3: the no-op guard's text is still in ralph-build.sh" \
  || ok "ac3: the no-op guard is deleted"
grep -q 'ALLOW_MONOLITHIC' "$RB" \
  && no "ac3: ALLOW_MONOLITHIC is still consulted or mentioned in ralph-build.sh" \
  || ok "ac3: the hatch variable is gone from the loop"

# ── ac4: an empty attempt still fails — the task gate refuses it, not a silent pass ──
FX4="$(mk_repo)"
mkdir -p "$FX4/specs/fx/tasks/T01-thing"
echo '# fx' > "$FX4/specs/fx/spec.md"
echo 'T1: do the thing' > "$FX4/specs/fx/tasks.txt"
GATE_OK='grep -q done "$(git rev-parse --show-toplevel)/ok.txt" 2>/dev/null || { echo "  FAIL  fx: ok.txt missing" >&2; exit 1; }; echo "  PASS  fx: ok.txt"; exit 0'
printf '#!/usr/bin/env bash\n%s\n' "$GATE_OK" > "$FX4/specs/fx/tasks/T01-thing/verify.sh"
printf '#!/usr/bin/env bash\n%s\n' "$GATE_OK" > "$FX4/specs/fx/verify.sh"
git -C "$FX4" add -A && git -C "$FX4" commit -qm fx >/dev/null
S_NOOP="$(mk_stub ':')"
out4="$(run_fx "$FX4" "$S_NOOP")"; rc4=$?
[ "$rc4" -eq 2 ] \
  && ok "ac4: an empty attempt still fails the run (exit 2)" \
  || no "ac4: expected exit 2 for the empty attempt, got $rc4"
printf '%s' "$out4" | grep -q 'verify failed' \
  && ok "ac4: the gate is what refused it" \
  || no "ac4: no 'verify failed' — what refused the attempt?"

# ── ac5 ──
bash -n "$RB" \
  && ok "ac5: ralph-build.sh passes bash -n" \
  || no "ac5: bash -n fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
