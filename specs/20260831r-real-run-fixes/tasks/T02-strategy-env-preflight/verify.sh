#!/usr/bin/env bash
# Gate for T02-strategy-env-preflight (20260831r-real-run-fixes).
# A strategy declaring STRATEGY_ENV_REQUIRED is refused early (exit 3, var named,
# no phase run) when the environment lacks it; satisfied env proceeds; undeclared
# strategies behave as today; build-then-judge declares its executor key.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
RL="$R/scripts/run-loop.sh"
NS="$R/scripts/new-spec.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

FX="$(mktemp -d)"; FX="$(cd "$FX" && pwd -P)"; _FX="$_FX $FX"
git -C "$FX" init -q
git -C "$FX" config user.email fx@fx.invalid
git -C "$FX" config user.name fx
git -C "$FX" checkout -qb loop/fx
mkdir -p "$FX/specs" "$FX/.harness/loops"
bash "$NS" --root "$FX" --id 20990101a fx one >/dev/null 2>&1 || no "ac0: fixture scaffold failed"
printf '#!/usr/bin/env bash\nexit 0\n' > "$FX/stub-build.sh"
cat > "$FX/.harness/loops/fxenv.conf" <<'CONF'
STRATEGY_DESC="fixture: requires env"
STRATEGY_PHASES="build"
STRATEGY_ENV_REQUIRED="FX_REQUIRED_KEY"
export BUILD_CMD="$HARNESS_REPO_ROOT/stub-build.sh"
CONF
git -C "$FX" add -A && git -C "$FX" commit -qm fx >/dev/null

# ── ac1: missing required env → exit 3, var named, no phase ran ──
out1="$( cd "$FX" && env -u FX_REQUIRED_KEY bash "$RL" fxenv specs/20990101a-fx 2>&1 )"; rc1=$?
[ "$rc1" -eq 3 ] \
  && ok "ac1: refused with exit 3 when FX_REQUIRED_KEY is unset" \
  || no "ac1: expected exit 3, got rc=$rc1"
printf '%s' "$out1" | grep -q 'FX_REQUIRED_KEY' \
  && ok "ac1: the refusal names the missing variable" \
  || no "ac1: the missing variable is not named in the refusal"
printf '%s' "$out1" | grep -q '── phase:' \
  && no "ac1: a phase ran despite the missing env" \
  || ok "ac1: no phase ran before the refusal"

# ── ac2: empty counts as missing ──
out2="$( cd "$FX" && FX_REQUIRED_KEY= bash "$RL" fxenv specs/20990101a-fx 2>&1 )"; rc2=$?
[ "$rc2" -eq 3 ] && printf '%s' "$out2" | grep -q 'FX_REQUIRED_KEY' \
  && ok "ac2: an empty required variable is refused the same way" \
  || no "ac2: empty FX_REQUIRED_KEY was not refused (rc=$rc2)"

# ── ac3: satisfied env proceeds to the phase (value never echoed) ──
out3="$( cd "$FX" && FX_REQUIRED_KEY=sk-fx-secret-value bash "$RL" fxenv specs/20990101a-fx 2>&1 )"; rc3=$?
[ "$rc3" -eq 0 ] && printf '%s' "$out3" | grep -q '── phase: build' \
  && ok "ac3: satisfied env reaches the build phase and exits 0 (rc=$rc3)" \
  || no "ac3: expected rc=0 with build phase reached, got rc=$rc3"
printf '%s' "$out3" | grep -q 'sk-fx-secret-value' \
  && no "ac3: the required variable's VALUE leaked into loop output" \
  || ok "ac3: the value never appears in output"

# ── ac4: a strategy with no STRATEGY_ENV_REQUIRED is untouched ──
cat > "$FX/.harness/loops/fxplain.conf" <<'CONF'
STRATEGY_DESC="fixture: no env requirement"
STRATEGY_PHASES="build"
export BUILD_CMD="$HARNESS_REPO_ROOT/stub-build.sh"
CONF
out4="$( cd "$FX" && env -u FX_REQUIRED_KEY bash "$RL" fxplain specs/20990101a-fx 2>&1 )"; rc4=$?
[ "$rc4" -eq 0 ] \
  && ok "ac4: undeclared strategy runs as before (rc=0)" \
  || no "ac4: undeclared strategy broke (rc=$rc4)"

# ── ac5: built-in confs NEVER declare required env — operator knowledge stays out
# of shared files (a qwen key here would be one laptop's world baked into everyone's) ──
if grep -l 'STRATEGY_ENV_REQUIRED=' "$R"/scripts/loops/*.conf >/dev/null 2>&1; then
  no "ac5: a built-in conf hardcodes STRATEGY_ENV_REQUIRED — which env an executor needs is the operator's, not the harness's"
else
  ok "ac5: no built-in conf declares required env"
fi

# ── ac6: an operator's exported STRATEGY_ENV_REQUIRED flows through an undeclaring conf ──
out6="$( cd "$FX" && env -u FX_REQUIRED_KEY STRATEGY_ENV_REQUIRED="FX_REQUIRED_KEY" bash "$RL" fxplain specs/20990101a-fx 2>&1 )"; rc6=$?
[ "$rc6" -eq 3 ] && printf '%s' "$out6" | grep -q 'FX_REQUIRED_KEY' \
  && ok "ac6: operator-exported requirement is enforced when the conf declares none" \
  || no "ac6: exported STRATEGY_ENV_REQUIRED was not honored (rc=$rc6)"
out7="$( cd "$FX" && STRATEGY_ENV_REQUIRED="FX_REQUIRED_KEY" FX_REQUIRED_KEY=x bash "$RL" fxplain specs/20990101a-fx 2>&1 )"; rc7=$?
[ "$rc7" -eq 0 ] \
  && ok "ac6: satisfied operator-exported requirement proceeds (rc=0)" \
  || no "ac6: satisfied exported requirement still refused (rc=$rc7)"

# ── ac7: the contract is documented where strategy authors read ──
grep -q 'STRATEGY_ENV_REQUIRED' "$R/scripts/loops/README.md" \
  && grep -qi 'operator' "$R/scripts/loops/README.md" \
  && ok "ac7: loops/README.md documents the knob as operator-declared" \
  || no "ac7: loops/README.md does not document STRATEGY_ENV_REQUIRED"

bash -n "$RL" && ok "ac8: run-loop.sh passes bash -n" || no "ac8: run-loop.sh fails bash -n"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T02 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
