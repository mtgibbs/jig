# bound.sh — a wall-clock bound that exists on every machine this repo runs on.
#
# Sourced, never executed. Defines one function and runs nothing on load.
#
# WHY THIS FILE EXISTS. `timeout` is GNU coreutils. Linux has it; macOS ships neither `timeout`
# nor `gtimeout`. scripts/gate-selftest.sh and four of the gates for specs/20260828k-gate-selftest
# used it, so on a laptop the tool exited 127 before running a single gate and reported every
# mutant as WRONG-REASON — the verdict that means "your mutant missed", which sends the author to
# rewrite checks that were already correct. All eight of that spec's own gates were red here for
# the same reason. A bound that works on only one of the two machines the harness runs on is not
# a bound.
#
# `bound` prefers the real `timeout` when present, so CI behaviour is unchanged, and otherwise
# falls back to perl, which both platforms already have. The exit contract is `timeout`'s:
# 124 means the bound fired.
#
# THE PROCESS GROUP IS LOAD-BEARING. The child runs as its own group leader and the alarm kills
# the GROUP. Killing only the direct child leaves its children alive holding the write end of the
# pipe, so the caller's command substitution goes on waiting for EOF and the tool inherits the
# hang it was bounding. That is not a BSD-vs-GNU quirk; it is what "bounded" has to mean.
#
# NOT `alarm; exec`: exec REPLACES the process, taking the SIGALRM handler with it, so the alarm
# never fires. A bound that cannot fire and a command that never times out look identical here.

_BOUND_PROG='
my $secs = shift;
my $pid = fork;
die "bound: fork failed\n" unless defined $pid;
if (!$pid) { setpgrp(0, 0); exec @ARGV; exit 127 }
$SIG{ALRM} = sub { kill("KILL", -$pid); waitpid($pid, 0); exit 124 };
alarm $secs;
waitpid($pid, 0);
my $st = $?;
alarm 0;
exit( ($st & 127) ? 128 + ($st & 127) : ($st >> 8) );
'

# bound <seconds> <cmd> [args...]
bound() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
    return $?
  fi
  perl -e "$_BOUND_PROG" "$secs" "$@"
}
