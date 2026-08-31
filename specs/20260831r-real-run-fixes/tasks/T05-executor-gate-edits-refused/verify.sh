#!/usr/bin/env bash
# Gate for T05-executor-gate-edits-refused (20260831r-real-run-fixes).
# An attempt that edits anything under the spec dir is rejected wholesale before
# the gate runs — the executor does not get to change the ruler. Proven against
# the REAL ralph-build.sh with an executor stub that rewrites its own task gate.
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

mk_fx(){ # git fixture with one scaffolded task; task gate: passes iff work.txt exists
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs"
  bash "$NS" --root "$d" --id 20990101a fx one >/dev/null 2>&1 || return 1
  printf '#!/usr/bin/env bash\n[ -f work.txt ]\n' > "$d/specs/20990101a-fx/tasks/T01-one/verify.sh"
  git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null
  printf '%s' "$d"
}

run_loop(){ # <root> <stub>
  ( cd "$1" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN \
      RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
      RALPH_EXEC_CMD="bash $2" bash "$RB" specs/20990101a-fx 2>&1 )
}

# The hacking stub: rewrites its own task gate to exit 0 and does nothing else.
HACK="$(mktemp)"; _FX="$_FX $HACK"
printf '#!/usr/bin/env bash\n: "${ROOT:?}"\nprintf "#!/usr/bin/env bash\\nexit 0\\n" > "$ROOT/specs/20990101a-fx/tasks/T01-one/verify.sh"\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' > "$HACK"

# The honest stub: does the work the gate asks for, touches no spec files.
WORK="$(mktemp)"; _FX="$_FX $WORK"
printf '#!/usr/bin/env bash\n: "${ROOT:?}"\necho done > "$ROOT/work.txt"\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' > "$WORK"

# ── ac1: the gate-rewriting attempt is rejected, run does not go green ──
FX1="$(mk_fx)" || no "ac1: fixture scaffold failed"
out1="$(run_loop "$FX1" "$HACK")"; rc1=$?
[ "$rc1" -ne 0 ] \
  && ok "ac1: a spec-dir-editing attempt cannot take the run green (rc=$rc1)" \
  || no "ac1: the executor rewrote its own gate to exit 0 and the loop exited 0 — the hack landed"
printf '%s' "$out1" | grep -qi 'spec' \
  && printf '%s' "$out1" | grep -qiE 'reject|refus' \
  && ok "ac1: the refusal is explicit in the output" \
  || no "ac1: no explicit spec-edit refusal in the output"

# ── ac2: the edited gate is restored before the next step ──
grep -q 'exit 0' "$FX1/specs/20990101a-fx/tasks/T01-one/verify.sh" \
  && no "ac2: the executor's gate rewrite survived in the tree" \
  || ok "ac2: the gate file was restored to its committed content"

# ── ac3: the refusal names the touched path ──
printf '%s' "$out1" | grep -q 'tasks/T01-one/verify.sh' \
  && ok "ac3: the refusal names the edited gate file" \
  || no "ac3: the refusal does not name the edited file"

# ── ac4: an honest attempt is untouched by the new guard ──
FX2="$(mk_fx)" || no "ac4: fixture scaffold failed"
out2="$(run_loop "$FX2" "$WORK")"; rc4=$?
[ "$rc4" -eq 0 ] \
  && ok "ac4: an attempt touching only product files still converges (rc=0)" \
  || no "ac4: honest attempt broke under the guard (rc=$rc4): $(printf '%s' "$out2" | tail -2 | tr '\n' ' ')"

bash -n "$RB" && ok "ac5: ralph-build.sh passes bash -n" || no "ac5: ralph-build.sh fails bash -n"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T05 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
