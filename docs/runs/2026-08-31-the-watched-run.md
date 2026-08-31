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
into the store its own spec's sibling built. Board history, attempt logs, prompts,
diffs and gate transcripts are under `.evidence/runs/20260831a-selftest-sweep/`.

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
