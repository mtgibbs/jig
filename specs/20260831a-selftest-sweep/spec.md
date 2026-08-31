# Spec: the selftest sweep — one command records every mutant corpus

- **Status:** Done v1.0 — executed 2026-08-31 by the local qwen loop, coordinator-watched
  (the deferred OQ2 of issue #84: make the recorded sweep one command). Two runs; the full
  story, including the false pass the STRICT endgame caught and the T2 scope-overshoot, is
  `docs/runs/2026-08-31-the-watched-run.md`. Note for the record: T2's README bullet landed
  inside T1's commit (executor overshoot + `add -A`), so T2 finished as an unwinnable no-op
  with the whole-spec gate already green.
- **Owner:** Matt (spec by Claude; executor: qwen via opencode, watched by the coordinator)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, bash, python3, jq
- **MCP:** none
- **Permissions:** write:scripts/selftest-sweep.sh, write:.evidence/README.md

---

## 1. Why · [R — Requirements]

Recording a mutant sweep today means hand-typing six `SELFTEST_EVID=… gate-selftest.sh <dir>`
invocations and then remembering `mutant-ledger.py`. A record that takes a for-loop to produce
is a record that stops being produced. One command, discoverable and boring, is what makes the
ledger a habit instead of an event.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `scripts/selftest-sweep.sh` exists: it finds every mutant corpus in the repo, runs
   `gate-selftest.sh` on each with `SELFTEST_EVID` pointing at the repo's `.evidence/`, then
   regenerates the ledger with `mutant-ledger.py`.
2. `--dry-run` prints what it would run and runs nothing.
3. The exit code tells the truth: 0 only when every corpus came back clean AND the ledger
   regenerated; any survivor/wrong-reason/hung or tool failure makes the sweep exit 1 — but the
   ledger is still regenerated first, because a red sweep is exactly when the record matters.
4. `.evidence/README.md` documents the command.

## 3. Entities · [E — Entities]

A **corpus** is any directory `specs/<slug>/tasks/<task>/mutants/`; the unit the tool runs on
is its parent `specs/<slug>/tasks/<task>/`. Today there are 6 corpora; the script must
enumerate, never hardcode.

## 4. Approach · [A — Approach]

A thin orchestrator in the shape of the repo's other operator scripts: resolve sibling scripts
relative to `$0` (the `_SD` pattern of `scripts/ralph-build.sh` line 52), enumerate with
`find`, delegate everything to the two tools that already exist. No new logic about mutants —
`gate-selftest.sh` owns verdicts, `mutant-ledger.py` owns rendering.

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/selftest-sweep.sh` (new file) and one bullet in `.evidence/README.md`.

### Out of scope
Any change to `gate-selftest.sh`, `mutant-ledger.py`, or any gate; wiring this into loop
phases or CI; running the real sweep (a human runs it after review).

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- Script skeleton contract (each line is load-bearing; the gate checks the behaviors, and the
  worked example below was tested by the spec author):

  ```bash
  #!/usr/bin/env bash
  set -uo pipefail
  _SD="$(cd "$(dirname "$0")" && pwd)"
  R="$(cd "$_SD/.." && pwd)"
  ```

- Enumeration, exactly this shape (sorted, so runs are comparable):

  ```bash
  find "$R/specs" -type d -name mutants -path '*/tasks/*' | sort
  ```

  and the corpus to hand the tool is `$(dirname …)` of each hit.
- Dry-run output format, one line per corpus, repo-relative:
  `would run: specs/<slug>/tasks/<task>` — and nothing else runs (no `gate-selftest.sh`,
  no ledger, no writes).
- Real-run banner per corpus before invoking the tool: `== specs/<slug>/tasks/<task>`.
- The tool invocation: `SELFTEST_EVID="$R/.evidence" bash "$_SD/gate-selftest.sh" "<dir>"`.
  Track the worst exit code across corpora; do not stop at the first red — a sweep reports
  the whole board.
- The ledger step, after ALL corpora, regardless of red or green:
  `python3 "$_SD/mutant-ledger.py" --evid "$R/.evidence" --out "$R/.evidence"` — its failure
  also makes the sweep exit 1.
- Portability floor (constitution): bash 3.2 — no arrays needed here, no `mapfile`, no
  `timeout` (bounds live inside `gate-selftest.sh` already).

§6 carries T1's deliverable only. T2's payload deliberately lives in §6b — a task's anchor
section holds nothing but that task's own work (Tuning log, and the run doc's lesson 6).

## 6b. T2's anchor — the README bullet · [S — Structure]

Referenced by T2 and only T2. The `.evidence/README.md` bullet, verbatim, appended to the
"What lives where" list after the `mutant-ledger.{md,html}` bullet:

```
- `scripts/selftest-sweep.sh` (run from anywhere) records every corpus above in one
  command and regenerates the ledger; `--dry-run` lists what it would run
```

## 7. Norms · [N — Norms]

Header comment in the file's own voice: what it is, the one-line usage, why exit codes are
truthful (Outcome 3's sentence is fine to adapt). No color, no spinner, no cleverness.

## 8. Safeguards · [S — Safeguards]

- The script must never write outside `$R/.evidence` (maps to ac3's fixture assertion).
- `--dry-run` must be write-free (maps to ac2).
- A red corpus must not abort the sweep before the ledger regenerates (maps to ac4).

## 9. Task breakdown · [O — Operations]

- T1: write `scripts/selftest-sweep.sh` per §6 — the `_SD`/`R` resolution, the find-based
  enumeration, `--dry-run`, the per-corpus banner + tool invocation with `SELFTEST_EVID`,
  worst-exit tracking, the unconditional ledger step, truthful exit. `chmod +x`.
- T2: append the §6b bullet to `.evidence/README.md`, verbatim, in the stated position.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- The repo shall contain an executable `scripts/selftest-sweep.sh` that passes `bash -n`. (ac1)
- When invoked with `--dry-run`, the script shall print one `would run:` line per corpus,
  matching an independent `find` of `specs/*/tasks/*/mutants` exactly, at least 6 of them, and
  shall invoke no tool and write nothing. (ac2)
- When invoked in a repo whose corpora are all clean, the script shall leave one
  `selftest-<slug>.jsonl` row-set per corpus and a regenerated `mutant-ledger.{md,html}` in
  that repo's `.evidence/`, and exit 0. (ac3)
- If a corpus contains a surviving mutant, the script shall still regenerate the ledger and
  shall exit non-zero. (ac4)
- `.evidence/README.md` shall contain the §6b bullet. (ac5)

## 11. Verification — per-task gates (converted 2026-08-31)

`tasks/T01-sweep-script/verify.sh` carries ac1–ac4 (as ac01–ac04) and
`tasks/T02-readme-bullet/verify.sh` carries ac5 (as ac05); no `pend` anywhere. The
spec-level `verify.sh` is convergence-only (integration: dry-run agrees with an
independent find; end state: the README documents the command). Each task gate ships a
mutant corpus — T01's five mutants are qwen's actual observed bugs from the watched runs
(the stripped `specs/` prefix, the never-invoked tool, abort-on-red, exit-0-over-a-
survivor, plus a syntax break), T02's two are the dropped and mispositioned bullet. All
seven KILLED at conversion. The original monolithic pend-staged gate this replaced lives
in git history (see Tuning log).

## 12. Open questions

None.

## 14. Tuning log

- **2026-08-31 — T1 implemented T2's payload.** As authored, the README bullet lived in §6,
  the very section T1's task line anchored to ("per spec §6"), so the executor — reading the
  whole spec by design — implemented everything its anchor contained: script *and* bullet.
  `add -A` swept the bullet into T1's commit, T2 arrived with nothing left to do, and the
  no-op protection correctly refused an empty diff until the loop stopped fail-closed over an
  already-green tree (`docs/runs/2026-08-31-the-watched-run.md`, lesson 6). Fix applied here:
  the bullet moved to §6b, referenced by T2 and only T2, and §6 now states the rule — **a
  task's anchor section holds nothing but that task's own deliverables.** The task line
  anchors harder than the spec (TEMPLATE §11 corollary); this is the authoring-side half of
  the guard until diff-scoping exists on the build loop.
- **2026-08-31 — converted to the per-task layout (20260828i).** This spec was authored in
  the monolithic pend-staged shape three days after the house deprecated it, because the
  TEMPLATE still taught the old shape — the full forensics are
  `specs/20260831b-scrub-monolithic-gates/`. The conversion gives each task its own gate
  and mutant corpus (seven mutants, all KILLED, five of them qwen's real observed bugs),
  slims the spec gate to convergence-only, and rides 20260831c (the no-op guard defers to
  per-task gates) so T2's `.evidence/` deliverable finally counts as work.
- **2026-08-31 — the rerun: authoring can't close the hole.** With the §6b split in place,
  a stripped-tree rerun overshot anyway: the executor ran the gate mid-task, read
  `pend ac5 … (not built yet)` as a to-do, and implemented T2's bullet during T1 — naming
  T2 as it did so. The spec stopped leaking; the pend-staged gate advertised the payload
  instead. Two leak paths, same destination: the atomicity guard must be harness-side
  (task-scoped staging or a diff-scope check), not spec-side. Run record:
  `docs/runs/2026-08-31-the-watched-run.md`, postscript.
