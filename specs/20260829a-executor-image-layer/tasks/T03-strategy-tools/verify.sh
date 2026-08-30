#!/usr/bin/env bash
# T3 — a strategy declares the executable it needs, and a missing one stops the run in preflight.
#
# Behavioural. `STRATEGY_TOOLS` appears in this spec, in the loops README this task writes, and
# in run-loop.sh's own comments, so any text grep is satisfied by prose. Each assertion runs
# run-loop.sh and reads the exit code and the message.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829a-executor-image-layer/lib/fixtures.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

RL="$ROOT/scripts/run-loop.sh"
[ -f "$RL" ] || { no "ac0: scripts/run-loop.sh is missing entirely"; gate_done; }

mkrepo "$T/repo"
mkspec "$T/repo" fx
mkdir -p "$T/repo/.harness/loops"
SAFE="$T/safe.sh"; printf '#!/usr/bin/env bash\necho RAN\n' > "$SAFE"; chmod +x "$SAFE"

conf() {   # conf <name> <extra-line>
  { printf 'STRATEGY_DESC="fixture %s"\nSTRATEGY_PHASES="build"\n' "$1"
    [ -n "${2:-}" ] && printf '%s\n' "$2"
  } > "$T/repo/.harness/loops/$1.conf"
}
run_fx() { ( cd "$T/repo" && SCRIPT_DIR="$ROOT/scripts" BUILD_CMD="$SAFE" \
               bounded 20 bash "$RL" "$@" ) 2>&1; }
rc_of()  { ( cd "$T/repo" && SCRIPT_DIR="$ROOT/scripts" BUILD_CMD="$SAFE" \
               bounded 20 bash "$RL" "$@" ) >/dev/null 2>&1; echo $?; }

# A name no PATH will ever hold, so "absent" is a property of the tool and not of the machine.
ABSENT="definitely-not-on-path-9f3a2c"

# ── ac1: a declared tool that is absent stops the run, exit 3 ────────────────────────────────
conf missing "export STRATEGY_TOOLS=\"$ABSENT\""
rc="$(rc_of missing specs/fx)"
out="$(run_fx missing specs/fx)"
if echo "$out" | grep -q 'unknown strategy'; then
  no "ac1: the fixture strategy did not resolve at all — T2's search path is not in place, so this task cannot be measured yet"
elif echo "$out" | grep -q '^RAN$'; then
  no "ac1: the run proceeded to its build phase with $ABSENT absent. STRATEGY_TOOLS must fail CLOSED — a warning means the executor is discovered missing mid-run, as a shell error"
elif [ "$rc" != 3 ]; then
  no "ac1: exit code was $rc, not 3. run-loop.sh already exits 3 for a missing spec-declared tool; a second code for the same class of fault means the caller has to learn two"
else
  ok "ac1: a missing declared tool stops the run with exit 3"
fi

# ── ac2: the message names the tool AND the strategy that declared it ────────────────────────
out="$(run_fx missing specs/fx)"
if ! echo "$out" | grep -q "$ABSENT"; then
  no "ac2: the failure message does not name the missing executable, so the reader learns only that something is wrong"
elif ! echo "$out" | grep -q 'missing'; then
  no "ac2: the failure message does not name the strategy 'missing' that declared the tool. Without it the reader goes to the spec header, which is the wrong file — the declaration is in the conf"
else
  ok "ac2: the message names both the missing executable and the declaring strategy"
fi

# ── ac3: no STRATEGY_TOOLS means today's behaviour ───────────────────────────────────────────
# Absence assertion. Its POSITIVE CONTROL is ac1 above: the same probe already fired on a conf
# that DID declare a missing tool, so "it ran" here is a real reading and not a dead check.
conf quiet ""
rc="$(rc_of quiet specs/fx)"
out="$(run_fx quiet specs/fx)"
if [ "$rc" = 3 ]; then
  no "ac3: a conf with no STRATEGY_TOOLS exited 3 anyway — the preflight is failing on an empty declaration, which would break every strategy that exists today"
elif ! echo "$out" | grep -q '^RAN$'; then
  no "ac3: a conf with no STRATEGY_TOOLS did not reach its build phase. Output: $(echo "$out" | tail -2 | tr '\n' ' ')"
else
  ok "ac3: a conf declaring no tools behaves exactly as today"
fi

# ── ac4: a spec miss and a strategy miss report together, once ───────────────────────────────
SPEC_ABSENT="also-not-on-path-7b1d4e"
printf '# Spec: fx\n\n- **Tools:** %s\n- **MCP:** none\n' "$SPEC_ABSENT" > "$T/repo/specs/fx/spec.md"
conf both "export STRATEGY_TOOLS=\"$ABSENT\""
rc="$(rc_of both specs/fx)"
out="$(run_fx both specs/fx)"
n="$(echo "$out" | grep -ci 'needs attention' || true)"
if [ "$rc" != 3 ]; then
  no "ac4: two missing tools produced exit $rc, not 3"
elif ! echo "$out" | grep -q "$SPEC_ABSENT" || ! echo "$out" | grep -q "$ABSENT"; then
  no "ac4: only one of the two missing tools was reported. A second preflight block that exits on the first miss hides the rest, and the operator fixes one thing per run"
elif [ "$n" -gt 1 ]; then
  no "ac4: the 'needs attention' message was printed $n times — STRATEGY_TOOLS added a SECOND preflight block instead of joining the existing accumulation"
else
  ok "ac4: a spec miss and a strategy miss are reported in one message, exiting 3 once"
fi

# ── ac5: every built-in strategy declares the executable its binding invokes ─────────────────
# The preflight from ac1-ac4 protects a conf that DECLARES. A conf that declares nothing gets no
# protection at all, and the one that matters most is the default: build-converge binds
# exec-qwen.sh, whose executable is exactly the thing the derived image may not carry. Declaring
# is what turns "strategy and image disagree" from a shell error mid-run into a preflight refusal
# that names the missing tool.
_ld="$ROOT/scripts/loops"
if [ ! -d "$_ld" ]; then
  no "ac5: scripts/loops/ is missing"
else
  _bare=""
  for c in "$_ld"/*.conf; do
    [ -f "$c" ] || continue
    strip_comments "$c" | grep -q 'STRATEGY_TOOLS' || _bare="$_bare $(basename "$c" .conf)"
  done
  if [ -n "$_bare" ]; then
    no "ac5: built-in strategies declare no STRATEGY_TOOLS:$_bare — the preflight cannot protect a conf that declares nothing, and build-converge is the one every default run uses"
  else
    ok "ac5: every built-in strategy declares the executable its binding invokes"
  fi
fi

gate_done
