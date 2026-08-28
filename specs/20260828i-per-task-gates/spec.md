# Spec: Per-task gates, a shared assertion vocabulary, and mutation self-test

## 1. Why · [R — Requirements]

The harness has one gate per **spec**. `ralph-build.sh:196` runs `$SPEC_DIR/verify.sh` after
*every* task, and `:287` runs the same file again under `STRICT`. There is no per-task gate
anywhere in the harness. That single fact produces four distinct defects, all four of which were
hit in production on 2026-08-27/28:

| # | defect | observed |
|---|---|---|
| 1 | **an assertion for task N fails task M<N** | `20260828g` ac9 keyed a T5 doc assertion on a README that already existed, so its presence guard never opened and it failed a T1 that had passed ac1/ac2/ac4 on the first attempt |
| 2 | **the gate is the roadmap** | `20260828g` T2's executor read `verify.sh`, built T1–T5 in one attempt, and T3 then failed three times on "changed nothing" while `STRICT` passed all 11 assertions |
| 3 | **an unfalsifiable guard** | `20260828h` ac7 guarded its 501 assertion with `grep -q '501'` — an implementation returning 404 removed the literal, the guard read "not built yet", and the assertion **could not fail for any input** |
| 4 | **a gate that hides its own evidence** | `20260828h` folded the server's stderr into a captured field and then printed only "the server did not start"; a `NameError` at import and a port collision were the same sentence, and the executor spent all three attempts guessing |

Defects 1 and 2 are the **same** problem wearing two hats. The monolithic gate is what makes
reading it lucrative, what forces the hand-written `pend` ladder, and what lets a later task's
assertion fail an earlier one. Scoping a gate to its unit of work removes all three at once and
leaks nothing beyond the task text the executor was already given.

Defects 3 and 4 are not structural — they are **gate craft**, and they survive any layout. A
correct-looking assertion that cannot fail reports green forever, and no amount of reading catches
it reliably: *I wrote and reviewed all four of these, and found every one of them only by running
the gate against a broken artifact.* That is the argument for making mutation the gate's own
entry condition rather than an optional discipline.

> **An assertion no mutant can trip is an assertion that has never been observed to work.**
> A gate with no mutants is an untested test.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A spec MAY carry `tasks/T<NN>-<slug>/verify.sh`, one directory per task in `tasks.txt` order.
2. After task N, the loop runs the gates for tasks **1..N** — cumulative, so a later task that
   breaks an earlier one still fails, while nothing beyond task N is ever consulted.
3. A task gate asserts **only** its own task's criteria. `pend` does not exist in the per-task
   vocabulary and MUST NOT appear in a task gate.
4. Cross-task and end-state assertions live in the spec-level `verify.sh`, which runs **only** at
   convergence, under `STRICT`.
5. Every assertion in a task gate is named by **at least one mutant** that it must reject.
6. `verify.sh --self-test` installs each mutant, runs the gate, and fails if any mutant **survives**
   or if any assertion is unnamed by every mutant.
7. A spec with no `tasks/` directory behaves **exactly** as today. This is a superset, not a
   migration: no existing spec changes behaviour.
8. Nothing here can make a loop pass that would previously have failed.

## 3. Entities · [E — Entities]

### 3.1 Layout

```
specs/
├── lib/
│   └── assert.sh                     repo-wide vocabulary. Sourced, never executed. NO `pend`.
└── 20260828g-dispatch-core/
    ├── spec.md
    ├── tasks.txt                     unchanged — the loop still reads tasks from here
    ├── verify.sh                     CONVERGENCE ONLY: integration + end state. `pend` allowed.
    ├── lib/
    │   └── fixtures.sh               spec-local fixtures (mock kubectl, AST oracle, …)
    └── tasks/
        ├── T01-extract-core/
        │   ├── task.md               the task text, verbatim from tasks.txt
        │   ├── verify.sh             ONLY T1's criteria. Sources ../../lib/assert.sh.
        │   └── mutants/
        │       ├── ac1-no-dispatch.py       header declares which assertion it must trip
        │       └── ac2-ledger-ignored.py
        └── T02-run-registry/…
```

### 3.2 The mutant contract

A mutant is a **complete replacement artifact** plus a declaration of the assertion it must break:

```python
# MUTANT: ac2
# WHY: dispatch() records the event id before checking it, so a replayed event launches twice.
```

`--self-test` for each mutant: install it at the task's target path, run the gate's assertions,
require **overall FAIL** *and* require the named assertion id to be among the failures. Two
separate requirements on purpose — a mutant that fails the gate for the *wrong* reason proves
nothing about the assertion it claims to cover.

The union of every mutant's declared ids must equal the gate's assertion ids. A gate assertion
covered by no mutant is a self-test failure, because that is precisely the state defect 3 was in.

### 3.3 Why mutants and not a reviewer

A reviewer — human or model — reads the gate and reasons about whether an assertion *could* fail.
A mutant **executes** the case and observes that it *does*. Of the four defects above, mutation
catches 3 directly and 1 by construction; only defect 4 (hidden evidence) needs a separate rule,
because a swallowed diagnostic still fails correctly — it just fails uselessly. That rule is §7.

## 4. Approach · [A — Approach]

Additive and fallback-first. `ralph-build.sh` gains a resolver: if `$SPEC_DIR/tasks/` exists, the
gate for task N is the concatenation of task gates 1..N; otherwise `$SPEC_DIR/verify.sh`, exactly
as today. The convergence invocation at `:287` additionally runs the spec-level `verify.sh` under
`STRICT`, which is the only place it runs in the new shape.

`20260828g-dispatch-core` is migrated as the reference instance. It is the right choice: its five
tasks are already built and merged, so the migration can be checked against a **known-good tree**
and a known-bad one, and its 17 `pend`s are the largest sample of the defect this removes. Most of
those 17 turn out not to be deferred assertions at all — they are integration checks misfiled into
a per-task position, and they belong in §3.1's convergence gate.

## 5. Scope · [S — Structure: boundary]

### In scope
- `specs/lib/assert.sh`; the `tasks/` layout; the cumulative resolver in `ralph-build.sh`;
  `--self-test`; migrating `20260828g-dispatch-core`; documenting the shape.

### Out of scope
- Migrating any other existing spec (they keep working untouched — Outcome 7).
- Withholding future task text from the executor. The layout makes selective withholding
  *possible* for the first time — a fleet worker can be handed one task directory instead of the
  whole spec — but choosing what to withhold is a dispatcher decision and belongs with item 3.
- A `gate-quality` LLM validator in review-hub. Mutation covers falsifiability deterministically;
  the judge's distinct job is **coverage** — "which acceptance criterion has no assertion at all?"
  — which no mutant can answer. Separate spec, separate repo.

## 6. Prior decisions / facts the implementer must know · [S]

| fact | source | consequence |
|---|---|---|
| the gate runs after every task AND again at convergence | `ralph-build.sh:196,287` | both call sites must go through the resolver, or STRICT diverges from the loop |
| `STRICT=1` promotes `pend` to failure, and is set only on the final task | `20260828d-last-task-strict` | the convergence gate is the only place `pend` still means anything |
| the executor reads `verify.sh` and `tasks.txt` off disk on its own initiative | `20260828g` evidence note | the leak is filesystem access, not prompt construction — do not "fix" it in the prompt |
| a gate must not litter the tree it measures | `20260828a` ac6 | `PYTHONDONTWRITEBYTECODE=1`; self-test installs mutants in a temp clone, never in `$ROOT` |
| the loop reverts uncommitted edits in its own worktree between attempts | observed 2026-08-28 | never author a gate in the tree a loop is running in |

## 7. Norms · [N — Norms]

1. **Never guard an assertion on the answer it asserts.** A presence guard keys on the *artifact*
   that the task produces, never on the *value* the assertion is checking. (Defect 3.)
2. **Every call into the thing under test is bounded.** A gate that hangs is worse than one that
   fails: the watchdog kills the run and blames the executor. `timeout` on every invocation, with
   an explicit `rc = 124` branch that says the call did not return.
3. **A failure message carries the evidence it captured.** If the gate captured output, the FAIL
   line interpolates it. A message that names only the symptom is a message the executor cannot
   retry against. (Defect 4.)
4. **Validate against an artifact you did not author** — the executor's own output from a prior
   attempt, or the nearest real file. A stub written from the same mental model as the assertion
   proves only that the two agree.

## 8. Safeguards · [S — Safeguards]

- The resolver falls back on `$SPEC_DIR/verify.sh` whenever `tasks/` is absent, so every existing
  spec is untouched. A missing task gate for a task that exists is a **hard error**, not a skip:
  a silently absent gate is a task with no criteria at all.
- `--self-test` never writes into `$ROOT`; it operates on a temp clone.
- Self-test is not on the loop's critical path. It runs in CI and on demand — a mutant corpus that
  can block a running loop would be a new way to fail a correct attempt.

## 9. Task breakdown · [O — Operations]

See `tasks.txt`. Five tasks: the vocabulary, the resolver, the self-test runner, the reference
migration, the documentation.

## 10. Acceptance criteria (EARS) · [O]

- **AC-1** When `$SPEC_DIR/tasks/` is absent, the system shall invoke `$SPEC_DIR/verify.sh` and
  behave bit-for-bit as before.
- **AC-2** When `$SPEC_DIR/tasks/` is present and task N has just run, the system shall invoke the
  task gates for 1..N and no gate for any task after N.
- **AC-2b** When a task gate **fails**, the system shall fail that task. Added after the fact:
  every gate in the fixtures passes, so an implementation that inverts its own return code
  satisfied every other assertion while reporting a red gate as green — the one failure here
  worse than a broken loop, because it ships unbuilt work.
- **AC-2c** When task 1's gates run, they shall run lenient; strict is reserved for the last task.
  `20260828d` last-task-strict is merged behaviour this change can silently break, and if task 1
  runs `STRICT=1` every `pend` is fatal on the first task and no early task can pass.
- **AC-3** When a task listed in `tasks.txt` has no corresponding `tasks/T<NN>-*/verify.sh`, the
  system shall exit non-zero naming the missing gate, **detected up front** before any task runs —
  a missing gate found mid-loop is folded into that attempt's verify feedback and retried, so the
  message never reaches the loop's own output.
- **AC-4** The shared vocabulary shall define `ok` and `no` and shall **not** define `pend`.
- **AC-5** When any task gate contains the token `pend`, the self-test shall fail naming that gate.
- **AC-6** When a mutant is installed, the gate shall exit non-zero **and** report a failure for
  the assertion id that mutant declares.
- **AC-7** When an assertion id in a task gate is declared by no mutant, `--self-test` shall exit
  non-zero naming that id.
- **AC-8** When every mutant is rejected for its declared reason and every id is covered,
  `--self-test` shall exit zero.
- **AC-9** At convergence the system shall additionally invoke `$SPEC_DIR/verify.sh` under
  `STRICT=1`.

## 11. Verification (the harness)

`verify.sh` for this spec is itself the first consumer of §7 — every assertion is bounded, no guard
keys on its own answer, and the red case is demonstrated before the green one. The reference
migration in T4 is verified against the **merged, known-good** `dispatcher.py` (all task gates must
pass) and against the mutant corpus (each must be rejected for its declared reason).
