# Spec: 20260831v-work-mutation

- **Status:** Draft v0.1 — FOR REVIEW (the OQ2 expansion Matt called for on 20260831u's
  wrap). Builds on `20260831u`; stacked on jig PR #120.
- **Owner:** mtgibbs
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Touches:** `scripts/work-mutate.sh` (new), `scripts/ralph-build.sh`,
  `scripts/mutant-ledger.py`, `.evidence/README.md`
- **Tools:** git, bash, python3, diff
- **MCP:** none

## 1. Why · [R — Requirements]

`20260831u` closed the mechanics half: every gate now proves, in-loop, that it can fail
for the right reason against the corpus its author imagined. The named limit stands in
that spec's §1: self-authored mutants cannot test gate *conception* — a failure mode the
author never imagined gets no assertion and no mutant, and #117 lived in production for
three days on exactly that.

This spec is the author-independent attack on that bias, and the research instrument the
fleet-monitoring visualization is being built toward. Instead of asking "does the gate
reject the defects we hypothesized?", it asks "does the gate NOTICE when the work it just
blessed is damaged?" — by mechanically mutating the executor's ACTUAL committed diff and
re-running the gate against each mutation. No hypothesis, no WHY line, no author in the
loop: the work itself generates the probes. A gate that keeps passing while the work it
certified is dismantled underneath it is measurably insensitive to that work — which is
precisely the lead a researcher wants, whether or not any individual probe is a true
defect.

The posture difference from `20260831u` is load-bearing and deliberate: corpus mutants
are ENFORCEMENT (a survivor STOPs the run — a curated pill with a WHY is a claim, and a
gate that eats it is broken). Work mutations are TELEMETRY (an UNNOTICED probe never
blocks — mechanical mutation has the classic equivalent-mutant problem: dropping an inert
line SHOULD go unnoticed, and treating that as failure would teach operators to ignore
the signal entirely). Enforcement graduates only when the accumulated data says what a
threshold means (OQ1).

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `scripts/work-mutate.sh <task-dir> [--commit <sha>]` exists: hermetic working-copy at
   the commit (gate-selftest's copy discipline), generates up to a budget of mutations
   from that commit's own diff, runs the task's gate bounded per mutation, prints one
   verdict line each — `NOTICED` (gate exited non-zero), `UNNOTICED` (gate passed the
   damaged work), `HUNG` — plus a summary. It never modifies the real tree and exits 0
   unless the tool itself errs: verdicts are data, not failure.
2. Two curated operators in v1, both language-agnostic and derived from the diff itself:
   **revert-one-hunk** (undo one hunk of the commit) and **drop-one-added-line** (delete
   one line the commit added, skipping blank and comment-only lines). No random token
   mutation — a probe must correspond to a legible "part of the work went missing" story,
   or an UNNOTICED verdict tells the researcher nothing.
3. Selection is DETERMINISTIC: probes are ordered and sampled by a seed derived from the
   commit sha, so a row in the ledger can be reproduced by re-running the tool at that
   commit. A budget (`RALPH_WORK_MUTANTS`, default 4, `0` disables) caps cost on large
   diffs.
4. The loop runs it at the same moment trust is minted: after a task's first green, after
   its corpus selftest passes, after the commit lands — one summary line in the run
   output (`work-sensitivity: 3/4 noticed`), and NEVER a changed exit code, retry, or
   reset. A run's outcome is identical with the hook on or off.
5. Recording rides the `20260830f` seam: `SELFTEST_EVID` set ⇒ one JSONL row per probe
   (ts, run id, spec, task, commit, operator, target, verdict, gate rc, the probe's
   diff) plus a `run_complete` marker, into `.evidence/worksens-<slug>.jsonl`; unset ⇒
   not one byte.
6. `mutant-ledger.py` renders a **work-sensitivity** section from those rows — UNNOTICED
   first, with their diffs — clearly separated from the corpus table so telemetry is
   never read as enforcement; `.evidence/README.md` documents the store and the
   distinction.

## 3. Entities · [E — Entities]

A **probe**: one mechanical mutation of one commit's diff (operator + site), applied in a
hermetic copy. **Verdicts**: NOTICED / UNNOTICED / HUNG — deliberately a different
vocabulary from KILLED/SURVIVOR, because an UNNOTICED probe is a lead, not a conviction.
The **sensitivity rows**: `worksens-<slug>.jsonl`. The **budget**: `RALPH_WORK_MUTANTS`.

## 4. Approach · [A — Approach]

One new tool owning generation and verdicts (the `20260831a` §4 rule: the loop
enumerates and delegates, never re-implements); the loop grows one non-blocking,
budgeted hook beside the `20260831u` selftest step; the ledger grows one section.
Probes are generated FROM `git show <commit>` and applied AS reverse patches / line
deletions to the hermetic copy — the tool never needs to understand the language, only
the diff. Rejected: mutating before the commit (the commit is the unit of trust the
gate blessed, and its sha is what makes rows reproducible); rejected: blocking on
UNNOTICED in v1 (equivalent-mutant noise would train operators to discount the signal —
the same reasoning that keeps warn-paths warn); rejected: random token-level operators
(illegible probes produce unactionable rows); rejected: a repo-wide sensitivity sweep
(same suite-drift refusal as 20260831u — the scope is the run's own commit, live).

## 5. Scope · [S — Structure: boundary]

### In scope
The files under **Touches**, this spec dir.

### Out of scope
`gate-selftest.sh` and the corpus enforcement path (untouched — enforcement and
telemetry stay separate mechanisms); any blocking behavior on UNNOTICED (OQ1);
language-aware operators (OQ2); model-adjudicated triage of UNNOTICED rows (OQ3); the
fleet visualization itself (consumes the rows); every existing spec (nothing backfilled).

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- `20260831u` (amendments): selftest is on the critical path at first-green; this hook
  runs AFTER it — a gate must first prove its mechanics before its sensitivity is worth
  measuring, and the commit must exist for the probe set to be reproducible.
- `20260830f`: the emission discipline — env set ⇒ rows, unset ⇒ nothing; a partial run
  must never pass for a finished one (`run_complete`).
- gate-selftest's hermetic-copy pattern (cp working tree, strip .git, re-init, carry
  origin/main best-effort) is the copy discipline to reuse; its GATE_SELFTEST_TIMEOUT
  bound applies per probe run.
- `20260831r` T5 + `20260831u` T2: the executor cannot touch the spec dir, and the
  corpus/gate are frozen per run — the probe results are therefore attributable to the
  WORK, not to a moving ruler.
- Comment-only-line detection is a heuristic (leading `#`, `//`, `--`, `;`, empty); it
  reduces noise, it does not eliminate equivalent probes — which is WHY the posture is
  telemetry.

## 7. Norms · [N — Norms]

House style: bash 3.2 floor for the driver, python3 for diff surgery (the pair
gate-selftest already is); verdict vocabulary never overlaps the corpus vocabulary;
one summary line in loop output, loud only on tool error.

## 8. Safeguards · [S — Safeguards]

- The real tree is never modified — T1's gate asserts byte-identity after a run.
- The hook cannot change a run's outcome — T2's gate runs the same fixture with the hook
  on and off and asserts identical exit codes and commits.
- Rows are unambiguous about their nature: every row carries `"kind": "work"`, and the
  ledger section header says telemetry, so a future reader cannot mistake UNNOTICED
  counts for gate failures.

## 9. Task breakdown · [O — Operations]

- **T1 — the tool** (`tasks/T01-mutate-tool`): `work-mutate.sh` — deterministic probe
  generation from a commit's diff, two operators, budget, hermetic gate runs, verdicts,
  emission seam, tree untouched.
- **T2 — the loop hook** (`tasks/T02-loop-hook`): post-commit, post-selftest, budgeted,
  one summary line, provably outcome-neutral, `RALPH_WORK_MUTANTS=0` disables.
- **T3 — the ledger surface** (`tasks/T03-ledger-surface`): the work-sensitivity section
  in `mutant-ledger.{md,html}`, UNNOTICED-first with diffs; `.evidence/README.md` rows.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- **T1** — WHEN run against a fixture commit whose gate checks a marker the commit added,
  a probe deleting that marker SHALL come back NOTICED and a probe deleting an inert
  added line SHALL come back UNNOTICED, each on its own verdict line (ac1); the probe
  set for a given commit SHALL be identical across two runs (ac2); the real tree SHALL
  be byte-identical after (ac3); with `SELFTEST_EVID` set the rows and `run_complete`
  SHALL land in `worksens-<slug>.jsonl`, unset ⇒ no file (ac4); the tool SHALL parse
  (ac5).
- **T2** — WHEN a task commits under the loop with the hook enabled, the output SHALL
  carry one `work-sensitivity:` summary line (ac1); the run's exit code and commit SHALL
  be identical with `RALPH_WORK_MUTANTS=0` and with the default (ac2); an UNNOTICED
  probe SHALL not stop, retry, or reset anything (ac3); the loop SHALL parse (ac4).
- **T3** — WHEN worksens rows exist the ledger SHALL render the section with UNNOTICED
  first and the probe diff visible (ac1); WHEN none exist the section SHALL say so
  rather than vanish (ac2); the section header SHALL name the telemetry posture (ac3);
  `.evidence/README.md` SHALL document the store (ac4).

## 11. Verification — the gates

Per-task gates authored red-first at implementation, driving the real tool, real loop
(fixtures with real corpora — the 20260831u law applies to this spec's own fixtures),
and real ledger renderer; each task ships its mutant corpus (the `20260831u`
requirement, satisfied not exempted). Evidence: red-before-green and green-after in
`evidence/`, plus this spec's own first sensitivity rows — the instrument's first
reading is of itself.

## 12. Open questions

- **OQ1 — when does sensitivity become enforcement?** Deferred until the rows exist.
  The candidate shape: a floor on noticed-rate per task (or per operator class) that
  STOPs like a corpus survivor, ratified only after the dogfood data shows the
  equivalent-probe baseline.
- **OQ2 — language-aware operators.** Off-by-one flips, condition inversions, string
  swaps for the languages the fleet actually works in — higher-signal probes, higher
  authoring cost, after v1's data says where the blind spots cluster.
- **OQ3 — adjudicated triage.** A judge (model) reads each UNNOTICED probe's diff and
  classifies equivalent-vs-suspect before a human looks — the natural next consumer of
  the rows, and a fleet-viz column, not a loop behavior.

## 14. Tuning log

- **v0.1 (2026-08-31)** — Drafted as the OQ2 expansion the same night 20260831u merged
  its spec. Telemetry-not-enforcement is the founding posture; the commit as the probe
  unit and deterministic seeding are what make every ledger row reproducible.
