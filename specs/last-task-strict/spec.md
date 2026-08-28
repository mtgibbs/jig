# Spec: the last task's gate is the strict gate

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor qwen)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, sed
- **MCP:** none
- **Permissions:** write:scripts/ralph-build.sh, write:specs/TEMPLATE.md, exec:git
- **Touches:** `scripts/ralph-build.sh` (the per-task gate call), `specs/TEMPLATE.md` (the STRICT
  note). **No change** to any `verify.sh`, to `ralph-log.sh`, `ralph-status.sh`, `run-loop.sh`, or
  to the `pend` contract itself.

---

## 1. Why · [R — Requirements]

`ralph-build.sh:192` runs the per-task gate with the ambient environment; `:275` runs the final
one as `STRICT=1`. A `pend` therefore **cannot fail the retry loop**, and a task can report `✓`
having done nothing the gate can see.

Measured, twice, on 2026-08-27:

| spec | task | reported | actually |
|---|---|---|---|
| `evidence-replayable` | T7 | `✓ T7 … passed verify` | `ac15` unbuilt — `ralph-judge.sh` never touched |
| `spec-manifest` | T3 | `✓ T3 … passed verify` | `ac6`–`ac13` unbuilt — eight of its own ACs |

Both were caught only by the post-loop STRICT check, which runs **after the loop has stopped
retrying** — so the executor was never once told it was wrong. In both cases, re-running that same
task with `STRICT=1` exported made it converge **on the first attempt**. The executor was never
the problem; the feedback was empty.

The fix is not "run everything strict". Applied from T1 that promotes every *later* task's `pend`
to a failure and no early task can ever pass — which is precisely why the lenient gate exists.
The pathology is bounded to one place.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. The **final** task's per-task gate treats `pend` as failure.
2. Every **earlier** task's gate does not — a mid-spec `pend` still means "a later task owns this".
3. A task that fails this way retries with the still-red AC text in its feedback, through the
   existing feedback path, so the executor can act on it.
4. `verify.sh` is still invoked exactly **twice** in `ralph-build.sh`
   (`specs/evidence-replayable` AC-4 asserts the literal count; a third call site doubles every
   gate's side effects).
5. The final post-loop STRICT check stays exactly as it is — this narrows the gap, it does not
   replace the backstop.
6. A reader of the run log can tell which mode the gate ran in.
7. No `verify.sh` changes, anywhere. 119 `pend` call sites across 12 gates are untouched.

## 3. Entities · [E — Entities]

No data model. One decision, computed per task inside the existing loop:

| name | value | source |
|---|---|---|
| "is this the last task" | `HB_TIDX` equals `HB_TOTAL` | `ralph-build.sh:132` increments `HB_TIDX`; `ralph-status.sh:84` sets `HB_TOTAL` from the non-blank line count of `tasks.txt` |
| the gate's mode | `STRICT=1` on the last task, `STRICT=0` otherwise | passed as an assignment **prefix on the existing call** |

`HB_TOTAL` may be absent or `0` if the status layer never initialised. That is not a licence to
guess: when it cannot be determined, the mode is **lenient**, because a false "last task" would
fail every earlier task and stop the run — the loud wrong answer, not the safe one.

## 4. Approach · [A — Approach]

Prefix the existing gate call with the computed mode. Same shape as `:275`, which already proves
the mechanism works: `STRICT=1 bash "$VERIFY"`.

The literal `bash "$VERIFY"` count must stay at 2 — AC-4 strips comments and counts that exact
string, so the mode has to ride as an assignment prefix on the call that is already there, never
as a second branch with its own call.

**Rejected: tagging every `pend` with its owning task** (`pend T4 "ac7: …"`, promoted by
`STRICT_TASK`). It is the fully general answer and it is not worth it here: 119 call sites across
12 gates, all of which would need re-reading and re-validating, to fix a pathology that both
observed instances hit at exactly one position. Position is a proxy for ownership, and at the last
task it is an exact one — there is no later task for a `pend` to be deferred to. The general
version stays available if a mid-spec instance ever shows up.

**Rejected: exporting `STRICT=1` for the whole run.** §1 covers why. It is recorded here because
it is the first thing anyone reaches for, and it was the first thing I reached for.
