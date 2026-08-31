# Spec: the loop runs from a snapshot — a self-edit cannot corrupt the run

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #48
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** bash, git
- **MCP:** none
- **Permissions:** write:scripts/ralph-build.sh

---

## 1. Why · [R — Requirements]

Issue #48: bash reads a running script incrementally and remembers a byte offset. A
spec whose task targets `scripts/ralph-build.sh` rewrites the file WHILE bash is
executing it; bash's next read resumes at the old offset in displaced content — mid
line, mid word — and runs whatever fragment it finds. Observed 2026-08-29
(`20260829b-resume-bound`): the task passed and committed, then the loop died on a
fragment of a comment (`last: command not found`) and exited 2 — **a false red after
the work succeeded**, inviting exactly the wrong response (re-running the "failed"
task). Nondeterministic by nature: it depends on where the edit lands relative to
the read offset.

## 2. Outcomes (Definition of Done) · [O — Outcomes]

1. On entry the loop copies its scripts directory to a run-local snapshot and
   re-execs from the snapshot; the copy bash reads is never the copy in the
   worktree. The issue's first direction — chosen over the wrap-in-a-function
   trick, whose protection one stray top-level statement silently removes.
2. The executor still edits the worktree's copy (the deliverable); a run whose
   task rewrites `ralph-build.sh` in place completes cleanly: exit 0, commit
   landed, no `command not found`/`syntax error` fragments.
3. The snapshot is removed when the run ends; `RALPH_NO_SNAPSHOT=1` skips the
   snapshot (debugging escape hatch).

## 3. Entities · [E — Entities]

The snapshot: `mktemp -d` under `$TMPDIR`, a full copy of `$(dirname "$0")` (the
sibling scripts — bound.sh, ralph-status.sh, loop-index.py — resolve inside it
naturally). The guard: `RALPH_SNAPSHOT` in the environment marks the re-exec'd
process; the EXIT trap removes the directory.

## 4. Approach · [A — Approach]

A block right after `set -uo pipefail`, before anything else reads the file's
later regions: absent `RALPH_SNAPSHOT`, copy and `exec bash <snapshot>/<self>
"$@"`. Cleanup folds into the existing `hb_tick_stop` trap — a second EXIT trap
would silently replace the first.

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/ralph-build.sh` — the snapshot block and the trap line.

### Out of scope
Other entry points (`run-loop.sh` invokes this file and inherits the protection);
scripts invoked as separate processes mid-run (read atomically at invocation, not
by saved offset); protecting the EXECUTOR from editing files it should not touch
(that is the per-task scope guard, 20260831d).

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- The corruption needs a SAME-INODE write (truncate + rewrite); a rename swap
  leaves bash reading the old inode via its open fd. Editors and `>` redirection
  do same-inode writes — the fixture must too, or it tests nothing.
- `$0`, `$_SD`, and `$(dirname "$0")` all resolve into the snapshot after the
  re-exec; that is what makes the sibling-script references safe, not a hazard.
- The existing trap is `trap 'hb_tick_stop' EXIT INT TERM` — extend, don't add.

## 7. Norms · [N — Norms]

The block's comment tells the observed 2026-08-29 story in the file's voice.

## 8. Safeguards · [S — Safeguards]

Snapshot failure is fatal up front (a loop that silently ran unprotected would
reintroduce the bug only on the days it matters); the control fixture pins that a
normal run still passes end-to-end under the snapshot.

## 9. Task breakdown · [O — Operations]

- T1: snapshot-and-re-exec block + trap extension in ralph-build.sh.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When a fixture task rewrites the running loop script in place (same inode, a
  ~24KB prefix inserted), the run shall exit 0. (ac1)
- The run's output shall contain no `command not found` and no `syntax error`. (ac2)
- The task's commit shall land and the WORKTREE copy shall carry the edit. (ac3)
- With `TMPDIR` pointed at a fixture-local dir, no `ralph-snap.*` directory shall
  remain after the run (cleanup). (ac4)
- A control fixture with no self-edit shall still pass end-to-end. (ac5)
- `bash -n` shall pass. (ac6)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. The fixture repo carries its own
copy of the harness scripts (`cp -R` of the real `scripts/`), so the stub edits the
fixture's running copy, never this repo's. Red today: the same-inode rewrite makes
the fixture loop die on displaced fragments.

## 12. Open questions

None.

## 14. Tuning log

- **2026-08-31 (authoring):** the first implementation cleaned the snapshot only via the
  existing `hb_tick_stop` EXIT trap — installed hundreds of lines into the file — so
  every early exit (missing spec files, validation's exit 3) leaked a snapshot; two
  showed up in `$TMPDIR` after one regression sweep. A minimal cleanup trap is now armed
  immediately after the re-exec; the later trap replaces it and carries the same rm
  (bash keeps ONE trap per signal — both sites must know about each other). Gate grew
  ac4b: an early-exit run leaves no `ralph-snap.*` behind.
