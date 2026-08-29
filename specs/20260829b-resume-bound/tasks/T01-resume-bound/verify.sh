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

gate_done
