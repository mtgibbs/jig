# The operator edited the tree a live loop was running in, and the loop committed it as the model's

**Date:** 2026-08-28 · **Run:** `.evidence/runs/20260828h-dispatch-api/e061d942c900/qwen-984536`

## What happened

The executor's record for this spec is clean:

| attempt | verdict | |
|---|---|---|
| T1-1 | FAIL | 9 PASS / 2 FAIL |
| T1-2 | FAIL | 6 PASS / 5 FAIL — a regression |
| T1-3 | **PASS** | **12 PASS / 0 FAIL** |

T1 attempt 3 delivered a correct 181-line `api.py`: `501` for evidence, an inline `subprocess`
delete for cancel, and — unlike attempt 1 — **no edit to `dispatcher.py`**, which the Touches
section forbids. It passed the whole gate.

I did not see that. Two failures of my own instrumentation stacked:

1. **My liveness check never matched anything.** I polled with
   `grep -qla 'ralph-build.sh specs/20260828h' /proc/*/cmdline`. `/proc/<pid>/cmdline` is
   **NUL-separated**, so a pattern containing a literal space cannot match it. The check reported
   "LOOP ENDED" every time it ran, including while the loop was mid-attempt. The first such report
   happened to be true, which is why it went unnoticed.
2. **I read a truncated log tail** and concluded the loop had failed all attempts.

Acting on that, I overwrote `scripts/dispatch/api.py` — *in the worktree the loop was still running
in* — with a hand-finished version built from attempt 1's output. The loop then reached T2, saw a
green gate, and committed my hand-written code as **`ralph(qwen): T2 — add the run-creation
route`** at 14:31:40. Git history credited the model with the operator's work, in a repository
whose entire purpose is measuring what the model can do unaided.

## Why it matters more here than elsewhere

Contaminated provenance is not a tidiness problem in this repo. `loop-index.py` parses
`ralph(<agent>):` back out of the git log, and the metrics derived from it are the evidence for
every claim about executor capability. One mislabelled commit makes that record say the opposite of
what happened: it credits the model for work it did not do, in the same run where it would have
hidden that the model *had* succeeded on its own.

## Correction

The branch was reset to the executor's own `b8c3e0a` (T1, unmodified), my `api.py` rewrite was
discarded in favour of it, and only `docs/dispatch-api.md` and the `scripts/dispatch/README.md`
pointer — which are genuinely mine — were committed separately. The gate passes 12/12 under STRICT
on that combination.

## The rule this makes concrete

**Never edit the worktree a loop is running in.** It was already known that the loop's
between-attempt cleanup *reverts* uncommitted operator edits — that had eaten a gate fix twice
earlier the same day. This is the other half: when the edits happen to make the gate green, the
loop *keeps* them and signs them with the model's name. Reverting is loud. This is silent.

Use `git worktree add` for any operator edit while a loop is live, and if a liveness check is what
tells you it is safe, verify the check itself matches something — a check that can only ever say
"clear" is not a check.
