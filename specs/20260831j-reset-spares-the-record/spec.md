# Spec: the failure reset spares the harness's own record

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #21
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** bash, git
- **MCP:** none
- **Permissions:** write:scripts/ralph-build.sh

---

## 1. Why · [R — Requirements]

Issue #21: after a failed attempt the loop resets the tree, and its `git clean -fd`
deletes every untracked file — including the harness's own bookkeeping. A NEW spec's
`.evidence/status/<slug>/` is untracked until its first run is merged, so the clean
takes it; PR #26 made `hb_write` recreate its own file, which fixed the symptom for
the writer that is still running, but any record nothing rewrites (another worker's
status file, an index, metrics) is simply gone. A cleanup that cannot distinguish
"the executor littered" from "the harness's own record" is the wrong shape — the
litter is the executor's, the record is ours. ADR-001 D6 gives it teeth: a worker
whose records vanish is a run that cannot classify itself.

## 2. Outcomes (Definition of Done) · [O — Outcomes]

1. The three-step failure reset (index reset, checkout, clean) lives in ONE helper,
   used by both callers: the verify-failure path and the scope-violation path.
2. Its `git clean` spares the loop's fixed bookkeeping set — `.evidence/status`,
   `.evidence/metrics.jsonl`, `.evidence/index-*`, `.evidence/runs` — the same set
   `_scope_violations` already excludes, for the same reason.
3. Executor litter outside that set is still removed (the clean still cleans).

## 3. Entities · [E — Entities]

The reset: `git reset -q -- .` + `git checkout -- .` + `git clean -fd`. The
bookkeeping set: paths the loop itself writes during an attempt. Litter: any other
untracked path the executor created.

## 4. Approach · [A — Approach]

`git clean -e <pattern>` adds gitignore-style excludes; one `-e` per bookkeeping
path. Factoring the helper makes the exclude list single-sourced, so the scope
path cannot drift from the verify path (which is exactly how #23's shape was
reintroduced once already).

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/ralph-build.sh` — a `_reset_tree` helper and its two call sites.

### Out of scope
`git checkout -- .` semantics for TRACKED bookkeeping (the next `hb_write`
rewrites the status file; harmless); `.gitignore` policy; hb_write's mkdir
(already landed in #26).

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- `git clean -fd` without `-x` already respects `.gitignore`, which is why
  `.evidence/runs/` (ignored) survives today; the bookkeeping set must survive
  even in a consumer repo whose `.gitignore` does not mention it.
- Post-#26, `hb_write` recreates its OWN status file after a clean — so the gate
  must plant a status file the running loop will never rewrite (another worker's)
  to observe the deletion.

## 7. Norms · [N — Norms]

Comments in the file's existing voice; the helper's comment cites issue #21 and
the litter-vs-record distinction.

## 8. Safeguards · [S — Safeguards]

The clean must NOT gain `-x` or lose `-d`; the positive control (litter still
removed) is gate-checked so the excludes cannot silently swallow the clean.

## 9. Task breakdown · [O — Operations]

- T1: `_reset_tree` with the bookkeeping excludes; both reset sites call it.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When an attempt fails and the tree is reset, untracked bookkeeping shall survive:
  another worker's `.evidence/status/<slug>/…` file (ac1), `.evidence/index-*.jsonl`
  and `.evidence/metrics.jsonl` (ac2).
- The reset shall still remove executor litter — untracked files and directories
  outside the bookkeeping set. (ac3)
- The loop's output shall not say `Removing .evidence/…`; the probe's positive
  control is the same output saying it removed the litter. (ac4)
- The failing run shall still exit 2 (the failure path actually ran). (ac5)
- `clean -fd` shall appear exactly once in ralph-build.sh — the helper is the only
  definition, so both paths share it. (ac6)
- `bash -n` shall pass. (ac7)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. The fixture runs the REAL
ralph-build.sh (20260831c idiom) with a stub executor that litters and never
satisfies the gate; bookkeeping is planted AFTER the fixture commit so it is
untracked, exactly like a new spec's first run. The 20260831d gate is the
regression control for the scope-violation reset.

## 12. Open questions

None.

## 14. Tuning log

- (none yet)
