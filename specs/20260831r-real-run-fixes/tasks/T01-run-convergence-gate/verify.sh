#!/usr/bin/env bash
# Gate for T01-run-convergence-gate (20260831r-real-run-fixes).
# The per-task path runs the spec-level convergence verify.sh at the final task —
# exactly once, only after the task gates are green — and the monolithic fallback
# is unchanged. Proven against the REAL ralph-build.sh on git fixtures.
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

mk_fx(){ # <ntasks> — git fixture with a scaffolded spec, task gates all exit 0,
         # spec verify.sh appends a marker line and exits $CONV_RC
  local d slugs i
  d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs"
  slugs=""; i=0
  while [ "$i" -lt "$1" ]; do i=$((i+1)); slugs="$slugs step$i"; done
  # shellcheck disable=SC2086
  bash "$NS" --root "$d" --id 20990101a fx $slugs >/dev/null 2>&1 || return 1
  for g in "$d"/specs/20990101a-fx/tasks/T*/verify.sh; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$g"
  done
  printf '#!/usr/bin/env bash\necho conv >> "$PWD/conv-ran.txt"\nexit %s\n' "${CONV_RC:-0}" \
    > "$d/specs/20990101a-fx/verify.sh"
  git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null
  printf '%s' "$d"
}

STUB="$(mktemp)"; _FX="$_FX $STUB"
printf '#!/usr/bin/env bash\n: "${ROOT:?}"\necho w >> "$ROOT/work.txt"\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' > "$STUB"

run_loop(){ # <root> <spec-rel>
  ( cd "$1" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN \
      RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
      RALPH_EXEC_CMD="bash $STUB" bash "$RB" "$2" 2>&1 )
}

# ── ac1: red convergence gate fails the run, and it actually ran ──
FX1="$(CONV_RC=1 mk_fx 1)" || no "ac1: fixture scaffold failed"
out1="$(run_loop "$FX1" specs/20990101a-fx)"; rc1=$?
[ -f "$FX1/conv-ran.txt" ] \
  && ok "ac1: the spec-level convergence gate RAN at the final task" \
  || no "ac1: the spec-level verify.sh never ran (per-task path skips convergence)"
[ "$rc1" -ne 0 ] \
  && ok "ac1: a red convergence gate fails the run (rc=$rc1)" \
  || no "ac1: convergence was red but the loop exited 0"

# ── ac2: green convergence converges ──
FX2="$(CONV_RC=0 mk_fx 1)" || no "ac2: fixture scaffold failed"
out2="$(run_loop "$FX2" specs/20990101a-fx)"; rc2=$?
[ "$rc2" -eq 0 ] && [ -f "$FX2/conv-ran.txt" ] \
  && ok "ac2: green task gates + green convergence exit 0" \
  || no "ac2: expected rc=0 with convergence run, got rc=$rc2 (ran: $([ -f "$FX2/conv-ran.txt" ] && echo yes || echo no))"

# ── ac3: convergence runs exactly once, at the final task only ──
FX3="$(CONV_RC=0 mk_fx 2)" || no "ac3: fixture scaffold failed"
run_loop "$FX3" specs/20990101a-fx >/dev/null; rc3=$?
n3=0; [ -f "$FX3/conv-ran.txt" ] && n3="$(grep -c conv "$FX3/conv-ran.txt")"
[ "$rc3" -eq 0 ] && [ "$n3" -eq 1 ] \
  && ok "ac3: two-task run converged with exactly one convergence run" \
  || no "ac3: expected rc=0 and 1 convergence run, got rc=$rc3 runs=$n3"

# ── ac4: the monolithic fallback still runs the spec verify (unchanged behavior) ──
FX4="$(mktemp -d)"; FX4="$(cd "$FX4" && pwd -P)"; _FX="$_FX $FX4"
git -C "$FX4" init -q; git -C "$FX4" config user.email fx@fx.invalid; git -C "$FX4" config user.name fx
mkdir -p "$FX4/specs/legacy"
printf 'T1: do the one thing\n' > "$FX4/specs/legacy/tasks.txt"
printf '# fx\n- **Tools:** none\n- **MCP:** none\n' > "$FX4/specs/legacy/spec.md"
printf '#!/usr/bin/env bash\necho conv >> "$PWD/conv-ran.txt"\nexit 0\n' > "$FX4/specs/legacy/verify.sh"
chmod +x "$FX4/specs/legacy/verify.sh"
git -C "$FX4" add -A && git -C "$FX4" commit -qm fx >/dev/null
run_loop "$FX4" specs/legacy >/dev/null; rc4=$?
[ "$rc4" -eq 0 ] && [ -f "$FX4/conv-ran.txt" ] \
  && ok "ac4: legacy no-tasks-dir path still judged by the spec verify (rc=0)" \
  || no "ac4: legacy path changed — rc=$rc4, verify ran: $([ -f "$FX4/conv-ran.txt" ] && echo yes || echo no)"

bash -n "$RB" && ok "ac5: ralph-build.sh passes bash -n" || no "ac5: ralph-build.sh fails bash -n"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T01 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
