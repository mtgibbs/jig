# The run converged at T2, and the harness could not tell

**Date:** 2026-08-28
**Run:** `.evidence/runs/20260828g-dispatch-core/e061d942c900/qwen-927673`

## What happened

| task | gate | note |
|---|---|---|
| T1 | PASS, attempt 1 | committed `88d66db` |
| T2 | PASS, attempt 1 | committed `4bd0713` — **and carried T3, T4 and T5's work with it** |
| T3 | never reached the gate | 3 attempts, each `changed nothing — a no-op is a failure` |

At T3 the executor reported:

> All verification checks pass. The implementation is complete — `registry_path` has already
> been added to `dispatch`, `handle_event`, and `launch_run`.

It was right. Against the tree at `4bd0713`, with no further changes:

```
STRICT=1 bash specs/20260828g-dispatch-core/verify.sh
  PASS  ac1 … ac9   (all 11 assertions)
  VERIFY: PASS
```

The spec had fully converged two tasks early. The loop would have failed the run anyway,
because a no-op is scored as a failed attempt and T3 was on its last one.

## The leak: `tasks.txt`, not `verify.sh`

The per-task prompt is correctly scoped. Checked against the captured
`T2-attempt1.prompt.md`: it contains one task's text, zero characters of the other tasks,
zero characters of the gate, and the literal instruction `Implement ONLY this one task,
nothing else:`.

But the executor is an agent with read tools in the worktree, and its transcript shows:

```
Read specs/20260828g-dispatch-core/tasks.txt
```

`tasks.txt` holds all five tasks. Having read it, the executor built all five.

This is the same class of defect as an executor reading `verify.sh` (harness#23), and a
different file. **Scoping the prompt is not scoping the executor.** Any file in the worktree
that enumerates future work is a to-do list, and there are currently two of them.

## Why "changed nothing" is the wrong verdict here

The no-op rule exists to catch a lazy executor, and it is right to. But it cannot distinguish
*"did nothing"* from *"there was nothing left to do"* — and the gate, which can, was never
consulted, because the no-op check short-circuits before it runs.

An honest ordering would ask the gate first: if the task's criteria are already satisfied, a
no-op is a **pass**, not a failure. That inversion matters much more once tasks are gated
individually, since a task whose work a neighbour already did is exactly the case a per-task
gate can answer and a diff-size heuristic cannot.

## Disposition

T3–T5 were not hand-written. No code was added after `4bd0713`; the run is being closed
because it had already converged, verified by the STRICT gate above.
