# Spec: `gate-selftest` — prove a gate can fail, and finish the per-task migration

Tools: python3 bash git
MCP: none
Permissions: read, write, bash

## 1. Why · [R — Requirements]

`20260828i` landed the *structure* — `ralph-build.sh` resolves `tasks/T<NN>-*/verify.sh`
cumulatively, and `specs/lib/assert.sh` deliberately has no `pend`. It did **not** land the part
that makes the structure worth having: the rule that **every assertion is named by at least one
mutant it must reject**, and the tool that enforces it.

Without that tool the rule is a habit, and habits are exactly what failed. Across
2026-08-27/28, **nine** defects were found in gates that had been written and reviewed — and
**every one was found by running the gate, none by reading it**. Three of them could not fail for
any input at all.

This spec is also the **first consumer of per-task gates**. That is not decoration. Its
predecessor's T2 bundled four separate changes into one task, no single change could take the
monolithic gate green, and the executor moved sideways for five attempts across two runs before a
human wrote it. Under per-task gates each task here is judged on its own criteria and nothing
else, which is the failure mode this whole arc exists to remove — so the spec that completes the
mechanism is the one that runs under it.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `scripts/gate-selftest.sh <task-dir>` exists and never modifies the tree it is pointed at.
2. Each file under `<task-dir>/mutants/` declares `MUTANT:` (the assertion id it must break),
   `TARGET:` (the repo-relative path it replaces) and `WHY:`. A mutant missing `MUTANT:` or
   `TARGET:` is an **error**, never a skip.
3. A mutant is **killed** only when the gate exits non-zero **and** reports a failure for the
   assertion id that mutant declares. Those are two requirements, not one.
4. A mutant the gate accepts is a **survivor** and is the tool's headline failure.
5. Every assertion id in the gate is declared by at least one mutant, or the run fails naming the
   uncovered id.
6. A task gate containing the token `pend` fails the run.
7. `20260828g-dispatch-core` is migrated to the per-task layout with a mutant corpus, as the
   reference instance, and every task gate passes against the merged implementation.
8. Nothing here runs on the loop's critical path.

## 3. Entities · [E — Entities]

### 3.1 The mutant

```python
# MUTANT: ac2
# TARGET: scripts/dispatch/dispatcher.py
# WHY: records the event id before checking it, so a replayed event launches twice.
```

A complete replacement artifact plus a declaration of what it must break.

### 3.2 Why the verdict has two parts

A mutant that fails the gate **for a different reason than it declared** proves nothing about the
assertion it claims to cover, and counting it as a kill leaves exactly the unfalsifiable assertion
the tool exists to detect.

This is not hypothetical. It happened twice while validating `20260828j`'s gate by hand:

- a mutant patched the 401 branch of `list_runs`, but the assertion exercised `run_status`, which
  has its own branch — **the mutant never ran the code the assertion tests**;
- a mutant removed an explicit `return 0` from a `for`-loop function, but the trap being modelled
  belongs to `while read` — a different construct, so the defect did not reproduce.

Both **looked like weak assertions and were mutants that missed.** A tool scoring only "did the
gate fail" would have sent the author rewriting correct checks. Hence: report `KILLED`,
`SURVIVED`, and `WRONG-REASON` as three distinct outcomes.

### 3.3 Coverage is the half mutation cannot self-check

A surviving mutant says an assertion is too weak. Nothing about the mutants says an assertion is
**missing**. The uncovered-id check is the cheap, deterministic half of that question — an id the
gate asserts that no mutant exercises has never been observed to work. The other half, *"which
acceptance criterion has no assertion at all"*, no mutant can answer and is out of scope here.

## 4. Approach · [A — Approach]

Bash and `python3`, matching the rest of `scripts/`. Operate on a **copy** of the repository in a
temp directory: a self-test that leaves a mutant behind poisons the very next scope check, and
several specs assert that the tree is untouched outside their own files.

Every gate invocation is bounded by `timeout` with a distinct outcome for the call that never
returned — a mutant that makes the gate **hang** is a finding in its own right, and reporting it
as a failure would hide it.

## 5. Scope · [S — Structure: boundary]

### In scope
- `scripts/gate-selftest.sh`; migrating `20260828g-dispatch-core`; `docs/per-task-gates.md` and
  the `specs/TEMPLATE.md` update.

### Out of scope
- Wiring self-test into `ralph-build.sh`. A mutant corpus that can block a running loop becomes a
  new way to fail correct work. CI and on-demand only.
- Migrating any other existing spec. The fallback keeps them working (`20260828i` AC-1).
- A `gate-quality` LLM validator for **coverage of the criteria**. Different question, different
  repo, later.
- Fixing `harness#30` (a stopped loop replays committed tasks as no-ops). Its fix — *a no-op whose
  gate is green is a satisfied task* — is only safe once per-task gates are in USE, because under
  one shared gate it marks every remaining task satisfied and reports success having done nothing.
  This spec is what puts them in use; the fix comes after it, not with it.

## 6. Prior decisions / facts the implementer must know · [S]

| fact | source | consequence |
|---|---|---|
| `specs/lib/assert.sh` defines `ok` and `no`, and no `pend` | `20260828i` T1 | task gates source it; the `pend` ban is enforceable by token |
| gates run cumulatively 1..N after task N | `ralph-build.sh` `run_gates` | a task gate must keep passing as later tasks land |
| a task gate has no `pend`, so it FAILS until its task is built | `20260828i` §2.3 | that is expected, not a broken gate |
| gates must not litter the tree they measure | `20260825a` ac6 | temp clone; `PYTHONDONTWRITEBYTECODE=1` |
| several specs assert out-of-scope files are untouched | `20260801a`, `20260802a`, `20260818b` | a stray mutant fails an unrelated spec's gate |
| a function whose last construct is a loop returns that loop's terminating status | `20260828i` T2, observed | write `return 0` explicitly |

## 7. Norms · [N — Norms]

1. **Name the states a check must tell apart** (`specs/amendments.md`). Killed, survived,
   wrong-reason and hung are four states; collapsing any two of them is the defect.
2. Never guard an assertion on the answer it asserts.
3. Bound every call into the thing under test, with an explicit branch for the call that never
   returned.
4. A failure message carries the evidence it captured — the mutant's `WHY:`, the gate's own output.
5. Validate against an artifact you did not author.

## 8. Safeguards · [S — Safeguards]

- The tool refuses to run if it would write outside its temp copy.
- A survivor is the headline: it must be impossible to read a run summary and miss one.
- No silent caps. If the tool skips a mutant for any reason, it says so and fails.

## 9. Task breakdown · [O — Operations]

Eight tasks, each one unit of work — deliberately smaller than `20260828i`'s, whose T2 bundled
four changes and could not be completed in one move. See `tasks.txt`.

## 10. Acceptance criteria (EARS) · [O]

Each task's criteria live in its own `tasks/T<NN>-*/verify.sh`. The spec-level `verify.sh` holds
only the end-state and integration assertions and runs at convergence, under `STRICT`.

- **AC-END-1** The tool leaves the working tree byte-identical after a full run.
- **AC-END-2** Running the tool over the migrated `20260828g` reports every mutant killed, every
  id covered, and exits zero.
- **AC-END-3** Every `20260828g` task gate passes against the merged implementation on `main`.

## 11. Verification (the harness)

`tasks/T<NN>-<slug>/verify.sh` per task, sourcing `specs/lib/assert.sh` and this spec's
`lib/fixtures.sh`. **No task gate contains `pend`** — the vocabulary does not define it, and T05's
own check would fail the run.
