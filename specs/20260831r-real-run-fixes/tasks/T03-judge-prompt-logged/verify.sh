#!/usr/bin/env bash
# Gate for T03-judge-prompt-logged (20260831r-real-run-fixes).
# ralph-judge.sh sources ralph-log.sh (guarded, house pattern) so log_prompt exists,
# with a no-op fallback when the file is absent — no more
# "log_prompt: command not found" every judge round.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
RJ="$R/scripts/ralph-judge.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

# ── ac1: the guarded source exists ──
grep -q 'ralph-log\.sh' "$RJ" \
  && ok "ac1: ralph-judge.sh references ralph-log.sh" \
  || no "ac1: ralph-judge.sh never sources ralph-log.sh — log_prompt is undefined at its call site"

# ── ac2: the absence fallback defines log_prompt as a no-op ──
grep -Eq 'log_prompt\(\)[[:space:]]*\{' "$RJ" \
  && ok "ac2: a fallback log_prompt definition exists for the file-absent path" \
  || no "ac2: no fallback — a judge run without ralph-log.sh still dies at the call"

# ── ac3: the function the judge calls is one ralph-log.sh actually provides ──
( . "$R/scripts/ralph-log.sh" >/dev/null 2>&1 || true
  command -v log_prompt >/dev/null 2>&1 ) \
  && ok "ac3: ralph-log.sh defines log_prompt (the import target is real)" \
  || no "ac3: ralph-log.sh no longer defines log_prompt — the judge imports a ghost"

# ── ac4: the source happens BEFORE the call — order is the bug's whole story ──
src_ln="$(grep -n 'ralph-log\.sh' "$RJ" | head -1 | cut -d: -f1)"
call_ln="$(grep -n 'log_prompt "judge"' "$RJ" | head -1 | cut -d: -f1)"
if [ -n "$src_ln" ] && [ -n "$call_ln" ] && [ "$src_ln" -lt "$call_ln" ]; then
  ok "ac4: ralph-log.sh is sourced (line $src_ln) before the judge's log_prompt call (line $call_ln)"
else
  no "ac4: sourcing does not precede the call (source: ${src_ln:-none}, call: ${call_ln:-none})"
fi

bash -n "$RJ" && ok "ac5: ralph-judge.sh passes bash -n" || no "ac5: ralph-judge.sh fails bash -n"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T03 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
