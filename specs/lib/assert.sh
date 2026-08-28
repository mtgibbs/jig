# assert.sh — shared assertion vocabulary for per-task gates
#
# OMISSION: No `pend` function is defined. Per-task gates assert only their own
# task's criteria, so there is nothing to defer. Providing `pend` invites misfiled
# assertions (integration checks tucked into task gates), which this spec exists
# to eliminate. The verb is banned; mentioning it in prose is not.
#
# This file is sourced, never executed, so it must not call `exit` at the top
# level and must not run anything on load.

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
