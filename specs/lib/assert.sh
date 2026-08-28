# Shared assertion vocabulary for all gates in the harness.
#
# This file is sourced, never executed. It defines only `ok`, `no`, `gate_tmpdir`, and
# `gate_done`. `pend` is intentionally omitted — deferred assertions have no place in
# the shared vocabulary and must not appear in per-task gates (see spec §2.3). The
# keyword `pend` appears below only in this comment block to document the omission.
#
# Usage:
#   . "$ROOT/specs/lib/assert.sh"
#   ok "message"     # prints "  PASS  message"
#   no "message"     # prints "  FAIL  message" to stderr, sets fail=1
#   gate_tmpdir      # creates temp dir, exports PYTHONDONTWRITEBYTECODE=1, sets PYTHONPYCACHEPREFIX
#   gate_done        # prints "---", exits 0 if pass, 1 if fail
#   gate_done "custom message"  # custom exit message
set -u

fail=0

ok() {
  echo "  PASS  $1"
}

no() {
  echo "  FAIL  $1" >&2
  fail=1
}

gate_tmpdir() {
  T="$(mktemp -d)" || { echo "VERIFY: ENV (no temp dir)" >&2; exit 2; }
  printf '#!/bin/sh\nexit 0\n' > "$T/x"; chmod +x "$T/x"
  "$T/x" 2>/dev/null || { echo "VERIFY: ENV (noexec TMPDIR — set TMPDIR to an exec-able path)" >&2; exit 2; }
  trap 'rm -rf "$T"' EXIT
  export PYTHONDONTWRITEBYTECODE=1
  export PYTHONPYCACHEPREFIX="$T/pyc"
}

gate_done() {
  echo "---"
  if [ "$fail" = 0 ]; then
    echo "VERIFY: PASS${1:+ $1}"
    exit 0
  else
    echo "VERIFY: FAIL${1:+ $1}"
    exit 1
  fi
}
