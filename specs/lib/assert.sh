# assert.sh — shared assertion vocabulary for per-task gates
#
# OMISSION: No `pend` function is defined. Per-task gates assert only their own
# task's criteria, so there is nothing to defer. Providing `pend` invites misfiled
# assertions (integration checks tucked into task gates), which this spec exists
# to eliminate. The verb is banned; mentioning it in prose is not.
#
# This file is sourced, never executed, so it must not call `exit` at the top
# level and must not run anything on load.
#
# SOURCING THIS FILE IS THE PROTECTION. The quarantine below runs on load, which is what makes
# it unforgettable: a gate gets a clean environment by sourcing the file every gate already
# sources, and no author has to know a rule. Moving those unsets into a function that something
# has to remember to call would leave every gate looking correct and none of them protected,
# which is the state this replaced — two local patches under two different mechanisms and a
# comment deferring to a spec that never existed.
#
# The one place `unset` at load is NOT enough is a gate that sources nothing; 23 of those exist.
# scripts/ralph-build.sh's run_gates covers them at the invocation boundary. Two placements,
# different populations, neither redundant.

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

# A gate that sets this per case: an ambient value silently overrides the gate's own, so the
# case it thinks it is testing is not the case that runs.
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

# gate_tmpdir_advice [dir] — what to do about a workspace that cannot execute.
#
# Factored OUT of gate_tmpdir so it can be called, and therefore asserted, without a noexec
# filesystem. Be plain about the limit that buys: this MESSAGE is checked by
# 20260829c-hermetic-gate T3; a real noexec run is not, because a portable gate cannot mount a
# filesystem. A check that claims to prove more than it does is the thing this spec removes, so
# the gap is written down rather than papered over.
#
# It replaced `environment: <hostname>`, which named the machine. That is a fact, not an
# instruction: it told a reader which host had the problem and nothing about the fix, and the
# variable that IS the fix appeared in no gate's text anywhere in the repo.
gate_tmpdir_advice() {
  local d="${1:-${TMPDIR:-/tmp}}"
  # A path that would work, not just the name of a knob. "Set GATE_TMPDIR" and
  # "set GATE_TMPDIR=/home/agent/tmp" are different amounts of help at 2am.
  local suggest="${HOME:-/home/agent}/gate-tmp"
  {
    echo "gate: the workspace under $d cannot execute a script (the mount is noexec)."
    echo "gate: point GATE_TMPDIR at a directory that executes, then re-run:"
    echo "gate:     mkdir -p $suggest && GATE_TMPDIR=$suggest bash <gate>"
    echo "gate: the containers mount /tmp noexec deliberately and the compose file asks for it,"
    echo "gate: so this moves the workspace rather than relaxing a container's hardening."
  } >&2
}

# gate_tmpdir — create the workspace and prove it is not mounted noexec.
#
# Honours GATE_TMPDIR so an operator can relocate the workspace without touching a container.
# Exports PYTHONDONTWRITEBYTECODE=1 and points PYTHONPYCACHEPREFIX inside T.
# On a workspace that cannot execute, prints the advice above and exits 2 — neither a pass nor a
# failure. Callers read 2 as "could not run"; turning it into 1 would file an environment problem
# in the run's evidence as a defect in the work.
gate_tmpdir() {
  if [ -n "${GATE_TMPDIR:-}" ]; then
    mkdir -p "$GATE_TMPDIR" 2>/dev/null
    T=$(mktemp -d "${GATE_TMPDIR%/}/gate.XXXXXX")
  else
    T=$(mktemp -d)
  fi
  local probe="$T/probe.sh"
  cat > "$probe" << 'PROBE'
#!/bin/bash
exit 0
PROBE
  chmod +x "$probe"
  if ! "$probe" 2>/dev/null; then
    gate_tmpdir_advice "$T"
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
