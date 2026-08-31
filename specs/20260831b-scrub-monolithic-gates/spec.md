# Spec: scrub the monolithic gate — the TEMPLATE must teach the convention we ratified

- **Status:** Done v1.0 — 2026-08-31, operator-built (doctrine work, not loop-fodder)
- **Owner:** Matt (spec by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, bash
- **MCP:** none
- **Permissions:** write:specs/TEMPLATE.md, write:specs/amendments.md,
  write:scripts/ralph-build.sh, write:docs/runs/2026-08-31-the-watched-run.md

---

## 1. Why · [R — Requirements]

`20260828i-per-task-gates` replaced the monolithic pend-staged gate for multi-task specs and
named its defects — including defect 2, "the gate is the roadmap": an executor reads the
whole-spec gate, sees a later task's `pend`, and does that task's work early. Ten specs
adopted the layout the same week.

Three days later, `20260831a-selftest-sweep` was authored in the old shape anyway, and
defect 2 recurred on schedule — twice, across two watched runs
(`docs/runs/2026-08-31-the-watched-run.md`). The author (Claude) worked from
`specs/TEMPLATE.md`, which still taught the pend-staged monolithic gate at length — twice,
a fenced copy-paste block and a duplicate comment — and never mentioned `tasks/T<NN>-*/`
once. **The doctrine document contradicted the ratified convention, so the convention lost.**
Any agent authoring from the TEMPLATE reproduces the deprecated shape; the owner's words:
"any agent coming in will make the same dumbass mistake."

A convention that lives only in the spec that ratified it is not a convention. It must live
where authors copy from (the TEMPLATE), where law lives (an amendment), and where it can be
enforced (the loop refuses the dead shape).

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `specs/TEMPLATE.md` §11 teaches the per-task layout as THE shape for multi-task specs;
   the pend-staged monolithic doctrine is reduced to a short legacy note for readers of old
   gates, and the copy-paste pend preamble is gone.
2. `scripts/ralph-build.sh` refuses to build a multi-task spec that has no `tasks/`
   directory — exit 3 (the spec needs attention), message naming the convention —
   with `RALPH_ALLOW_MONOLITHIC=1` as the explicit escape hatch for re-running the
   ~30 legacy specs.
3. `specs/amendments.md` carries the deprecation as law.
4. The run doc's rerun postscript is corrected: "spec authoring cannot close this" was
   half-right — the house had already closed it structurally in 20260828i, and the failure
   was authoring in a shape the house had deprecated. What remains genuinely open is
   tracked in an issue, not overstated in the record.

## 3. Entities · [E — Entities]

The two gate shapes, named precisely so the scrub is scoped:

- **Per-task layout (the convention):** `tasks/T<NN>-<slug>/verify.sh` per task; the loop
  runs gates 1..N cumulatively; `pend` is banned from task gates; the spec-level
  `verify.sh` holds only convergence/integration assertions and runs under STRICT at the
  end; every task-gate assertion is named by a mutant (20260828i outcomes 1–6).
- **Monolithic pend-staged gate (deprecated):** one whole-spec `verify.sh` run after every
  task, `pend` deferring later tasks' checks. Legal only for **single-task** specs — with
  one task there is no later work to advertise and no pend to write — and for the legacy
  population, which is never edited retroactively.

## 4. Approach · [A — Approach]

Three small edits, one per surface where the convention must live: the TEMPLATE (where
authors copy from), `_validate_task_gates` in ralph-build.sh (where the loop already
validates spec shape up front — the refusal goes in the same function, same exit-3
contract), and amendments.md (where law accumulates). Plus the record correction. The
timeless gate craft in the TEMPLATE — Traps A/B/A-prime, the one-question test, the
near-miss practice, semantically-rich task lines, the anchor rule — is layout-agnostic
and stays.

## 5. Scope · [S — Structure: boundary]

### In scope
`specs/TEMPLATE.md` §11/§11b, `scripts/ralph-build.sh` (`_validate_task_gates` only),
`specs/amendments.md` (one new amendment), the run doc correction.

### Out of scope
Migrating any legacy spec (the #73 class — separate, issue-tracked); the diff-scope
residuals that survive the per-task layout (the `.evidence/` no-op blind spot and `add -A`
commit attribution — issue-tracked, see §6); `run-loop.sh`, bindings, judges,
`gate-selftest.sh`.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- The refusal lives in `_validate_task_gates`, which already exits 3 for a per-task spec
  with a missing gate. New rule, checked first: no `tasks/` dir AND `_task_count` > 1 AND
  `RALPH_ALLOW_MONOLITHIC != 1` → refuse, in the house voice, naming 20260828i and the
  escape hatch. Single-task specs and per-task specs pass through untouched; the legacy
  escape hatch prints a one-line warning so a reader of the run knows it was deliberate.
- Skip-satisfied (`ralph-build.sh`, 20260828l) is the reason overshoot is benign in the
  per-task shape: task N's own gate already green → skipped gracefully. This belongs in
  the TEMPLATE's why, one sentence.
- What the per-task layout does NOT fix (goes in the issue, not the TEMPLATE): the no-op
  work check excludes `.evidence/` wholesale, so a task whose deliverable lives there
  reads as "changed nothing" even when done perfectly; and `add -A` still sweeps any
  stray writes into the current task's commit, so per-task attribution can lie.
- The anchor rule from 20260831a's Tuning log graduates to the TEMPLATE: a task's anchor
  section holds nothing but that task's own deliverables.
- The granularity rule (this session, ratified by the owner asking the question): tasks
  share a spec when they share a gate and a design; anything else is either the same task
  or a different spec.

## 7. Norms · [N — Norms]

Amendment in the existing amendments.md voice (statement, Status line, Rationale with the
observed cost). TEMPLATE edits keep the golden-rule tone and the measured-example style —
cite the watched-run doc the way existing blocks cite model-watch and notes-from-hearing.

## 8. Safeguards · [S — Safeguards]

- The refusal must not change behavior for single-task specs, per-task specs, or any run
  setting the escape hatch — the legacy population stays runnable (maps to ac2/ac3).
- The gate-craft content of TEMPLATE §11 (Traps, one-question test, near-miss practice)
  must survive the rewrite — the scrub removes the dead layout, not the living craft
  (maps to ac5).

## 9. Task breakdown · [O — Operations]

- T1: all four edits per §2 — single atomic task; they share one gate and one design, and
  splitting doctrine from its enforcement is how doctrine and enforcement drift apart.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When `ralph-build.sh` is pointed at a multi-task spec with no `tasks/` directory and
  `RALPH_ALLOW_MONOLITHIC` unset, it shall exit 3 before invoking any executor, naming the
  per-task convention. (ac1)
- When the same spec is run with `RALPH_ALLOW_MONOLITHIC=1`, and when any single-task or
  per-task spec is run, the refusal shall not fire. (ac2)
- `bash -n` shall pass on the edited `ralph-build.sh`. (ac3)
- `specs/TEMPLATE.md` shall document the per-task layout (`tasks/T<NN>-<slug>/verify.sh`,
  cumulative gates, no `pend` in task gates, mutants, convergence-only spec gate) and
  shall not contain the pend-preamble copy block ("do NOT write a two-verdict gate"). (ac4)
- `specs/TEMPLATE.md` shall retain the gate-craft blocks (Trap A, Trap B, Trap A-PRIME,
  the one-question test). (ac5)
- `specs/amendments.md` shall carry the deprecation amendment; the run doc shall carry the
  correction. (ac6)

## 11. Verification — `verify.sh`

Shipped in this directory. Single-task spec, so a single spec-level gate with no `pend`
anywhere is the correct shape (§3). ac1/ac2 run the real `ralph-build.sh` against mktemp
fixture spec dirs (physical paths) with a stub `RALPH_EXEC_CMD` that drops a marker file —
the marker's absence proves the refusal fired before any executor ran, and its presence
under the escape hatch is the positive control that the probe can fire. ac4's absence
assertion gets its positive control from the red-before-green record (the phrase present
pre-edit, gone post-edit — `evidence/red-before-green.txt`).

## 12. Open questions

None. The residuals and the legacy migration are issues, not questions.

## 14. Tuning log

*(empty — first authoring)*
