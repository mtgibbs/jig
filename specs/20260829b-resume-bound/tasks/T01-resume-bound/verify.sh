#!/usr/bin/env bash
# T1 — the predicate can afford the answer, and says which refusal it hit.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829b-resume-bound/lib/fixtures.sh"

gate_tmpdir
trap 'rm -rf "$T"' EXIT
mkexec

# ac1 — the fix. A task whose own gate outlasts the OLD 60s bound is still recognised as done.
# There is no way to assert this without waiting longer than 60 seconds; the fixture's gate
# sleeps on its first invocation only, so the cumulative runs behind it stay fast.
mkloop "$T/slow" 62 yes
runloop "$T/slow"
if ran "$T/slow" "make a"; then
  no "ac1: task 1 was already done and its gate passes, but the executor was invoked for it anyway — the predicate could not outwait a 62s gate. Loop said: $(loopout slow)"
elif [ "$RC" != 0 ]; then
  no "ac1: the run exited $RC. Loop said: $(loopout slow)"
elif ! ran "$T/slow" "make b"; then
  no "ac1: task 2 never ran, so the run proves nothing about task 1 having been skipped. Loop said: $(loopout slow)"
else
  ok "ac1: a task whose gate costs more than the old 60s bound is recognised as already done"
fi

# ac2 — the bound still bites, and still fails CLOSED. Overridden low against a slower gate.
mkloop "$T/tight" 6 yes
runloop "$T/tight" RALPH_SATISFIED_TIMEOUT=2
if ! ran "$T/tight" "make a"; then
  no "ac2: task 1 was skipped although its gate needs ~6s and the bound was set to 2s. Either RALPH_SATISFIED_TIMEOUT is not being read at all, or an unanswered question was treated as a yes — the second is the one that costs correctness rather than time. Loop said: $(loopout tight)"
else
  ok "ac2: a gate that outruns the bound still fails closed — the task runs"
fi

# ac3 — and it SAYS the bound is what stopped it, naming the knob that raises it.
if ! grep -qi 'RALPH_SATISFIED_TIMEOUT' "$T/tight.out"; then
  no "ac3: the run declined to skip because its gate ran out of time and never named RALPH_SATISFIED_TIMEOUT, so a reader cannot tell a bound to raise from work still to do. Loop said: $(loopout tight)"
elif ! grep -qiE 'timed out|did not finish|exceed' "$T/tight.out"; then
  no "ac3: nothing in the output says the gate did not FINISH; naming the variable without naming the case leaves the two refusals still conflated. Loop said: $(loopout tight)"
else
  ok "ac3: a bound-exceeded refusal announces itself and names how to raise the bound"
fi

# ac4 — the OTHER refusal must read differently. This is the assertion that separates the two
# states; an implementation printing one generic message for both satisfies ac3 and fails here.
mkloop "$T/unmet" 0 no
runloop "$T/unmet"
if ! grep -qi 'did not pass' "$T/unmet.out"; then
  no "ac4: task 1's gate ran and failed, and nothing announced that its gate did not pass. Loop said: $(loopout unmet)"
elif grep -qi 'RALPH_SATISFIED_TIMEOUT' "$T/unmet.out"; then
  no "ac4: a gate that RAN and failed was reported with the timeout's message — the two refusals are still one message, and a reader is told to raise a bound that was never reached. Loop said: $(loopout unmet)"
else
  ok "ac4: a failing gate and an unfinished gate are announced as different facts"
fi

# ac5 — a malformed override means the DEFAULT, never zero. Zero would read as configuration and
# silently disable resume everywhere.
mkloop "$T/junk" 0 yes
runloop "$T/junk" RALPH_SATISFIED_TIMEOUT=abc
if ran "$T/junk" "make a"; then
  no "ac5: an unparseable RALPH_SATISFIED_TIMEOUT stopped an already-done task from being recognised — a malformed value fell through to a bound of no time at all instead of the default. Loop said: $(loopout junk)"
else
  ok "ac5: a malformed override falls back to the default rather than to zero"
fi


# ac6 — an announcement must not contradict the action it describes. ac3 and ac4 check that the
# right FACTS appear; neither notices a line that reports the opposite outcome while carrying
# them. Both refusal branches are paths where the task is NOT skipped and the executor runs, so
# a line calling it skipped tells a reader precisely the reverse of what happened — the defect
# this spec exists to remove, reintroduced in the message that announces its removal. The legal
# skip line ("gate already passed") belongs to the other branch and does not appear in either of
# these runs, so any "skipped" found here is on a refusal.
tl="$(grep -iE 'did not finish|timed out|exceed' "$T/tight.out" 2>/dev/null | head -1)"
ul="$(grep -i 'did not pass' "$T/unmet.out" 2>/dev/null | head -1)"
if [ -z "$tl" ] || [ -z "$ul" ]; then
  no "ac6: one of the two refusal announcements was not found, so this assertion could not run — see ac3 and ac4"
elif echo "$tl" | grep -qi 'skipped'; then
  no "ac6: the bound-exceeded refusal calls the task skipped, and it was not — it ran. The line was: $tl"
elif echo "$ul" | grep -qi 'skipped'; then
  no "ac6: the failed-gate refusal calls the task skipped, and it was not — it ran. The line was: $ul"
else
  ok "ac6: neither refusal announces the task as skipped, because neither of them skipped it"
fi


# ac7 — a gate that FAILS must never be read as satisfied, however much of it passed. The verdict
# is the exit status; the PASS lines are per-assertion detail and a gate that fails prints plenty
# of them. Deciding by searching the output for the word PASS therefore skips a task whose gate is
# red, which is the one failure mode worse than not skipping at all: not-skipping costs time, this
# costs correctness and does it silently. Measured 2026-08-29 — dropping the exit-status guard in
# front of that search turned this from latent into live, and it reached a commit.
mkloop "$T/mixed" 0 mixed
runloop "$T/mixed"
if ! ran "$T/mixed" "make a"; then
  no "ac7: task 1's gate printed a PASS line and then FAILED, and the task was skipped anyway — the verdict was taken from the presence of the word PASS rather than from the gate's exit status, so a red gate now silently satisfies a task. Loop said: $(loopout mixed)"
else
  ok "ac7: a failing gate is not satisfied, no matter how many of its assertions passed"
fi

gate_done
