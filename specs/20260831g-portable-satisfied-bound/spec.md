# Spec: skip-satisfied gets a bound that exists on every machine

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #98
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, bash, perl
- **MCP:** none
- **Permissions:** write:scripts/ralph-build.sh

---

## 1. Why · [R — Requirements]

Issue #98, found by 20260831f's control assertion. `_task_satisfied` bounds its
pre-dispatch gate run with `timeout(1)` — GNU coreutils, which stock macOS does not ship
(as `run_bounded`'s comment in the same file says, and as `scripts/bound.sh` exists to
solve since 20260828k hit the identical 127). The gate run exits 127, reads as "gate did
not pass", and skip-satisfied has never once skipped on macOS: overshoot absorption
silently does not exist on half the machines the harness runs on, and a resume re-runs
every already-satisfied task.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A task whose gate passes on the committed tree is skipped, on a machine with no
   `timeout(1)` on PATH.
2. A hanging gate is still bounded: `_task_satisfied` answers false within
   `RALPH_SATISFIED_TIMEOUT` and the task runs (fail-closed, as today's contract states).

## 3. Entities · [E — Entities]

`scripts/bound.sh` — the house portable bound; sourced, defines `bound`, runs nothing on
load, prefers real `timeout` when present, perl fallback otherwise, exit 124 on fire,
kills the process GROUP.

## 4. Approach · [A — Approach]

Source `bound.sh` next to the other sibling-script wiring (`_SD` already exists) and
replace the one `timeout` call in `_task_satisfied` with `bound`. Same shape as
`gate-selftest.sh` line 18. No behavior change where `timeout` exists.

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/ralph-build.sh`: one `. "$_SD/bound.sh"` and the `_task_satisfied` call site.

### Out of scope
`run_bounded` (its hand-rolled poll loop also serves cancel collection — not a plain
bound); `bound.sh` itself; any gate.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- `bound`'s exit contract is `timeout`'s: 124 on fire — `_task_satisfied`'s existing
  124 branch keeps working unchanged.
- `bound.sh` must be sourced AFTER `_SD` is set (line 52) and before `_task_satisfied`
  can run.

## 7. Norms · [N — Norms]

The call-site comment already explains the bound; add only the one fact that changed
(portable `bound`, not `timeout`).

## 8. Safeguards · [S — Safeguards]

- The hang contract must hold with the fallback: a gate that never finishes must not
  wedge a resume (ac2).

## 9. Task breakdown · [O — Operations]

- T1: source `scripts/bound.sh` in `ralph-build.sh`; use `bound` in `_task_satisfied`.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When a task's gate passes on the committed tree, the loop shall skip it without
  invoking the executor, with `timeout(1)` masked off PATH. (ac1)
- If a task's gate hangs, the loop shall report it did not finish within the bound and
  run the task. (ac2)
- `scripts/ralph-build.sh` shall pass `bash -n`. (ac3)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. Fixtures run the real loop with stub
executors; `timeout` is masked off PATH via a shim directory so the gate proves the
fallback on any machine, Linux CI included.

## 12. Open questions

None.

## 14. Tuning log

- (none yet)
