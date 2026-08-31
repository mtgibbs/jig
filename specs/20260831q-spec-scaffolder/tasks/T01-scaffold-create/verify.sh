#!/usr/bin/env bash
# Gate for T01-scaffold-create (20260831q). Runs the real scripts/new-spec.sh against
# mktemp fixture roots; ac6 then runs the REAL ralph-build.sh against a scaffolded spec
# to prove the emitted shape clears the loop's own validation.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
NS="$R/scripts/new-spec.sh"
RB="$R/scripts/ralph-build.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

[ -f "$NS" ] || { echo "  FAIL  ac0: scripts/new-spec.sh does not exist" >&2; echo; echo "VERIFY: failures above" >&2; exit 1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

mk_root() { # a bare consumer-repo root with an empty specs/ dir, physical path
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  mkdir -p "$d/specs"
  printf '%s' "$d"
}

# ── ac1: three task slugs scaffold the full per-task shape ──
FX1="$(mk_root)"
out1="$(bash "$NS" --root "$FX1" --id 20990101a widget-frobnicator alpha-thing beta-thing gamma-thing 2>&1)"; rc1=$?
D1="$FX1/specs/20990101a-widget-frobnicator"
[ "$rc1" -eq 0 ] && [ -d "$D1" ] \
  && ok "ac1: scaffold created the spec dir (rc=0)" \
  || no "ac1: scaffold failed (rc=$rc1) — $(printf '%s' "$out1" | head -2 | tr '\n' ' ')"
[ -f "$D1/spec.md" ] && [ -f "$D1/tasks.txt" ] && [ -f "$D1/verify.sh" ] && [ -d "$D1/evidence" ] \
  && ok "ac1: spec.md, tasks.txt, verify.sh, evidence/ all present" \
  || no "ac1: core files missing from the scaffold"
n1="$(grep -c '^T[0-9]' "$D1/tasks.txt" 2>/dev/null)"
[ "$n1" = "3" ] \
  && ok "ac1: tasks.txt carries 3 T-lines" \
  || no "ac1: expected 3 T-lines in tasks.txt, got ${n1:-none}"
gates_ok=1
for g in "$D1/tasks/T01-alpha-thing/verify.sh" "$D1/tasks/T02-beta-thing/verify.sh" "$D1/tasks/T03-gamma-thing/verify.sh"; do
  [ -x "$g" ] || { gates_ok=0; no "ac1: missing or non-executable gate: ${g#"$FX1/"}"; }
done
[ "$gates_ok" -eq 1 ] && ok "ac1: every task has an executable tasks/T<NN>-<slug>/verify.sh"
grep -q '20990101a' "$D1/spec.md" 2>/dev/null \
  && ok "ac1: the spec.md skeleton names its own id" \
  || no "ac1: spec.md skeleton does not name the spec id"

# ── ac2: stub gates are RED by construction — never green with no work done ──
bash "$D1/tasks/T01-alpha-thing/verify.sh" >/dev/null 2>&1; rcg=$?
[ "$rcg" -ne 0 ] \
  && ok "ac2: a fresh stub gate fails (red until authored)" \
  || no "ac2: the stub gate passes with no work done — green by construction"
bash "$D1/verify.sh" >/dev/null 2>&1; rcs=$?
[ "$rcs" -ne 0 ] \
  && ok "ac2: the convergence gate propagates the stub failures" \
  || no "ac2: the convergence gate is green over red stubs"

# ── ac3: a single task still gets tasks/ — the shape does not change with count ──
FX3="$(mk_root)"
bash "$NS" --root "$FX3" --id 20990101a lone-fix only-task >/dev/null 2>&1; rc3=$?
[ "$rc3" -eq 0 ] && [ -x "$FX3/specs/20990101a-lone-fix/tasks/T01-only-task/verify.sh" ] \
  && ok "ac3: a single-task spec is scaffolded WITH tasks/T01-only-task/" \
  || no "ac3: the single-task scaffold lacks the per-task layout (rc=$rc3)"

# ── ac4: refusals — zero tasks, existing dir, bad slug; refusal writes nothing ──
FX4="$(mk_root)"
bash "$NS" --root "$FX4" --id 20990101a no-tasks-here >/dev/null 2>&1 \
  && no "ac4: zero task slugs was accepted" \
  || ok "ac4: zero task slugs refused"
[ ! -d "$FX4/specs/20990101a-no-tasks-here" ] \
  && ok "ac4: the refused scaffold wrote nothing" \
  || no "ac4: the refusal left a partial spec dir behind"
bash "$NS" --root "$FX1" --id 20990101a widget-frobnicator other-task >/dev/null 2>&1 \
  && no "ac4: an existing spec dir was overwritten" \
  || ok "ac4: an existing spec dir is refused"
bash "$NS" --root "$FX4" --id 20990101b 'Bad Slug!' task-one >/dev/null 2>&1 \
  && no "ac4: a bad slug was accepted" \
  || ok "ac4: a bad slug is refused"

# ── ac5: auto id allocation walks the alphabet within a date ──
FX5="$(mk_root)"
bash "$NS" --root "$FX5" first-spec a-task >/dev/null 2>&1
bash "$NS" --root "$FX5" second-spec b-task >/dev/null 2>&1
d5a="$(ls -d "$FX5"/specs/*-first-spec 2>/dev/null | head -1)"
d5b="$(ls -d "$FX5"/specs/*-second-spec 2>/dev/null | head -1)"
case "$d5a" in
  */specs/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]a-first-spec) ok "ac5: the first auto id ends in 'a'";;
  *) no "ac5: first auto id wrong: ${d5a:-none}";;
esac
case "$d5b" in
  */specs/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]b-second-spec) ok "ac5: the second auto id ends in 'b'";;
  *) no "ac5: second auto id wrong: ${d5b:-none}";;
esac

# ── ac6: the REAL loop accepts the scaffolded shape — past validation (never exit 3),
# then judged by the red stub gate ('verify failed', exit 2) ──
FX6="$(mktemp -d)"; FX6="$(cd "$FX6" && pwd -P)"; _FX="$_FX $FX6"
git -C "$FX6" init -q
git -C "$FX6" config user.email fx@fx.invalid
git -C "$FX6" config user.name fx
mkdir -p "$FX6/specs" "$FX6/.evidence"
echo keep > "$FX6/.evidence/keep.txt"
bash "$NS" --root "$FX6" --id 20990101a loop-shape one-task >/dev/null 2>&1 \
  || no "ac6: scaffold into the git fixture failed"
git -C "$FX6" add -A && git -C "$FX6" commit -qm fx >/dev/null
STUB="$(mktemp)"; _FX="$_FX $STUB"
printf '#!/usr/bin/env bash\n: "${ROOT:?}"\necho attempt >> "$ROOT/attempt.txt"\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' > "$STUB"
out6="$( cd "$FX6" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN \
    RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
    RALPH_EXEC_CMD="bash $STUB" bash "$RB" specs/20990101a-loop-shape 2>&1 )"; rc6=$?
[ "$rc6" -ne 3 ] \
  && ok "ac6: the loop's up-front validation accepts the scaffolded shape (rc=$rc6, not 3)" \
  || no "ac6: the loop REFUSED the scaffolded shape (exit 3) — $(printf '%s' "$out6" | head -2 | tr '\n' ' ')"
[ "$rc6" -eq 2 ] && printf '%s' "$out6" | grep -q 'verify failed' \
  && ok "ac6: the attempt was judged by the red stub gate (rc=2, 'verify failed')" \
  || no "ac6: expected the stub gate's verdict (rc=2, 'verify failed'), got rc=$rc6"

# ── ac7: the scaffolder parses ──
bash -n "$NS" \
  && ok "ac7: new-spec.sh passes bash -n" \
  || no "ac7: bash -n fails on new-spec.sh"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
