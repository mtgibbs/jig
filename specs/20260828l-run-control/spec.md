# Spec: resume, retry, and the seam a run-control surface hangs on

Tools: python3 bash git
MCP: none
Permissions: read, write, bash

## 1. Why · [R — Requirements]

A stopped loop cannot be picked up again. `ralph-build.sh` iterates `tasks.txt` from the top on
every invocation — no resume, no start-at, no notion of a task already being satisfied. Restarting
a run whose first two tasks are **already committed** re-runs them, the executor correctly does
nothing, and the no-op guard scores that as failure three times before stopping on a task that was
finished before it began (`harness#30`).

The no-op guard runs **before** the gate, so it cannot tell *"the model did nothing"* from
*"there was nothing left to do."* Those are opposite situations with one signature.

The practical cost is that **an operator cannot safely interrupt a loop** — including to fix a
defect in the loop's own gate, which is precisely when interrupting is most necessary. It happened
twice on 2026-08-28: both times the fix was to branch from `main`, cherry-pick, and re-run the
whole spec, paying again for every completed task.

**And it is worse in the fleet.** An evicted or rescheduled worker restarts from task 1 against a
repo that already holds its own earlier commits, and reads its own completed work as laziness.

### What makes this solvable now

Resume needs one question answered: *is task N already done?* Under a monolithic gate that has no
sound answer — task 1's gate passing says nothing about **task 1**. Under per-task gates
(`20260828i`, merged) it is one gate run. **The prerequisite landed; this is the payoff.**

### The surface this belongs to

Resume is one verb. The others a run needs — **retry**, **stop**, **pause** — are the same shape,
and the constraint that decides all of them is that **nothing can connect into a worker**. A loop
in a container has no published port; a loop in a k8s Job has an ephemeral name and then ceases to
exist. So a control cannot be *sent* to a worker; the worker must **notice** it.

That is how the systems this resembles actually work: a GitHub Actions runner and a GitLab runner
both poll outbound and discover cancellation while polling. Nothing dials the agent. This spec
builds the local half — the decisions a worker makes about what to skip and what to re-run — and
shapes it so a polled control source drops in without changing the decisions.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. Before invoking the executor for task N, a spec with per-task gates checks whether task N's gate
   already passes; if so the task is **skipped**, with no executor call and no attempt consumed.
2. A skipped task is announced and heartbeated as satisfied — never silently absent.
3. A spec **without** per-task gates behaves exactly as today. The question is unanswerable there
   and must not be guessed.
4. `RALPH_FORCE_FROM=<n>` re-runs task n and everything after it regardless of gate state — the
   mechanism a "retry from here" control needs.
5. `RALPH_FORCE_ALL=1` disables skipping entirely.
6. Nothing here can make a loop pass a task whose gate is not green.

## 3. Entities · [E — Entities]

### 3.1 "Satisfied" is a gate result, not a bookkeeping record

A ledger of completed tasks would be a second source of truth that can disagree with the tree —
and after a `git reset`, a cherry-pick, or a human edit, it *will*. The gate is already the
authority on whether a task's criteria hold. Asking it is both cheaper and impossible to desync.

This is also why Outcome 3 is a hard boundary rather than a nicety: with one gate for the whole
spec, "the gate is green" means the spec is done, not that task N is. Skipping on that basis would
mark every remaining task satisfied and report success having done nothing — the false green this
whole arc exists to prevent, one level up.

### 3.2 Ask before, not after

`harness#30` proposed scoring a no-op whose gate is green as a satisfied task. Checking **before**
the executor runs is strictly better: no attempt is spent, no transcript is written, and the
"did nothing" / "nothing to do" ambiguity never arises because the executor is never called.

### 3.3 The control seam

The decisions live here; the *source* of a control does not. A later spec adds a polled source
(`HARNESS_CONTROL_URL`) and a local file for laptop use. What this spec must guarantee is that the
decision points exist and are cheap to reach: **between tasks** and **between attempts** are the
two places a worker can act on an intent without abandoning work in progress.

## 4. Approach · [A — Approach]

One predicate and one branch. `_task_satisfied <n>` runs task n's gate and reports; the task loop
consults it immediately after `HB_TIDX` is incremented and before the attempt loop. Overrides are
environment variables, matching every other knob in this file.

Bound the gate invocation, as everywhere else: a gate that hangs while being asked "is this
already done?" must not wedge a resume.

## 5. Scope · [S — Structure: boundary]

### In scope
- the satisfied-task predicate, the skip, `RALPH_FORCE_FROM`, `RALPH_FORCE_ALL`, docs.

### Out of scope
- **A terminal phase on the heartbeat.** It already works: `ralph-build.sh` writes `stopped` or
  `done` at every graceful ending, which the gate confirmed at baseline before this task was cut.
  What remains of `harness#22` is the *killed* case — a process cannot write its own last word —
  and that needs a supervisor calling `hb_mark`, which is a different mechanism.
- The polled control source and the pause/stop verbs — they need a coordinator, and this spec must
  stay runnable on a laptop with no infrastructure.
- Any change to what a gate means or when the convergence gate runs.
- Migrating monolithic specs (Outcome 3 leaves them exactly as they are).

## 6. Prior decisions / facts the implementer must know · [S]

| fact | source | consequence |
|---|---|---|
| gates resolve per task, cumulatively, only when `tasks/` exists | `ralph-build.sh` `run_gates` | the predicate is answerable only for those specs |
| a per-task gate has no `pend`; it FAILS until its task is built | `20260828i` §2.3 | an unbuilt task's gate is red, so nothing is skipped on a fresh run |
| the no-op guard runs before the gate | `ralph-build.sh` ~182 | it cannot distinguish did-nothing from nothing-to-do; do not try to fix it there |
| a function whose last construct is a loop returns that loop's terminating status | observed, `20260828i` T2 | write `return 0` explicitly |
| `hb_write` is best-effort and must never fail a run | `ralph-status.sh` | the terminal phase is stamped the same way |

## 7. Norms · [N — Norms]

1. **Name the states a check must tell apart** (`specs/amendments.md`). *Satisfied*, *not yet
   built*, and *unanswerable because the spec is monolithic* are three states, and the third must
   never be collapsed into the first.
2. Bound every gate invocation, with an explicit branch for the call that never returned.
3. A skip is announced. Work that silently does not happen is indistinguishable from work that
   silently failed.
4. Never let a control decision make a red gate look green.

## 8. Safeguards · [S — Safeguards]

- The predicate answers **false** for any spec without `tasks/`, and false when the gate cannot be
  run at all. Both are fail-closed: the task runs.
- `RALPH_FORCE_ALL=1` is the escape hatch when a human wants the work redone regardless.
- The skip consults the gate for **task n only**, never the cumulative group: the cumulative rule
  exists to catch regressions after work is done, and using it here would let a later task's
  failure prevent an earlier task from being recognised as complete.

## 9. Task breakdown · [O — Operations]

Three tasks. See `tasks.txt`. The predicate and the skip are ONE task: a predicate nothing calls
has no observable behaviour, so its gate would have nothing to assert — the same defect that made
`20260828k`'s T3 ungateable on first writing.

## 10. Acceptance criteria (EARS) · [O]

Per-task criteria live in `tasks/T<NN>-*/verify.sh`. The spec-level gate holds end-state only.

- **AC-END-1** Given a spec with per-task gates whose first tasks are already complete, when the
  loop is re-run, then those tasks shall be skipped and the loop shall proceed to the first
  incomplete task.
- **AC-END-2** Given a spec with no `tasks/` directory, the loop's behaviour shall be unchanged.

## 11. Verification (the harness)

Per-task gates, driven by the same fixture shape `20260828i` uses: a throwaway git repo with a
stub executor, so "did the executor get called" is observable rather than inferred.
