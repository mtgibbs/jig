# MUTANT: ac01
# TARGET: specs/lib/assert.sh
# WHY: moves the call inside gate_tmpdir, so a gate is protected only if it makes a workspace.
# WHY: Gates that assert on file text never call gate_tmpdir and inherit everything, and the rule
# WHY: is back to being one you have to know.
# assert.sh — shared assertion vocabulary for per-task gates
#
# OMISSION: No `pend` function is defined. Per-task gates assert only their own
# task's criteria, so there is nothing to defer. Providing `pend` invites misfiled
# assertions (integration checks tucked into task gates), which this spec exists
# to eliminate. The verb is banned; mentioning it in prose is not.
#
# This file is sourced, never executed, so it must not call `exit` at the top
# level and must not run anything on load.

# `bound` comes along for the ride, from the one implementation in scripts/bound.sh. A gate that
# drives the loop or the tool needs a wall-clock bound as much as the tool does, and a second
# copy of it here is the drift this repo keeps removing. Resolved relative to THIS file so it
# works from a consumer repo's checkout as well as from the harness's own.
# shellcheck source=/dev/null
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../../scripts" 2>/dev/null && pwd)/bound.sh" 2>/dev/null || true

# THE QUARANTINED SET — the harness's own configuration cannot reach a fixture.
#
#   HARNESS_REPORT_URL/_TOKEN  a fixture loop that inherits these POSTS TO THE PRODUCTION
#                              coordinator; eight rows keyed spec=fx landed on the live board
#                              this way and share harness#46's eviction, so they can evict a run
#   RALPH_FORCE_ALL/_FROM      a gate that inherits them cannot skip inside its own fixtures;
#                              four of six assertions could not pass whatever the executor wrote
#   RALPH_SATISFIED_TIMEOUT    a gate that sets it per case is silently overridden
#
# Unset, never a sentinel: a sentinel URL is still a URL and something eventually POSTs to it.
# Run at SOURCE time, which is what makes it unforgettable and also what bounds it — anything a
# gate sets afterwards is the gate's own choice and survives.
gate_env_reset() {
  unset HARNESS_REPORT_URL HARNESS_REPORT_TOKEN \
        RALPH_FORCE_ALL RALPH_FORCE_FROM RALPH_SATISFIED_TIMEOUT
}
fail=0

# ok <message> — print PASS message to stdout
ok() {
  echo "  PASS  $1"
}

# no <message> — print FAIL message to stderr and set fail=1
no() {
  echo "  FAIL  $1" >&2
  fail=1
}

# gate_tmpdir — create temp directory and prove it is not mounted noexec
#
# Exports PYTHONDONTWRITEBYTECODE=1 and points PYTHONPYCACHEPREFIX inside T.
# If the directory cannot execute a simple script, prints the environment name
# and exits 2 (neither pass nor fail).
gate_tmpdir_advice() {
  echo "workspace cannot execute. Set GATE_TMPDIR to a mount that can, e.g." >&2
  echo "  GATE_TMPDIR=/home/agent/tmp bash \"$0\"" >&2
  echo "environment: $(uname -n 2>/dev/null || echo unknown)" >&2
}

gate_tmpdir() {
  gate_env_reset
  T=$(mktemp -d "${GATE_TMPDIR:-${TMPDIR:-/tmp}}/gate.XXXXXX")
  local probe="$T/probe.sh"
  cat > "$probe" << 'PROBE'
#!/bin/bash
exit 0
PROBE
  chmod +x "$probe"
  if ! "$probe" 2>/dev/null; then
    gate_tmpdir_advice
    exit 2
  fi
  export PYTHONDONTWRITEBYTECODE=1
  export PYTHONPYCACHEPREFIX="$T/.pycache"
}

# gate_done — print separator and exit 0/1 based on fail status
gate_done() {
  echo "---"
  if [ "$fail" -eq 0 ]; then
    echo "VERIFY: PASS"
    exit 0
  else
    echo "VERIFY: FAIL"
    exit 1
  fi
}
