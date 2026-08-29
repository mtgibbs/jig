# resume-bound — the question "is this already done?" must afford the answer

Tools: python3 bash git
MCP: none
Permissions: read, write, bash

## Why

`_task_satisfied` decides whether a task's work already exists by running that task's own gate and
watching it pass. It bounds that gate at `timeout 60`, hardcoded. `20260828o-evidence-egress`'s
T01 gate spawns real `ralph-build.sh` loops end to end and takes about five minutes. So the answer
never arrives, the predicate fails closed, and the task runs.

**The bound is inverted against the cost it is guarding.** A cheap gate belongs to a task that
would have converged anyway; resume earns its keep on the expensive ones, and that is precisely the
set the predicate cannot evaluate. The tighter the gate, the less resume is worth.

Worse, the same gate runs **unbounded** a few lines away. `run_gates` invokes it in the verify path
with no `timeout` at all. One gate, two bounds, and the strict one is on the cheaper question —
asking "is this already done?" is strictly less work than asking "is this correct now?", because
the answer is the same computation and nobody is waiting on an executor for it.

**Observed 2026-08-29.** `20260828o` was re-run with T1-T3 committed and each task's own gate green
(`T03-push-transcript` verified 4/4 by hand minutes earlier). Expected: skip to T4. Actual: the
board showed the run at T1 attempt 2, asking the executor to reproduce `71ebb13` and `e90fef1`.
The cost compounds — every attempt at a needlessly re-run task also drags the cumulative gate
1..n behind it, so a run making no progress is *more* expensive per attempt than one that is.

**And it says nothing.**

    out="$(timeout 60 bash "$g" 2>&1)" || { _rc=$?; [ "$_rc" -eq 124 ] && return 1 || return 1; }

Both branches return 1. A timeout and a failing gate are deliberately indistinguishable, and
neither is announced, so from outside "resume is defeated by its own bound" and "the gate genuinely
fails" look identical — the only symptom is a task running that should not have. That contradicts
the rule `20260828l-run-control` T1 set for the skip path itself: *"Announcing is not optional:
work that silently does not happen is indistinguishable from work that silently failed."* The same
argument applies to declining to skip, and declining is the case that costs an executor invocation.

## What this spec is not

It does not change what makes a task satisfied — its own gate passing, asked before the executor
runs, never the cumulative group. It does not touch `run_gates`, the attempt loop, the no-op guard,
or the force overrides. It does not remove the bound: a hanging gate must still not wedge a resume,
which is the reason a bound exists and that reason is still good. It does not cache or persist a
verdict; reading a recorded gate result instead of re-running one is a real option and belongs to
its own spec, not to a fix for the bound.

## The bar

**Fail-closed stays fail-closed.** Every uncertain case still runs the task: no gate, unrunnable
gate, failing gate, exceeded bound, forced. Nothing here may turn "I could not tell" into a skip.
A skip is the only outcome that costs correctness rather than time, and it must remain the outcome
that requires positive evidence.

**Finite, and generous enough to be useful.** The default must be no smaller than the loop's own
executor bound (`RALPH_EXEC_TIMEOUT`, 480s), because a gate is not permitted to be slower than the
work it judges, and a predicate that cannot outwait its own gate has no purpose. It stays finite so
a hung gate still fails closed rather than hanging the run.

**The two refusals must be distinguishable.** "Its gate did not pass" and "its gate did not finish"
are different facts with different fixes — one is unfinished work, the other is a bound to raise or
a gate to make cheaper. A reader must be able to tell them apart from the run's output alone,
without instrumenting the loop.

**A malformed override means the default, never zero.** Same discipline as
`HARNESS_ARTIFACT_MAX_BYTES`: an unset or unparseable value falls back to the default. Zero would
read as a bound of no time at all, which silently disables resume everywhere while looking like
configuration.

## Shape

One override, `RALPH_SATISFIED_TIMEOUT`, holding seconds; unset or malformed means the default.
The predicate announces its refusals on the same stream as the other task lines, naming the task
and which of the two cases it hit. The skip path's announcement is already correct and is not
touched.

## Gate cost, stated deliberately

One assertion in this spec's gate must prove that a task whose gate outlasts the OLD 60s bound is
now recognised, and there is no way to prove that without waiting longer than 60 seconds. That
assertion costs about a minute; the fixture's gate sleeps only on its first invocation so the
cumulative runs behind it stay fast. Every other assertion is seconds. This is named here because
`harness#42` is about gate economics, and a gate that quietly costs a minute is the kind of thing
that turns into a five-minute one nobody measured.
