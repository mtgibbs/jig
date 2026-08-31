# Spec: the all-skipped run survives its own STRICT stop

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #49
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, bash
- **MCP:** none
- **Permissions:** write:scripts/ralph-build.sh

---

## 1. Why · [R — Requirements]

Issue #49. `attempt` is assigned in exactly one place — the attempt loop — and the
skip-satisfied path `continue`s before that loop is entered. When EVERY task is skipped
and the final STRICT gate then fails, the stop path dereferences an unassigned `attempt`
under `set -u` and the loop dies with `unbound variable` instead of printing the failing
assertions it had just collected. It dies BEFORE `hb_write stopped false`, so the status
file freezes non-terminal — a run recorded as running that is not running (issue #22's
shape). The path is ordinary now that resume exists: re-running a spec whose tasks are
all satisfied against a convergence gate that does not pass is exactly what resume is
for.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A run whose every task is skipped and whose final STRICT gate fails exits 2 (not a
   crash), prints the gate's failing assertions, and stamps its status file terminal
   (`stopped`).
2. The record for that stop reads as "no attempt was made" — the string `skipped`, the
   same one the skip path already writes to `HB_ATTEMPT` — never a fabricated number.
3. The stop message on that path names the STRICT endgame, not "failed verify after N
   attempts" (no attempts happened).

## 3. Entities · [E — Entities]

The final-STRICT stop path at the bottom of `ralph-build.sh` (`_strict_out`), reached
after the task loop; `attempt`, assigned only inside the attempt loop.

## 4. Approach · [A — Approach]

`"${attempt:-skipped}"` at the dereference site — a default that reads as what happened,
per the issue's own analysis (0 is a real attempt number in the record; `skipped` is the
established sentinel). Fix the misleading bus/stderr message on the same path. No
refactor of the surrounding logging.

## 5. Scope · [S — Structure: boundary]

### In scope
The final-STRICT stop path in `scripts/ralph-build.sh`.

### Out of scope
The skip-satisfied mechanism; `run_gates`; the task-level stop path (its `attempt` is
always assigned); issue #22's supervisor-side marking.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- Observed 2026-08-29 on `spec/resume-bound`: single task skipped, STRICT gate failed,
  `ralph-build.sh: line 453: attempt: unbound variable`, exit 1, status frozen.
- The crash fires after `_strict_out` is captured and the `grep -E FAIL` lines print —
  the loss is the terminal stamp and the honest exit code, not the assertions.

## 7. Norms · [N — Norms]

House comment voice: state why the default is `skipped` and not 0.

## 8. Safeguards · [S — Safeguards]

- A run with real attempts that reaches the same stop path must keep recording the real
  attempt number (the default must not mask an assigned value).

## 9. Task breakdown · [O — Operations]

- T1: default `attempt` to `skipped` on the final-STRICT stop path; correct that path's
  stop message.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When every task is skipped and the final STRICT gate fails, the loop shall exit 2 with
  no `unbound variable` in its output. (ac1)
- On that path, the loop shall print the STRICT gate's failing assertions. (ac2)
- On that path, the status file shall be stamped `stopped` (terminal). (ac3)
- The run shall have announced the skip (`skipped (gate already passed)`) — the control
  proving the fixture exercises the all-skipped path, not a normal failure. (ac4)
- `scripts/ralph-build.sh` shall pass `bash -n`. (ac5)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. The fixture is a per-task repo whose
task gate is green on the committed tree (so the task skips) and whose convergence gate
always fails (so the STRICT endgame stops); the stub executor must never be invoked.

## 12. Open questions

None.

## 14. Tuning log

- (none yet)
