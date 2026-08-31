#!/usr/bin/env bash
# Gate for 20260831d-task-scope-guard. Single-task spec: one gate, no pend.
# Fixtures run the REAL ralph-build.sh with stub executors (the 20260831c idiom).
# Markers and prompt copies live OUTSIDE the fixture repos — the loop's failure
# path runs `git clean -fd` and would eat them.
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

# mk_fx <scope-content|-> — one-task per-task-layout fixture repo, physical path.
# "-" means no scope file. The task gate (and convergence gate) pass iff ok.txt says done.
mk_fx() {
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs/fx/tasks/T01-thing" "$d/.evidence"
  echo '# fx spec' > "$d/specs/fx/spec.md"
  echo 'T1: write done into ok.txt' > "$d/specs/fx/tasks.txt"
  echo placeholder > "$d/.evidence/keep.txt"
  # As in the real repo: run evidence is IGNORED, so the loop's `git clean -fd` spares it.
  printf '.evidence/runs/\n' > "$d/.gitignore"
  local gate='grep -q done "$(git rev-parse --show-toplevel)/ok.txt" 2>/dev/null || { echo "  FAIL  fx: ok.txt missing" >&2; exit 1; }; echo "  PASS  fx: ok.txt present"; exit 0'
  printf '#!/usr/bin/env bash\n%s\n' "$gate" > "$d/specs/fx/tasks/T01-thing/verify.sh"
  printf '#!/usr/bin/env bash\n%s\n' "$gate" > "$d/specs/fx/verify.sh"
  [ "$1" != "-" ] && printf '%s\n' "$1" > "$d/specs/fx/tasks/T01-thing/scope"
  git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null
  printf '%s' "$d"
}

mk_stub() { # <body> -> path; the stub's $1 is the executor prompt
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

SCOPE_MSG='outside this task'
SCOPE='# the deliverable, nothing else
ok.txt'

# ── ac1: in-scope work under a scope → passes, no rejection ──
# (Also the implicit proof that the loop's own .evidence bookkeeping writes are excluded.)
FX1="$(mk_fx "$SCOPE")"
S_IN="$(mk_stub 'echo done > "$ROOT/ok.txt"')"
out1="$(run_fx "$FX1" "$S_IN")"; rc1=$?
[ "$rc1" -eq 0 ] \
  && ok "ac1: a scoped in-scope attempt passes (rc=0)" \
  || no "ac1: scoped in-scope attempt failed (rc=$rc1) — $(printf '%s' "$out1" | grep -E 'FAIL|✗' | head -2 | tr '\n' ' ')"
printf '%s' "$out1" | grep -q "$SCOPE_MSG" \
  && no "ac1: the scope guard fired on in-scope work (or on bookkeeping writes)" \
  || ok "ac1: no scope rejection for in-scope work"

# ── ac2: out-of-scope change → rejected before the gate, tree reset, nothing committed ──
FX2="$(mk_fx "$SCOPE")"
S_OUT="$(mk_stub 'echo stray > "$ROOT/stray.txt"')"
out2="$(run_fx "$FX2" "$S_OUT")"; rc2=$?
printf '%s' "$out2" | grep -q "$SCOPE_MSG" \
  && ok "ac2: the loop rejected the out-of-scope attempt" \
  || no "ac2: no scope rejection in loop output (rc=$rc2)"
printf '%s' "$out2" | grep -q 'stray.txt' \
  && ok "ac2: the rejection names the offending path" \
  || no "ac2: the rejection does not name stray.txt — feedback is not targeted"
printf '%s' "$out2" | grep -q 'passed verify' \
  && no "ac2: the gate ran and passed after a violation — the check must fire BEFORE the gate" \
  || ok "ac2: the gate never blessed the violating attempt"
[ "$rc2" -eq 2 ] \
  && ok "ac2: the run still fails overall (exit 2)" \
  || no "ac2: expected exit 2, got $rc2"
[ -f "$FX2/stray.txt" ] \
  && no "ac2: stray.txt survived — the tree was not reset" \
  || ok "ac2: the tree was reset (stray.txt gone)"
_n2="$(git -C "$FX2" rev-list --count HEAD)"
[ "$_n2" -eq 1 ] \
  && ok "ac2: nothing was committed (fixture commit only)" \
  || no "ac2: $_n2 commits — the violating attempt was committed"
_d2="$(find "$FX2/.evidence/runs" -name '*.diff' 2>/dev/null | head -1)"
if [ -n "$_d2" ] && grep -q 'stray' "$_d2"; then
  ok "ac2: the rejected work was captured to evidence BEFORE the reset (issue #23's rule)"
else
  no "ac2: no diff artifact for the rejected attempt — the work vanished unrecorded"
fi

# ── ac3: in-scope AND out-of-scope in one attempt → rejected WHOLESALE, never filtered ──
FX3="$(mk_fx "$SCOPE")"
S_BOTH="$(mk_stub 'echo done > "$ROOT/ok.txt"; echo stray > "$ROOT/stray.txt"')"
out3="$(run_fx "$FX3" "$S_BOTH")"; rc3=$?
printf '%s' "$out3" | grep -q "$SCOPE_MSG" \
  && ok "ac3: the mixed attempt was rejected" \
  || no "ac3: no scope rejection for the mixed attempt (rc=$rc3)"
[ -f "$FX3/ok.txt" ] \
  && no "ac3: ok.txt survived — the loop filtered instead of rejecting wholesale" \
  || ok "ac3: the in-scope half was discarded too (reject-wholesale, never filter-the-commit)"
_n3="$(git -C "$FX3" rev-list --count HEAD)"
[ "$_n3" -eq 1 ] \
  && ok "ac3: nothing was committed" \
  || no "ac3: $_n3 commits — filtered work reached the history"

# ── ac4: no scope file → behavior unchanged (control): strays sweep in as today ──
FX4="$(mk_fx "-")"
out4="$(run_fx "$FX4" "$S_BOTH")"; rc4=$?
[ "$rc4" -eq 0 ] \
  && ok "ac4: control — the unscoped run passes exactly as today (rc=0)" \
  || no "ac4: control broke — unscoped run failed (rc=$rc4)"
printf '%s' "$out4" | grep -q "$SCOPE_MSG" \
  && no "ac4: control — the scope guard fired with no scope file" \
  || ok "ac4: control — no scope rejection without a scope file"
git -C "$FX4" show --stat HEAD | grep -q 'stray.txt' \
  && ok "ac4: control — add -A still sweeps the stray in when unscoped (superset, not migration)" \
  || no "ac4: control — the stray did not commit; unscoped behavior changed"

# ── ac5: the executor prompt carries the scope globs ──
FX5="$(mk_fx "$SCOPE")"
PC="$(mktemp)"; _FX="$_FX $PC"
S_PROMPT="$(mk_stub 'printf "%s" "$1" > "$PROMPT_COPY"; echo done > "$ROOT/ok.txt"')"
out5="$(run_fx "$FX5" "$S_PROMPT" PROMPT_COPY="$PC")"; rc5=$?
grep -q 'ONLY paths matching' "$PC" && grep -q 'ok.txt' "$PC" \
  && ok "ac5: the prompt states the scope and its globs" \
  || no "ac5: the prompt does not carry the scope (rc=$rc5)"

# ── ac6: a scope file with no globs is refused up front (exit 3) ──
FX6="$(mk_fx '# comments only — matches nothing')"
out6="$(run_fx "$FX6" "$S_IN")"; rc6=$?
[ "$rc6" -eq 3 ] \
  && ok "ac6: an empty scope refuses to start (exit 3, spec-needs-attention)" \
  || no "ac6: expected exit 3 for a globless scope, got $rc6"
printf '%s' "$out6" | grep -qi 'scope' \
  && ok "ac6: the refusal names the scope file" \
  || no "ac6: the refusal does not mention the scope"

# ── ac7 ──
bash -n "$RB" \
  && ok "ac7: ralph-build.sh passes bash -n" \
  || no "ac7: bash -n fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
