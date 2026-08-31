# Spec: a finished single-task spec resumes as a skip, not a no-op death

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #30
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, bash
- **MCP:** none
- **Permissions:** write:scripts/ralph-build.sh

---

## 1. Why · [R — Requirements]

Issue #30: a stopped loop could not resume — completed work re-read as a no-op and
burned every attempt. For multi-task specs the per-task layout closed this
(skip-satisfied, 20260828l; actually working on macOS since #98, proven by 20260831g's
gate: everything committed → restart → skip → exit 0). The residual is the
**single-task spec**, which by the 20260828i exemption has no `tasks/` directory —
`_task_satisfied` calls the question unanswerable and a resumed, finished single-task
spec still dies as a no-op ×3. Interrupting a loop is most necessary when its own gate
needs fixing; the operator must be able to do it on every spec shape the convention
allows.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A single-task spec whose spec gate passes under STRICT on the committed tree is
   skipped on resume; the run completes 0 without invoking the executor.
2. The question is answered under STRICT: a legacy pend-staged gate that is only
   lenient-green must NOT read as satisfied (fail-closed — the task runs).
3. A multi-task monolithic spec (the `RALPH_ALLOW_MONOLITHIC=1` escape hatch) remains
   unanswerable: never skips, exactly as today.
4. An unfinished single-task spec still dispatches the executor (no false skip).

## 3. Entities · [E — Entities]

`_task_satisfied`'s early monolithic return; `$VERIFY` (the spec-level gate), which for
a single-task spec IS the task's gate.

## 4. Approach · [A — Approach]

In `_task_satisfied`, replace the unconditional "no `tasks/` → unanswerable" return
with: unanswerable only when `_task_count > 1`; for one task, resolve the gate to
`$VERIFY` and run it with `STRICT=1` through the same `bound` path. Everything else in
the function (force flags, bound, exit-status verdict, refusal messages) is shared
unchanged.

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/ralph-build.sh`, `_task_satisfied` only.

### Out of scope
The no-op guard; `run_gates`; the STRICT endgame; skip-satisfied for per-task specs.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- STRICT is how legacy gates promote `pend` to FAIL; without it a pend-staged gate is
  green on an empty tree and a lazy resume would skip real work. Per-task gates ignore
  STRICT entirely, so the env var is set only on the single-task path.
- The verdict stays the gate's EXIT STATUS, never a grep of its output (the function's
  own standing rule).

## 7. Norms · [N — Norms]

Comment states the one non-obvious thing: why STRICT, and why multi-task monolithic
stays unanswerable (a green whole-spec gate only says the SPEC is done, not task N).

## 8. Safeguards · [S — Safeguards]

- No false skips: ac2 (unfinished) and ac3 (lenient-only green) both must dispatch.
- The escape-hatch legacy path must be byte-for-byte behavior-identical (ac4).

## 9. Task breakdown · [O — Operations]

- T1: extend `_task_satisfied` per §4.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When a single-task spec's gate passes under STRICT on the committed tree, a re-run
  shall skip the task and exit 0 without invoking the executor. (ac1)
- When a single-task spec's gate fails on the committed tree, the loop shall dispatch
  the executor (no false skip). (ac2)
- If a single-task gate is green only leniently (red under STRICT), the loop shall NOT
  skip it. (ac3)
- While `RALPH_ALLOW_MONOLITHIC=1`, a multi-task monolithic spec shall never skip. (ac4)
- `scripts/ralph-build.sh` shall pass `bash -n`. (ac5)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. Fixtures run the real loop with stub
executors and out-of-repo markers (the loop's failure path runs `git clean -fd`).

## 12. Open questions

None.

## 14. Tuning log

- (none yet)

- **2026-08-31 (spec 20260831p):** ac4 used `RALPH_ALLOW_MONOLITHIC=1` to reach the
  multi-task-monolithic skip question; that hatch is removed, so the shape is refused
  before dispatch. ac4 keeps the never-skips probe and now also pins the up-front
  refusal (exit 3, no executor).
