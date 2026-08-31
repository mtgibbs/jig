# Spec: monolithic multi-task specs are refused outright — the hatch is gone

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #91
- **Owner:** Matt (direction 2026-08-31: "if they don't match our convention, they
  should just instantly get kicked out"; spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** bash, git
- **MCP:** none
- **Permissions:** write:scripts/ralph-build.sh, write:specs/TEMPLATE.md,
  write:the b/c/h gates + their spec Tuning logs

---

## 1. Why · [R — Requirements]

Two threads converge here.

**The hatch.** 20260831b deprecated the monolithic multi-task shape but left
`RALPH_ALLOW_MONOLITHIC=1` as a legacy re-run escape. Matt's direction closes it:
a spec that does not match the convention is refused, full stop. No env var makes
the dead shape runnable.

**The guard.** Issue #91's last residual was the no-op work check: its
`':!.evidence'` exclusion blinds it to a deliverable under `.evidence/`, and a
SINGLE-task spec still hit it (per-task specs were already exempted by 20260831c).
The guard's only remaining audience was the hatch's legacy runs — the per-task
shape's gates are no-op-proof (pend banned, empty tree fails), and a single-task
spec's one gate run is STRICT (task 1 of 1 is the last task), so an honest gate
refuses an empty tree with better feedback than the guard's generic hint. With the
hatch gone the guard protects nobody: it is DELETED, not narrowed, and the
.evidence blind spot goes with it.

## 2. Outcomes (Definition of Done) · [O — Outcomes]

1. `_validate_task_gates` refuses a multi-task spec without `tasks/` uncondition-
   ally — exit 3, before any executor, naming the per-task convention.
   `RALPH_ALLOW_MONOLITHIC` is not consulted; the variable is gone from the file.
2. The no-op guard is deleted. A single-task spec whose deliverable lives under
   `.evidence/` completes; a single-task no-op attempt still fails — via its
   STRICT gate.
3. The b/c/h gates that pinned the hatch or the guard are updated with Tuning log
   entries; `specs/TEMPLATE.md` states the unconditional rule.
4. Single-task and per-task specs are untouched (the regression sweep is the
   control).

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/ralph-build.sh` (validator + guard deletion); `specs/TEMPLATE.md` §gate
layout; gates/Tuning logs of 20260831b, 20260831c, 20260831h.

### Out of scope
Re-running the ~30 legacy monolithic specs through the loop (they are DONE; their
gates still run directly via `bash verify.sh`, which needs no loop); migrating
them to per-task layout (a separate effort if ever wanted).

## 6. Facts the implementer must know · [S — Structure]

- The refusal must stay BEFORE any executor dispatch and before the heartbeat
  loop — exit 3 is "spec needs attention".
- `_task_satisfied`'s multi-task-monolithic branch (returns unanswerable) becomes
  unreachable through the loop but stays as defense in depth.
- Legacy gates invoked DIRECTLY (`bash specs/<old>/verify.sh`) are unaffected —
  the refusal lives in the loop, not in the gates.

## 9. Task breakdown · [O — Operations]

- T1: hatch removal + guard deletion in `scripts/ralph-build.sh`.
- T2: `specs/TEMPLATE.md` states the unconditional rule.
- T3: b/c/h gate reworks + Tuning log entries.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

Per task; each maps to that task's gate.

**T1** — When a multi-task spec has no `tasks/` dir, the loop shall exit 3 before
any executor runs, EVEN WITH `RALPH_ALLOW_MONOLITHIC=1` set (ac1); a task whose
deliverable lives under `.evidence/` shall pass with the deliverable committed
(ac2); the guard's and hatch's strings shall be absent from ralph-build.sh (ac3);
an empty attempt shall still fail via its gate (ac4); `bash -n` (ac5).

**T2** — `specs/TEMPLATE.md` shall state the refusal, say no override exists, and
name no escape variable.

**T3** — The 20260831b/c/h gates shall run green against the hatchless loop, and
each spec's Tuning log shall cite 20260831p.

## 11. Verification

Per-task layout (20260828i): `tasks/T01..T03/*/verify.sh`, cumulative in the loop;
the spec-level `verify.sh` is convergence-only — it runs the union of the task
gates. The 20260831 sweep is the regression control.

## 12. Open questions

None.

## 14. Tuning log

- **2026-08-31 (authoring):** the first draft of THIS spec was itself the defect it
  closes — five deliverables crammed into one task line to ride the single-task
  exemption (one gate, no `tasks/`). Matt caught it: "this looks monolithic … if
  something ends up as a single task, just make it fit the shape anyways." Restructured
  to the full per-task layout, and the convention now reads: every spec carries
  `tasks/T<NN>-<slug>/verify.sh`, single-task included. The exemption rewarded finding
  the fastest way around the eval loop, which is exactly what a harness must not do.
