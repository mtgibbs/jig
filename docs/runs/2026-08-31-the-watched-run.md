# The watched run — five defects in one evening, and the strict gate that caught the lie

**Date:** 2026-08-30/31 · the first coordinator-watched laptop loop, dogfooding
`specs/20260831a-selftest-sweep` (qwen via opencode, board on `:8877`, operator: Claude).
Two runs. The second one shipped the feature. The first one was worth more.

## Run 1 — a false pass, manufactured by the operator

- **The executor had no hands.** The global opencode config says `"bash": "ask"`, and
  headless opencode auto-rejects `ask`. qwen read the spec, planned correctly, and was
  refused its first `find`. Attempt 1: no-op, correctly failed. (This is jig#70's
  quickstart gap manifesting live: nothing in the repo provisions loop permissions.)
- **The operator fix corrupted the no-op signal.** Dropping `opencode.jsonc` into the
  worktree MID-ATTEMPT made the tree differ, which is all the no-op detector measures. It
  cannot tell executor writes from anyone else's. Attempt 2 was rejected on every tool
  call and still got credited: the lenient pend-staged gate saw all-pend, exit 0.
- **The loop committed the operator's file as the task's work.** `ralph(qwen): T1 — …`
  contained a status JSON and the operator's config, because `opencode.jsonc` was never
  actually gitignored — the "gitignored opencode.json" comment the scripts carried was
  stale. Fixed on this branch: the ignore entry now exists.
- **STRICT caught it at the endgame.** T2 is the final task, so its gate promoted T1's
  four pends to FAIL. qwen — with working permissions by then — appended T2's README
  bullet and was still refused, three times, on work that was never its to fix. The loop
  stopped fail-closed. **The three-verdict design held: a lie survives a lenient
  mid-run gate for exactly as long as there are later tasks, and not one check longer.**

Operator rules this buys: **never touch a loop's worktree mid-attempt**, and seed
permissions before launch. Harness candidates it names: a no-op detector scoped to the
executor's own writes, and task-scoped staging instead of `add -A`.

## Run 2 — the gate against real code, and a scope overshoot

Reset to the spec commit, config seeded pre-launch.

- **Attempt 1 was real work with real bugs**, and the gate discriminated all three:
  `--dry-run` stripped one path segment too many (`specs/` missing), real mode never
  invoked the tool, and a red corpus aborted before the ledger step (§8's safeguard).
  One check — "a survivor makes the sweep exit non-zero" — **passed for the wrong
  reason** (the script exited 1 for being broken); its two companion checks caught it,
  which is why absence assertions travel in packs.
- **Attempt 2 stalled reading the repo** and the 480s watchdog killed it: a finding
  reported as HUNG-shaped, not inherited as a wedge.
- **Attempt 3 fixed all three findings from the gate's feedback.** T1 green, 14 PASS,
  committed. The retry-with-feedback contract earned its keep on the first real defect
  cycle.
- **Then the overshoot:** qwen had also appended T2's README bullet during T1, and
  `add -A` swept it into T1's commit. **T2 arrived with nothing left to do**, and the
  no-op protection — the same rule that failed run 1's attempt 1 honestly — refused an
  empty diff three times. The loop stopped fail-closed over a tree whose STRICT gate
  was already green. Per-task accounting broke; the work did not.

## Where it ended

`STRICT=1 verify.sh` → exit 0, 14 PASS. The operator reviewed the 46-line script,
approved it, and ran the first real sweep with it — the sweep recording its own corpora
into the store its own spec's sibling built.

**Correction (2026-08-31, same operator):** the raw attempt records — prompts, transcripts,
per-attempt diffs and gate outputs under `.evidence/runs/…` — did NOT survive. They are
gitignored ("bulky"), lived only inside the loop's worktree, and `git worktree remove
--force` at teardown deleted them; `~/.harness/` held no copy for these runs. What
survives is what was committed: the joined `index-20260831a-selftest-sweep.{md,jsonl}`,
the status row, the task commits' diffs, and the excerpts quoted in this document, which
were read from the live files before teardown.

## The generalizable lessons

1. **The no-op detector measures the tree, not the executor.** Anything else writing to
   the worktree — an operator, a cron, a second agent — can mint a false pass. The
   worktree-per-agent rule exists for exactly this; it must bind operators too.
2. **A stale "this file is gitignored" claim is an active hazard**, because `add -A`
   turns it into a commit. The neglect-sweep's resolver (20260830e) checks paths exist;
   nothing yet checks claimed *ignore* status. Cheap gate, real payoff.
3. **Scope overshoot steals the next task's diff.** A literal executor that does N+1's
   work during N leaves N+1 unwinnable under no-op accounting. Candidates: task-scoped
   staging, or a scope check like the judge exec's touch-only-the-finding's-file rule.
4. **Watchdog kills read as progress on the board** (attempt increments), but only the
   transcript says *stalled reading the repo*. The coordinator row should carry the
   kill reason — it already carries the attempt.
5. **Teardown eats the gitignored evidence.** `.evidence/runs/` is in-repo but ignored,
   so it exists exactly as long as the worktree does — `git worktree remove --force`
   destroyed both runs' raw records minutes after the run doc cited them. The fleet
   already has the answer (`20260828o-evidence-egress`: artifacts leave the worker as
   produced); the laptop flow needs its equivalent, or teardown needs an
   evidence-export step before the remove.
6. **Task atomicity is a convention, not a guard.** T1's task line said "per spec §6"
   and §6 carried T2's deliverable verbatim (the README bullet, quoted for T2 to copy) —
   so the executor, reading the whole spec as designed, implemented everything its
   anchor section contained. The task line anchors harder than the spec, and it anchored
   into a section holding two tasks' payloads. Spec-authoring rule: a task's anchor
   section carries only that task's deliverables. Enforcement candidate: same as
   lesson 3 — nothing in the build loop scopes what a task's diff may touch.

## Postscript — the rerun (2026-08-31): the fix held, and the overshoot came back anyway

After PR #88 moved the bullet to §6b, a rerun from a stripped tree
(branch `qwen/selftest-sweep-rerun`, coordinator-watched) tested whether T2 could now
complete clean. It could not — **for a new reason**.

- **The §6b split worked on its own terms.** T1's attempts 1 and 2 touched only
  `scripts/selftest-sweep.sh`; the spec no longer leaked T2's payload through the anchor.
- **The gate leaked it instead.** On attempt 3 the executor ran `verify.sh` itself, saw
  the pend-staged line `pend ac5: the .evidence/README.md bullet (not built yet)`, and
  wrote — verbatim in the transcript — *"All ac1-ac4 pass. Now I need to implement T2 -
  add the README bullet"*. It knew it was crossing the task boundary and crossed it,
  because a pending criterion reads as a to-do to a completionist executor. `add -A`
  swept the bullet into T1's commit (`04ce95b`), T2 no-oped three times, and the loop
  stopped fail-closed over a STRICT-green tree — byte-for-byte the run-2 ending.
- **T1's own arc repeated run 2 exactly**: attempt 1 real work with real bugs (6 FAILs),
  attempt 2 close (2 FAILs, both the red-corpus safeguard), attempt 3 green with 14 PASS.
  Retry-with-feedback converged twice out of twice.

**Lesson 6, sharpened:** spec authoring cannot close the atomicity hole. A pend-staged
whole-spec gate *advertises* every later task's pending criteria to any executor that
runs it — and executors run the gate because we tell them to. Two runs, two different
leak paths (spec anchor, then gate pend), one destination. The guard has to live in the
harness: task-scoped staging or a diff-scope check on the build loop. Until then,
per-task accounting on multi-task specs is best-effort.

**Correction (2026-08-31, same day, prompted by the owner):** the paragraph above
overstates the discovery. The gate-pend leak was not an open problem — it is defect 2 of
`specs/20260828i-per-task-gates` ("the gate is the roadmap"), structurally closed three
days earlier by the per-task layout, which bans `pend` from task gates and consults
nothing beyond task N. Both watched runs failed because **20260831a was authored in the
deprecated monolithic shape**, which `specs/TEMPLATE.md` still taught at length while
never mentioning the per-task layout at all. The doctrine document lost to the convention
it contradicted. The scrub is `specs/20260831b-scrub-monolithic-gates/`: the TEMPLATE now
teaches the layout, an amendment makes it law, and the loop refuses the dead shape
(`RALPH_ALLOW_MONOLITHIC=1` for legacy re-runs). What genuinely remains open — the
`.evidence/` no-op blind spot and `add -A` commit attribution — is issue-tracked, not a
lesson about spec authoring.

This run's raw records were exported before teardown (lesson 5, applied) to
`.evidence/runs/20260831a-selftest-sweep-rerun/`.

## Postscript 2 — run 4: the per-task shape, first try, clean

Same experiment, third rerun of the stripped tree (branch `qwen/selftest-sweep-rerun2`
off main at `9df4c31`), but the first against the **converted** spec: per-task gates
(#94), the TEMPLATE scrub live (#92), the no-op guard deferring to per-task gates (#93).

**Result: exit 0, both tasks green on attempt 1.** Every prior run needed three
attempts for T1 and died fail-closed on T2.

- **T1 held scope.** Its commit carries `scripts/selftest-sweep.sh` and nothing of
  T2's — the README bullet is absent from the diff. With no `pend ac5` line anywhere
  to read as a to-do, the executor built exactly its own task. (The commit does carry
  `.evidence/` ledger rows because qwen ran the live sweep to test its script and
  `add -A` swept the output in — the attribution half of issue #91, still open, in
  miniature.)
- **T1 went green on attempt 1**, where runs 2 and 3 both took three attempts. A
  gate that states only the current task's criteria is also a *smaller, sharper*
  target — the executor wasn't juggling five future criteria while building one.
- **T2 did real work for the first time in the experiment's history.** Skip-satisfied
  found its gate red (no absorption needed — there was no overshoot to absorb), the
  #93 deferral let an `.evidence/`-only diff count as work instead of refusing it as
  "changed nothing", and T2's own gate judged the bullet verbatim and in position.
  STRICT, attempt 1, green.
- **Independent confirmation after exit:** both task gates and the convergence gate
  re-run by hand in the worktree — rc=0 across the board; convergence saw all 8
  corpora from the repo root.

The comparison is now three runs on one side, one on the other: monolithic shape —
two different leak paths, T2 structurally unwinnable, fail-closed endings; per-task
shape — scoped commits, first-attempt greens, a T2 that exists. Defect 2 of
`20260828i` ("the gate is the roadmap") is confirmed closed in practice, not just in
fixtures. Records exported before teardown to
`.evidence/runs/20260831a-selftest-sweep-rerun2/` (loop stdout and both commits as a
patch included).
