#!/usr/bin/env bash
# T3 — a workspace that cannot execute names the variable and the fix.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829c-hermetic-gate/lib/fixtures.sh"
A="$ROOT/specs/lib/assert.sh"
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT

# ── ac01: GATE_TMPDIR relocates the workspace ────────────────────────────────────────────────
# Behavioural. The containers mount /tmp noexec deliberately and the compose file asks for it, so
# the fix an operator needs is a place to put the workspace — not a relaxed container.
mkdir -p "$D/elsewhere"
_where="$( env GATE_TMPDIR="$D/elsewhere" bash -c '. "$1" >/dev/null 2>&1; gate_tmpdir >/dev/null 2>&1; printf %s "${T:-NONE}"' _ "$A" 2>/dev/null )"
case "$_where" in
  "$D/elsewhere"/*) ok "ac01: GATE_TMPDIR relocates the workspace ($_where)" ;;
  NONE|"")          no "ac01: gate_tmpdir set no workspace at all under GATE_TMPDIR" ;;
  *)                no "ac01: the workspace landed at $_where, ignoring GATE_TMPDIR. An operator whose default mount is noexec has no way to point gates somewhere that executes, and the only alternative is relaxing a container's hardening" ;;
esac

# ── ac02: the failure says what to do ────────────────────────────────────────────────────────
# The message is asserted, a real noexec mount is NOT — a portable gate cannot mount a
# filesystem, and a check that claims to prove more than it does is what this spec removes. So
# the diagnostic path is called directly, which means T3 has to factor it out of the probe.
_advice="$( bash -c '. "$1" >/dev/null 2>&1
                     command -v gate_tmpdir_advice >/dev/null 2>&1 || { printf ABSENT; exit 0; }
                     gate_tmpdir_advice 2>&1' _ "$A" 2>/dev/null )"
if [ "$_advice" = ABSENT ]; then
  no "ac02: there is no diagnostic to call. gate_tmpdir prints 'environment: <hostname>' inline and exits — a fact about the machine, not an instruction, and nothing a gate can assert on without mounting a filesystem"
elif ! printf '%s' "$_advice" | grep -q 'GATE_TMPDIR'; then
  no "ac02: the failure message does not name GATE_TMPDIR, so the reader is told a workspace is unusable and not how to move it. Message: [$_advice]"
elif ! printf '%s' "$_advice" | grep -qE '/[A-Za-z0-9_./-]+'; then
  no "ac02: the message names the variable but shows no path to set it to. 'Set GATE_TMPDIR' and 'set GATE_TMPDIR=/home/agent/tmp' are different amounts of help at 2am"
else
  ok "ac02: the failure names GATE_TMPDIR and shows a usable path"
fi

# ── ac03: the contract around it is unchanged ────────────────────────────────────────────────
# Exit 2 is load-bearing: a workspace fault is neither a pass nor a failure, and a gate that
# turns it into a FAIL files an environment problem in the run's evidence as a defect in the work.
_probe="$( bash -c '. "$1" >/dev/null 2>&1; gate_tmpdir >/dev/null 2>&1
                    printf "%s|%s|%s" "${T:+set}" "${PYTHONDONTWRITEBYTECODE:-}" "${PYTHONPYCACHEPREFIX:+set}"' _ "$A" 2>/dev/null )"
case "$_probe" in
  set\|1\|set) ok "ac03: gate_tmpdir still makes a workspace and exports the python cache settings" ;;
  *)           no "ac03: gate_tmpdir's other guarantees changed [$_probe] — a spec that makes gates hermetic by dropping what they relied on has done the opposite of its job" ;;
esac
_rc="$( strip_comments "$A" | grep -A20 'gate_tmpdir()' | grep -cE 'exit 2' )"
[ "${_rc:-0}" -ge 1 ] && ok "ac03: a workspace fault still exits 2, not 1" \
                      || no "ac03: gate_tmpdir no longer exits 2 on a workspace fault. Callers read 2 as 'could not run'; turning it into 1 puts an environment problem into the evidence as a failed assertion"

gate_done
