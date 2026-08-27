#!/usr/bin/env bash
# specs/last-task-strict/verify.sh — the deterministic gate for "the last task's gate is the
# strict gate".
#
# BEHAVIOURAL, NOT GREP-BASED. The claim is about what the loop DOES, so the gate builds a
# two-task fixture spec with a mock executor and runs ralph-build.sh against it. Grepping for
# `STRICT=` in ralph-build.sh would pass on a comment and on a broken implementation alike.
#
# The fixture is rigged so the two modes give OPPOSITE answers on the same tree:
#   T1 creates a.txt      -> ac1 PASSes, ac2 pends  -> lenient rc 0, and that is CORRECT
#   T2 creates junk       -> ac2 STILL pends        -> lenient rc 0 (today's bug), STRICT rc 1
# So "T1 passes AND T2 fails" is only reachable with per-task strictness. Whole-run STRICT fails
# T1; today's lenient-everywhere passes T2. Neither wrong answer can masquerade as the right one.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

BUILD="$R/scripts/ralph-build.sh"
TMPL="$R/specs/TEMPLATE.md"

for f in "$BUILD"; do
  [ -r "$f" ] || { echo "  FAIL  scope: $f missing" >&2; exit 1; }
  bash -n "$f" 2>/dev/null || { echo "  FAIL  scope: $f is not valid bash" >&2; exit 1; }
done
ok "scope: ralph-build.sh exists and parses"

_stray="$(find "$R/specs/last-task-strict" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence \
          2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$T/x"; chmod +x "$T/x" 2>/dev/null
"$T/x" 2>/dev/null || { echo "  FAIL  ENV: TMPDIR is noexec — re-run with TMPDIR=<exec-able dir>" >&2
                        echo "VERIFY: ENV" >&2; exit 2; }

# ── AC-4 / AC-5 · the regression guards, asserted at source because they ARE source facts ──
vn="$(sed 's/#.*//' "$BUILD" | grep -c 'bash "\$VERIFY"' 2>/dev/null || echo 0)"
[ "$vn" = 2 ] && ok "ac4: verify.sh is still invoked exactly twice (evidence-replayable AC-4 holds)" \
              || no "ac4: verify.sh is invoked $vn times; the baseline is 2 — a third call doubles every gate's side effects"

sed 's/#.*//' "$BUILD" | grep -q 'STRICT=1 bash "\$VERIFY"' \
  && ok "ac5: the final post-loop STRICT check is still there — the backstop was narrowed, not removed" \
  || no "ac5: the final STRICT check at ralph-build.sh:275 is gone; this spec narrows the gap, it does not replace the backstop"

# ── THE FIXTURE ────────────────────────────────────────────────────────────────────────────
P="$T/proj"; mkdir -p "$P/specs/demo"
git -C "$P" init -q 2>/dev/null
git -C "$P" config user.email g@e; git -C "$P" config user.name g
git -C "$P" checkout -q -b work 2>/dev/null

printf '# demo\n' > "$P/specs/demo/spec.md"
printf 'T1: create a.txt\n\nT2: create b.txt\n' > "$P/specs/demo/tasks.txt"

# The fixture gate. ac2 pends until b.txt exists — b.txt is T2's deliverable and the mock
# executor never creates it, which is the whole point.
cat > "$P/specs/demo/verify.sh" <<'FIX'
#!/usr/bin/env bash
f=0
[ -f a.txt ] && echo "  PASS  ac1: a.txt" || { echo "  FAIL  ac1: a.txt missing" >&2; f=1; }
if [ -f b.txt ]; then echo "  PASS  ac2: b.txt"
elif [ "${STRICT:-0}" = 1 ]; then echo "  FAIL  ac2: b.txt — still unbuilt at the final check (STRICT)" >&2; f=1
else echo "  pend  ac2: b.txt (not built yet)"; fi
[ "$f" = 0 ] && exit 0 || exit 1
FIX
chmod +x "$P/specs/demo/verify.sh"

# The mock executor: creates a.txt the first time, then unique junk. Never b.txt, and never a
# no-op — a no-op is scored as a failure by the loop and would confound the measurement.
cat > "$T/mock.sh" <<'MOCK'
#!/usr/bin/env bash
# Record the prompt. The retry feedback is delivered to the EXECUTOR, not printed in the run
# log, so the only honest place to assert AC-3 is the prompt the executor actually received.
printf '%s\n===PROMPT-END===\n' "${1:-}" >> "${GATE_PROMPTS:-/dev/null}"
cd "${ROOT:?}" || exit 1
if [ ! -f a.txt ]; then printf 'a\n' > a.txt; else
  n=1; while [ -e "junk$n.txt" ]; do n=$((n + 1)); done; printf 'j\n' > "junk$n.txt"
fi
exit 0
MOCK
chmod +x "$T/mock.sh"

git -C "$P" add -A 2>/dev/null; git -C "$P" commit -qm base 2>/dev/null

runloop() {  # -> RL_OUT, RL_RC
  : > "$T/prompts.txt"
  # RETRIES=1 so the last task gets a SECOND attempt: the feedback only exists on a retry, and a
  # feedback nobody receives is the failure mode this AC is about.
  RL_OUT="$(cd "$P" && ROOT="$P" RALPH_EXEC_CMD="$T/mock.sh" RALPH_RETRIES=1 \
            GATE_PROMPTS="$T/prompts.txt" \
            RALPH_AGENT=gate RALPH_LOG_DIR="$T/ev" RALPH_STATUS_DIR="$T/st" \
            RALPH_BUS_DISABLE=1 bash "$BUILD" "$P/specs/demo" 2>&1)"
  RL_RC=$?
}
runloop

# ── AC-1/AC-2 · the two halves, and each is the other's control ────────────────────────────
_t1_passed=0; _t2_passed=0
printf '%s' "$RL_OUT" | grep -qE '✓ *T1' && _t1_passed=1
printf '%s' "$RL_OUT" | grep -qE '✓ *T2' && _t2_passed=1

if [ "$_t1_passed" = 1 ]; then
  ok "ac2: T1 still passes under leniency — a mid-spec pend is not a failure"
else
  no "ac2: T1 failed. A mid-spec pend must NOT fail: that is whole-run STRICT, the wrong fix (spec §4)"
fi

if [ "$_t2_passed" = 1 ]; then
  pend "ac1: the last task's gate is strict (T2 passed with ac2 unbuilt — the bug this spec fixes)"
  pend "ac3: the still-red AC reaches the executor's feedback"
else
  if [ "$_t1_passed" = 1 ]; then
    ok "ac1: the LAST task's gate treats pend as failure, while the first task's does not"
  else
    no "ac1: T2 failed but so did T1 — that is whole-run STRICT, not per-task strictness"
  fi
  [ "$RL_RC" != 0 ] && ok "ac1: the run exits nonzero instead of declaring every task passed" \
                    || no "ac1: T2 did not pass yet the run exited 0"
  if grep -q 'FAILED verification' "$T/prompts.txt" 2>/dev/null && grep -q 'ac2' "$T/prompts.txt" 2>/dev/null; then
    ok "ac3: the retry prompt the executor received names the still-red AC (ac2)"
  else
    no "ac3: the executor's retry prompt never names ac2 — it is failed without being told why"
  fi
fi

# ── AC-6 · a reader can tell which gate ran ────────────────────────────────────────────────
# Scoped to the per-task VERDICT line, not the whole run. The final STRICT block already prints
# the word "strict" on its own, so a whole-output grep passes with nothing built — a gate that
# cannot fail. Measured: it did exactly that on the first draft of this gate.
_verdict="$(printf '%s\n' "$RL_OUT" | grep -E '(✓|✗) *T1' | head -1)"
if [ -z "$_verdict" ]; then
  pend "ac6: the run log names the gate's mode (no T1 verdict line to read)"
elif printf '%s' "$_verdict" | grep -qiE 'strict|lenient'; then
  ok "ac6: the task's own verdict line names the gate's mode"
else
  pend "ac6: the task's verdict line names the gate's mode"
fi

# ── AC-7 · the rule is written where gate authors read it ──────────────────────────────────
if [ -r "$TMPL" ]; then
  if grep -qi 'strict' "$TMPL" && grep -qiE 'last task|final task' "$TMPL"; then
    ok "ac7: TEMPLATE.md states that the final task's gate is strict"
  else
    pend "ac7: TEMPLATE.md states the rule"
  fi
else
  no "ac7: specs/TEMPLATE.md is missing"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
