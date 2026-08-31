# Spec: the task-scope guard — a declared scope, enforced before the gate

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes the surviving half of issue #91
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, bash
- **MCP:** none
- **Permissions:** write:scripts/ralph-build.sh, write:specs/TEMPLATE.md

---

## 1. Why · [R — Requirements]

Issue #91's surviving half. The per-task layout made overshoot benign (skip-satisfied
absorbs it) and #93 let `.evidence/` deliverables count as work — but `add -A` still
sweeps ANY stray write into the current task's commit, the ledger attributes it to the
wrong task, and nothing stops an executor touching genuinely unrelated files. Rerun2
showed it in miniature: T1 ran the live sweep to test its script and committed 1,100
lines of ledger churn that belonged to no task.

The guard is harness-side by prior finding (`docs/runs/2026-08-31-the-watched-run.md`,
lesson 6 + correction): two watched runs proved spec authoring alone cannot hold the
task boundary.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A task MAY declare its scope: `$SPEC_DIR/tasks/T<NN>-<slug>/scope`, one git pathspec
   glob per line (repo-relative; `#` comments and blank lines ignored).
2. When a scope exists, the executor's prompt states it (prevention before punishment).
3. When a scope exists and an attempt changes any path outside it, the attempt fails
   BEFORE the gate runs: targeted feedback naming the offending paths and the scope,
   full tree reset. Never filter-the-commit — stripping files could commit a task whose
   gate went green because of them.
4. The loop's own bookkeeping writes (`.evidence/status/`, `.evidence/metrics.jsonl`,
   `.evidence/index-*`, `.evidence/runs/`) never count as violations.
5. A scope file with zero globs is refused up front (exit 3, spec-needs-attention) —
   a scope that matches nothing makes every attempt a violation.
6. No scope file → behavior byte-for-byte unchanged. Opt-in, superset, not a migration.
7. `specs/TEMPLATE.md` §11 documents the file.

## 3. Entities · [E — Entities]

A **scope** is the set of repo-relative git pathspec globs a task's attempt may touch.
A **violation** is any changed path (tracked or untracked, staged or not) matching none
of them, bookkeeping excluded.

## 4. Approach · [A — Approach]

Pure git, no hand-rolled glob matching: the complement is computed with
`git status --porcelain -- . ':(exclude)<glob>'...` — one exclude per scope line plus
the fixed bookkeeping excludes. Whatever remains changed is out of scope. Helpers follow
the `_gate_for` idiom; `set --` builds the exclude list inside a function so positional
params stay local (bash 3.2, no arrays — constitution floor).

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/ralph-build.sh` (the guard) and `specs/TEMPLATE.md` §11 (one paragraph).

### Out of scope
Scope files for any existing spec; monolithic specs (deprecated shape gets no new
features); commit filtering of any kind; changing the `add -A` commit itself.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- Placement: the check runs in the attempt loop AFTER the stillborn guard and BEFORE
  `hb_write verifying` — a gate must never judge a tree containing out-of-scope work.
- The violation path mirrors the existing verify-failure path exactly: `LOG_OUTCOME`
  recorded (outcome string `scope`), `hb_write failed false`, feedback set, then the
  same three-step tree reset (`reset -q -- .`, `checkout -- .`, `clean -fd -- .`),
  then `continue` to the next attempt.
- `_scope_for <n>` resolves like `_gate_for` (two-digit zero-padded `ls` glob, `head -1`);
  returns 1 when the task dir or its `scope` file is absent.
- Validation lives in `_validate_task_gates`' per-task loop: an existing scope file with
  no effective lines fails validation (exit 3 via the existing `|| exit 3`).
- The prompt already says "Do not touch anything outside this task's scope"; with a
  scope file that sentence gets teeth — append the actual globs to the prompt.
- Porcelain paths: strip the two status chars + space; renames print `old -> new`,
  acceptable as-is in feedback.

## 7. Norms · [N — Norms]

Comment the guard in the file's own voice, stating the one thing the code can't:
why violation means reject-wholesale rather than filter-the-commit. House comment
density; no new dependencies.

## 8. Safeguards · [S — Safeguards]

- The guard must reject the WHOLE attempt on violation — in-scope work in the same
  attempt is discarded too (ac3).
- The unscoped path must be untouched (ac4 control).
- Bookkeeping writes must not trip the guard (implicit in every green fixture — the
  loop writes status files during each run).

## 9. Task breakdown · [O — Operations]

- T1: implement `_scope_for`, `_scope_violations`, the validation rule, the prompt
  injection, and the pre-gate check in `scripts/ralph-build.sh`; document the scope
  file in `specs/TEMPLATE.md` §11.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When a scoped task's attempt changes only in-scope paths, the run shall pass with no
  scope rejection. (ac1)
- If a scoped task's attempt changes a path outside its scope, the loop shall fail the
  attempt before the gate, name the offending path in output, leave the attempt
  uncommitted, and reset the tree. (ac2)
- If an attempt contains both in-scope and out-of-scope changes, the loop shall reject
  it wholesale — the in-scope work is also discarded, never committed. (ac3)
- When no scope file exists, the run shall behave exactly as today (control). (ac4)
- When a scope exists, the executor's prompt shall contain its globs. (ac5)
- If a scope file contains no globs, the loop shall refuse to start with exit 3. (ac6)
- `scripts/ralph-build.sh` shall pass `bash -n`. (ac7)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend (20260828i exemption — one task needs
no staging). Fixtures run the REAL `ralph-build.sh` with stub executors, in the idiom of
`specs/20260831c-noop-defers-to-per-task-gates/verify.sh`; markers and prompt copies
live OUTSIDE the fixture repos because the loop's failure path runs `git clean -fd`.

## 12. Open questions

None. (Auto-deriving scope from a task's gate was considered and rejected: a gate reads
files it must not write, so read-scope and write-scope differ; explicit declaration is
smaller than inference and honest about being opt-in.)

## 14. Tuning log

- **2026-08-31 — bash 3.2 ate the guard silently.** First implementation built the
  exclude list with `set -- "$@" ...` inside a `set -u` script: bash before 4.4 (macOS
  ships 3.2) treats an EMPTY `"$@"` as an unbound variable, the function died
  mid-command-substitution, `_viol` came back empty, and the guard never fired — while
  every downstream ac2 assertion still passed because the fixture gate failed for its
  own reasons. The gate caught it only because ac2 also asserts the rejection MESSAGE.
  Fix: the `${1+"$@"}` idiom, both expansion sites. Lesson kept: a guard's gate must
  probe the guard's own voice, not just the state it leaves behind — the state can be
  right by coincidence.
