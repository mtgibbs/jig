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
- The `.evidence/README.md` bullet, verbatim, appended to the "What lives where" list after
  the `mutant-ledger.{md,html}` bullet:

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
- T2: append the §6 bullet to `.evidence/README.md`, verbatim, in the stated position.

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
- `.evidence/README.md` shall contain the §6 bullet. (ac5)

## 11. Verification — `verify.sh`

Shipped in this directory, pend-staged for the loop (T1 arms ac1–ac4, T2 arms ac5). The
behavioral checks run against mktemp fixture repos carrying the REAL tools (copied in) and
one-mutant corpora — a clean one for ac3, a surviving one for ac4 (which doubles as the
positive control that the sweep's exit code and the tool's verdicts can actually go red).

## 12. Open questions

None.
