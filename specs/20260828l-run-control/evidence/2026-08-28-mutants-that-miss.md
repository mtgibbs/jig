# A mutant that removes one of two redundant guards changes nothing

**Date:** 2026-08-28 · validating this spec's gates before opening it.

Eight mutants, seven killed by their own assertion on the first try. The survivor was `ac3` — the
safety boundary, *"a spec with no per-task gates must not skip anything"* — and for the second
time in a day the assertion was fine and the **mutant had missed**.

## What happened

`_task_satisfied` refuses a monolithic spec twice over:

```bash
[ -d "$SPEC_DIR/tasks" ] || return 1      # explicit guard
g="$(_gate_for "$n")" || return 1          # and _gate_for fails there anyway
```

My mutant deleted the first line. The second still refused, so the behaviour never changed and
`ac3` had nothing to detect. It read as *"this assertion cannot detect this"*, which is exactly the
wrong conclusion — the obvious response is to strengthen a check that was already correct.

Re-pointed at the implementation someone would plausibly write instead — *"run this task's gate,
or the spec gate if the task hasn't got one"* — and `ac3` killed it immediately, catching the
catastrophic form: the executor ran **zero** times, both tasks were skipped, and the run reported
success having done nothing.

## The rule this adds

The `20260828k` write-up said a mutant must *disable the behaviour, not delete one of the places
that implement it*. This is the same defect arriving one spec later, which suggests the rule needs
a procedure rather than good intentions:

> **Before writing a mutant, look for a second implementation of the behaviour.** Defensive code
> commonly guards the same property twice — a check plus a fallback, a restore before plus a
> restore after. Removing one leaves the property intact and produces a false survivor.

And the sharper version, which is what actually worked both times: **do not mutate by deletion.**
Write the mutant as the wrong implementation a competent person would plausibly produce. Deleting
a line tests whether that line is load-bearing; writing the plausible mistake tests whether the
assertion catches the mistake — and only the second is what the gate exists for.

Related: `specs/amendments.md`, *"Name the states a check must tell apart"* — a mutant is itself a
check, and the states it must separate are "the behaviour is present" and "the behaviour is gone".
