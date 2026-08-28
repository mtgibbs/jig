#!/usr/bin/env bash
# T01 — a task whose own gate already passes is skipped, and the executor is never called for it.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
. "$ROOT/specs/20260828l-run-control/lib/fixtures.sh"
mkexec

# ac1/ac2 — task 1's work is already present and committed, exactly the state a re-run finds.
mkloop "$T/a" yes
echo a > "$T/a/a.txt"
( cd "$T/a" && git add -A && git commit -qm done1 ) >/dev/null 2>&1
runloop "$T/a"
n="$(execs "$T/a")"
if [ "$RC" = 124 ]; then
  no "ac1: the loop did not return within 180s. Loop said: $(loopout a)"
  no "ac2: the skip is announced"
elif [ "$n" -gt 1 ]; then
  no "ac1: the executor ran $n times for a 2-task spec whose first task was already complete — the satisfied task was not skipped. Loop said: $(loopout a)"
elif [ "$n" = 0 ]; then
  no "ac1: the executor never ran at all — task 2 was unbuilt and must NOT have been skipped. Loop said: $(loopout a)"
else
  ok "ac1: a task whose gate already passes is skipped, and the executor is not called for it"
fi
if grep -qiE 'skip|satisfied|already' "$T/a.out"; then
  ok "ac2: the skip is announced, so a run that jumps tasks is still readable"
else
  no "ac2: a task was skipped with no announcement — silently-not-done is indistinguishable from silently-failed. Loop said: $(loopout a)"
fi

# ac3 — the unanswerable case. With one gate for the whole spec, a green gate means the SPEC is
# done, not this task; skipping on that basis marks every remaining task satisfied.
mkloop "$T/b" no
echo a > "$T/b/a.txt"
( cd "$T/b" && git add -A && git commit -qm done1 ) >/dev/null 2>&1
runloop "$T/b"
n="$(execs "$T/b")"
if [ "$RC" = 124 ]; then
  no "ac3: the loop did not return within 180s on a spec with no tasks/"
elif [ "$n" -lt 2 ]; then
  no "ac3: a spec with NO per-task gates skipped a task (executor ran $n times, expected 2) — that question is unanswerable there and must not be guessed. Loop said: $(loopout b)"
else
  ok "ac3: a spec without per-task gates is unchanged — nothing is skipped"
fi

# ac4 — the control that makes ac1 mean something: with nothing built, nothing is skipped.
mkloop "$T/c" yes
runloop "$T/c"
n="$(execs "$T/c")"
if [ "$n" -ge 2 ]; then
  ok "control: on a fresh tree no task is skipped ($n executor runs)"
else
  no "control: a fresh tree skipped work — the executor ran only $n times for 2 unbuilt tasks. Loop said: $(loopout c)"
fi
gate_done
