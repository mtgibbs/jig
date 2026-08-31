#!/usr/bin/env bash
# Gate for 20260831f-all-skipped-strict-stop. Single-task spec: one gate, no pend.
# The fixture's task gate is green on the committed tree (task skips); its convergence
# gate always fails (STRICT endgame stops). The stub executor writes a marker OUTSIDE
# the repo — it must never run.
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

d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
git -C "$d" init -q
git -C "$d" config user.email fx@fx.invalid
git -C "$d" config user.name fx
mkdir -p "$d/specs/fx/tasks/T01-thing" "$d/.evidence"
echo '# fx spec' > "$d/specs/fx/spec.md"
echo 'T1: already done' > "$d/specs/fx/tasks.txt"
echo keep > "$d/.evidence/keep.txt"
printf '#!/usr/bin/env bash\necho "  PASS  fx: satisfied"; exit 0\n' > "$d/specs/fx/tasks/T01-thing/verify.sh"
printf '#!/usr/bin/env bash\necho "  FAIL  fx-conv: the integration was never built" >&2; exit 1\n' > "$d/specs/fx/verify.sh"
git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null

MARK="$d.ran"; _FX="$_FX $MARK"
s="$(mktemp)"; _FX="$_FX $s"
printf '#!/usr/bin/env bash\ntouch "$MARK"\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' > "$s"

out="$( cd "$d" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN -u RALPH_ALLOW_MONOLITHIC \
    MARK="$MARK" RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
    RALPH_EXEC_CMD="bash $s" bash "$RB" specs/fx 2>&1 )"; rc=$?

# ── ac4 first: the control — this run really was the all-skipped path ──
printf '%s' "$out" | grep -q 'skipped (gate already passed)' \
  && ok "ac4: control — the task was skipped (all-skipped path exercised)" \
  || no "ac4: control — the task did not skip; the fixture is not testing the crash path"
[ -f "$MARK" ] \
  && no "ac4: control — the executor ran; the task was not skipped" \
  || ok "ac4: control — the executor was never invoked"

# ── ac1: exit 2, no crash ──
printf '%s' "$out" | grep -q 'unbound variable' \
  && no "ac1: the loop still dies on an unbound variable" \
  || ok "ac1: no unbound-variable crash"
[ "$rc" -eq 2 ] \
  && ok "ac1: the STRICT stop exits 2 (stop-needs-human), not a crash code" \
  || no "ac1: expected exit 2, got $rc"

# ── ac2: the failing assertions reached the human ──
printf '%s' "$out" | grep -q 'final STRICT gate found unbuilt work' \
  && ok "ac2: the STRICT stop banner printed" \
  || no "ac2: no STRICT stop banner in output"
printf '%s' "$out" | grep -q 'fx-conv: the integration was never built' \
  && ok "ac2: the convergence gate's failing assertion printed" \
  || no "ac2: the failing assertion never reached the output"

# ── ac3: the status file is stamped terminal ──
_st="$(find "$d/.evidence/status" -name '*.json' 2>/dev/null | head -1)"
if [ -z "$_st" ]; then
  no "ac3: no status file was written at all"
elif grep -q '"phase":"stopped"' "$_st"; then
  ok "ac3: the status file is stamped terminal (phase stopped)"
else
  no "ac3: the status file froze non-terminal — $(grep -o '"phase":"[^"]*"' "$_st" | head -1)"
fi

# ── ac5 ──
bash -n "$RB" \
  && ok "ac5: ralph-build.sh passes bash -n" \
  || no "ac5: bash -n fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
