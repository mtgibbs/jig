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

# ── the quarantine ───────────────────────────────────────────────────────────────────────────
#
# Sourcing this file is the protection. A gate inherits the environment of whatever launched it
# — a shell, a container, the loop itself — and five variables in that environment change what a
# gate MEASURES rather than how it runs. They are removed here, on load, so that no gate has to
# carry a line of its own and no author has to know a rule.
#
# UNSET, never a sentinel. A sentinel URL is still a URL, and something eventually POSTs to it.
#
# This runs at SOURCE TIME, which is both what makes it unforgettable and what makes it bounded:
# anything a gate sets AFTER this line is the gate's own choice and survives. Several gates
# configure these deliberately for the case they are testing, this spec's own gate included.
#
# Each entry carries the failure that earned it. The list is the only place a reader learns what
# kind of evidence puts a variable here, and a list that reads as arbitrary gets added to
# arbitrarily.

# A fixture loop that inherits these POSTS TO THE PRODUCTION COORDINATOR. Eight rows keyed
# `spec=fx` landed on the live fleet board this way; they share harness#46's oldest-first
# eviction, so a gate's throwaway run can push out the record of a real one.
unset HARNESS_REPORT_URL
unset HARNESS_REPORT_TOKEN

# A gate that inherits these cannot skip anything inside its own fixtures — the loop it drives
# is forced to re-run every task. Four of six assertions in 20260829b could not pass whatever
# the executor wrote, and a fifth passed for the wrong reason.
unset RALPH_FORCE_ALL
unset RALPH_FORCE_FROM

# A gate that sets this per case is silently overridden by an ambient value, so the case it
# thinks it is testing is not the case that runs.
unset RALPH_SATISFIED_TIMEOUT

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
gate_tmpdir() {
  T=$(mktemp -d)
  local probe="$T/probe.sh"
  cat > "$probe" << 'PROBE'
#!/bin/bash
exit 0
PROBE
  chmod +x "$probe"
  if ! "$probe" 2>/dev/null; then
    echo "environment: $(uname -n 2>/dev/null || hostname 2>/dev/null || echo 'unknown')" >&2
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
