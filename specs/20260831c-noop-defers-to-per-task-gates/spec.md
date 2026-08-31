# Spec: the no-op guard defers to per-task gates

- **Status:** Done v1.0 — 2026-08-31, operator-built (one-condition loop fix on the
  rerun's critical path)
- **Owner:** Matt (spec by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, bash
- **MCP:** none
- **Permissions:** write:scripts/ralph-build.sh

---

## 1. Why · [R — Requirements]

The loop's no-op check refuses any attempt whose diff is empty outside `.evidence/`
(`git status --porcelain -- . ':!.evidence'`). The exclusion keeps the indexer's writes
from counting as work — and blinds the check to a task whose deliverable legitimately
lives under `.evidence/`. `20260831a-selftest-sweep`'s T2 (`.evidence/README.md`) was
unwinnable in both watched runs for exactly this reason, independent of the overshoot
(issue #91, first half).

The guard's reason to exist is the **pend-staged** gate: an empty tree satisfies every
pend, so a blocked executor would "pass" having written nothing (observed 2026-08-12,
specs/model-watch). A **per-task** gate cannot be satisfied by an empty tree — `pend` is
banned from task gates (20260828i outcome 3), so an empty attempt fails its own gate with
criteria-specific feedback. Where the gate is no-op-proof, the guard is redundant on the
honest path and wrong on the `.evidence/` path. Let the gate decide.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. When a spec carries per-task gates (`tasks/` exists), the empty-diff refusal does not
   run — an empty attempt proceeds to its task gate and fails there, with the gate's
   feedback.
2. A per-task task whose only change is under `.evidence/` (its declared deliverable) can
   pass — the blind spot is gone where gates are no-op-proof.
3. Monolithic (legacy) specs keep the refusal verbatim — same line, same message.

## 3. Entities · [E — Entities]

Stateless — the change is one guard condition in `scripts/ralph-build.sh`.

## 4. Approach · [A — Approach]

Add `[ ! -d "$SPEC_DIR/tasks" ]` to the existing no-op condition. No new mechanism, no
refactor of the check itself (the scrub's rule: the legacy path stays the same line, so
it cannot drift). The gate feedback an empty per-task attempt now gets is *better* than
the generic "changed nothing" hint — it names the failing criteria.

## 5. Scope · [S — Structure: boundary]

### In scope
The one condition in `scripts/ralph-build.sh`, and its comment.

### Out of scope
The second #91 residual (`add -A` attribution); any change to gates or the refusal
message; the monolithic path's behavior.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

The check today (ralph-build.sh, after the stillborn guard):

```bash
if [ -z "$(git -C "$ROOT" status --porcelain -- . ':!.evidence' 2>/dev/null)" ]; then
```

becomes

```bash
if [ ! -d "$SPEC_DIR/tasks" ] \
   && [ -z "$(git -C "$ROOT" status --porcelain -- . ':!.evidence' 2>/dev/null)" ]; then
```

with the comment extended to say why per-task specs skip it (gate is no-op-proof; the
`.evidence/` deliverable case; issue #91; this spec).

## 7. Norms · [N — Norms]

Comment in the file's own voice, dated, citing the watched-run doc and #91.

## 8. Safeguards · [S — Safeguards]

- The monolithic path must be byte-identical in behavior (maps to ac3).
- An empty per-task attempt must still FAIL — via its gate, never pass by default
  (maps to ac1's fixture).

## 9. Task breakdown · [O — Operations]

- T1: the condition + comment, per §6.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When a per-task spec's attempt changes nothing, the loop shall not print the no-op
  refusal and the attempt shall fail by its task gate's output instead. (ac1)
- When a per-task task's attempt changes only a path under `.evidence/` that its gate
  asserts on, the task shall pass. (ac2)
- When a monolithic spec's attempt changes nothing, the loop shall refuse it with the
  existing no-op message. (ac3)
- `bash -n` shall pass on the edited file. (ac4)

## 11. Verification — `verify.sh`

Single-task spec: one spec-level gate, no pend. Fixture repos through the real loop with
stub executors: one that writes nothing (per-task → gate feedback, no refusal message;
monolithic under the legacy hatch → refusal message, the positive control that the probe
still fires), and one that writes only `.evidence/note.md` with a task gate that greps it
(passes → ac2, the blind spot's death certificate).

## 12. Open questions

None.
