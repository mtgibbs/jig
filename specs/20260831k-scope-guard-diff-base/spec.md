# Spec: gate scope guards diff the working tree, not the whole branch

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #33
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** bash, git
- **MCP:** none
- **Permissions:** write:specs/20260818{a,b,c,d}*/verify.sh, write:their spec.md Tuning logs

---

## 1. Why · [R — Requirements]

Issue #33: four legacy gates (`20260818a/b/c/d`) check their spec's §5 scope with
`git diff --quiet origin/main -- <out-of-scope files>` — committed history, whole
branch. So they fire on ANY branch that legitimately edits those files for some other
spec (observed on `impl/per-task-gates-2`, where editing `ralph-build.sh` was
20260828i's entire T2 — and again live on the #21 branch today). Per the amendments,
that is a conflated-states defect: "this spec's implementer went out of scope" and
"a different spec is being built here" both read as failure, and a guard that fails
for the wrong reason trains the reader to discount it.

## 2. Outcomes (Definition of Done) · [O — Outcomes]

1. All four guards default their diff base to `HEAD` — the working-tree comparison
   `scored-gate` and `judge-loop` already use. In the loop, gates run BEFORE the
   task commit, so an out-of-scope edit by this spec's own implementer is still in
   the working tree at gate time and still caught; on any other branch the check
   clears once the change is committed.
2. The per-gate env override (`RETRY_BASE`, `LOOP_DOCTOR_BASE`, `RRG_BASE`,
   `TL_BASE`) survives — an operator can still run a deliberate history audit
   against any base.
3. The guards can still fail: a dirty tree touching an out-of-scope file fires.

## 3. Entities · [E — Entities]

The guard: `BASE="${X_BASE:-…}"` + `git diff --quiet "$BASE" -- <files>`. Base
`HEAD` = index+working tree vs last commit; base `origin/main` = the whole branch.

## 4. Approach · [A — Approach]

One line per gate: the default becomes `HEAD`. The issue's option 2 (the loop
exports the active spec) is no longer needed as the general answer — the loop-level
per-task scope guard (20260831d, issue #91) is that mechanism now, enforced at
attempt time with reject-wholesale semantics. The gate-local guard only has to stop
lying on other branches, which the base change does.

## 5. Scope · [S — Structure: boundary]

### In scope
The four `BASE=` lines (and adjacent comments); a Tuning log entry in each of the
four legacy spec.mds.

### Out of scope
The guards' file lists; the loop; hand-committed out-of-scope edits made outside
the loop on the spec's own branch (the old check "caught" those only by also firing
on every innocent branch; the per-task scope guard is the real enforcement).

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- `git diff BASE -- files` includes uncommitted changes, so base `HEAD` still sees
  everything an attempt has done when the gate runs pre-commit.
- The pend-on-unresolvable-base branch stays as written — `HEAD` resolves in any
  repo with a commit, and the env override can name anything.

## 7. Norms · [N — Norms]

Keep each gate's comment voice; the changed comment states why HEAD is the right
base (states-told-apart, not convenience).

## 8. Safeguards · [S — Safeguards]

The meta-gate proves both directions on the REAL gates, in throwaway clones: a
committed out-of-scope edit with a clean tree must pass all four; the same edit
uncommitted must fail all four.

## 9. Task breakdown · [O — Operations]

- T1: change the four defaults to HEAD, adjust comments, add Tuning log entries.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- When a clone has an out-of-scope edit COMMITTED and a clean tree, each of the
  four gates' scope check shall pass. (ac1)
- When the same edit is UNCOMMITTED, each of the four gates' scope check shall
  fail — the guard still has teeth. (ac2)
- When `LOOP_DOCTOR_BASE=origin/main` is set explicitly, the committed edit shall
  fire the guard — the history audit is still available. (ac3)
- No `:-origin/main}` default shall remain in the four verify.sh files. (ac4)
- All four gates shall pass `bash -n`. (ac5)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. The meta-gate clones this repo
into fixtures, pins the clone's `origin/main` ref to the clone's HEAD (so the only
diff is the one the fixture makes), commits/leaves-dirty the out-of-scope edits,
and greps each real gate's own `scope:out-of-scope-files-untouched` line — the
guard's own voice, not the surrounding state. The rest of each legacy gate may
pass or fail for its own reasons; only the scope line is asserted.

## 12. Open questions

None.

## 14. Tuning log

- **2026-08-31 (authoring):** two meta-gate harness bugs, both silent-empty: (1) the
  probe expanded an empty `"$@"` under `set -u` on bash 3.2 — the `${1+"$@"}` idiom,
  third sighting in this repo; (2) `env … bound …` — env(1) cannot exec a shell
  function, so `bound` must WRAP env, not follow it. Both produced `<missing>` scope
  lines; the per-check line echo is what made the difference between "the guard fired"
  and "the probe never ran" visible.
- **2026-08-31 (authoring):** `git clone --local` carries committed state only, so the
  first green run was still testing the OLD committed guards. mk_clone now syncs the
  four gates from the working tree and commits before pinning origin/main — the
  meta-gate blesses what the run actually changed, which is also what lets
  red-before-green work at all.
