#!/usr/bin/env bash
# Gate for 20260831n-list-strategies-bash32. Single-task spec: one gate, no pend.
# Every check drives /bin/bash explicitly (the 20260818c idiom): Homebrew bash 5 on a
# dev machine is exactly what let declare -A hide in a bash-3.2-floor repo.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../.." && pwd -P)"
RL="$R/scripts/run-loop.sh"
B32=/bin/bash
[ -x "$B32" ] || B32=bash

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

# ── ac1: --list survives bash 3.2 ──
out1="$(cd "$R" && "$B32" "$RL" --list 2>&1)"; rc1=$?
[ "$rc1" -eq 0 ] \
  && ok "ac1: --list exits 0 under $B32" \
  || no "ac1: --list exited $rc1 — $(printf '%s' "$out1" | head -2 | tr '\n' ' ')"
printf '%s' "$out1" | grep -q 'build-converge' \
  && ok "ac1: build-converge is listed" \
  || no "ac1: build-converge missing from --list"
printf '%s' "$out1" | grep -q 'declare' \
  && no "ac1: a declare error leaked: $(printf '%s' "$out1" | grep declare | head -1)" \
  || ok "ac1: no declare noise"

# ── ac2/ac3: consumer shadowing and consumer-only listing, from a fixture repo ──
FX="$(mktemp -d)"; FX="$(cd "$FX" && pwd -P)"; _FX="$_FX $FX"
git -C "$FX" init -q
mkdir -p "$FX/.harness/loops"
printf 'STRATEGY_DESC="shadowed by the consumer"\nSTRATEGY_PHASES="build"\n' \
  > "$FX/.harness/loops/build-converge.conf"
printf 'STRATEGY_DESC="consumer-only strategy"\nSTRATEGY_PHASES="build"\n' \
  > "$FX/.harness/loops/fx-local.conf"
out2="$(cd "$FX" && "$B32" "$RL" --list 2>&1)"; rc2=$?
[ "$rc2" -eq 0 ] || no "ac2: fixture --list exited $rc2 — $(printf '%s' "$out2" | head -2 | tr '\n' ' ')"
_n="$(printf '%s\n' "$out2" | grep -c 'build-converge')"
[ "$_n" -eq 1 ] \
  && ok "ac2: a shadowed name lists exactly once" \
  || no "ac2: build-converge listed $_n times — dedup broke"
printf '%s\n' "$out2" | grep 'build-converge' | grep -q '\[consumer\]' \
  && ok "ac2: the consumer copy wins the shadow" \
  || no "ac2: the consumer override lost: $(printf '%s\n' "$out2" | grep 'build-converge' | head -1)"
printf '%s\n' "$out2" | grep 'fx-local' | grep -q '\[consumer\]' \
  && ok "ac3: a consumer-only strategy is listed" \
  || no "ac3: fx-local missing or mistagged"
printf '%s\n' "$out2" | grep -q '\[built-in\]' \
  && ok "ac3: built-ins still contribute alongside the consumer dir" \
  || no "ac3: no built-in strategies listed from the fixture repo"

# ── ac4: every line keeps the '  name [origin] desc' shape ──
bad="$(printf '%s\n' "$out2" | grep -v '^  [A-Za-z0-9_-]* *\[\(consumer\|built-in\)\]' | grep -v '^$' || true)"
[ -z "$bad" ] \
  && ok "ac4: every listed line keeps the output shape" \
  || no "ac4: malformed lines: $(printf '%s' "$bad" | head -2 | tr '\n' ' ')"

# ── ac5 ──
"$B32" -n "$RL" \
  && ok "ac5: run-loop.sh parses under $B32" \
  || no "ac5: bash -n fails under $B32"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
