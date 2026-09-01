# Spec: 20260831u-mutants-always-run

- **Status:** In progress v1.1 — spec merged 2026-08-31 (#119) with Matt's direction
  ("we just need to establish that this process always runs"); the supersession of
  `20260828k` outcome 8 is ratified in `specs/amendments.md`. OQ2 remains open by
  design (the post-wrap expansion Matt named).
- **Owner:** mtgibbs
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Touches:** `scripts/ralph-build.sh`, `scripts/new-spec.sh`, `specs/TEMPLATE.md`,
  `specs/amendments.md` (the supersession entry, on ratification)
- **Tools:** git, bash
- **MCP:** none

## 1. Why · [R — Requirements]

A gate is only trustworthy if it has proven it can fail for the right reason — that is
the whole `20260828k` argument, and its record stands: nine defects in written-and-reviewed
gates across 2026-08-27/28, every one found by running, three gates unable to fail at all.
The tool that proves it (`gate-selftest.sh` + a `mutants/` corpus per task) exists and
works. What died is the *habit*: no spec since `20260829c` shipped a corpus (except
`20260831a`, the sweep spec itself), because nothing scaffolds one, nothing checks for
one, and nothing runs one. Ratified direction (Matt, 2026-08-31): mutants are the
gate-authoring discipline — the author inverts each assertion into the plausible wrong
implementation that would fool it — and the loop must run them EVERY run, so a gate that
was born blind never gets to judge an attempt.

The scope is deliberately the LIVING loop: the run's own spec, in the run's own worktree.
Not a repo-wide sweep — past specs' corpora are history with their gates (see
`20260831t` §4 and the "spec gates are history" correction, same day). And per-run
selftest is also what feeds the research: the `SELFTEST_EVID` rows (`20260830f`) start
accumulating from every dogfood run, which is the dataset the fleet-monitoring
visualization is being built on.

Named limit, stated so nobody oversells this: self-authored mutants test gate
*mechanics* (an assertion that cannot fail, a grep blind to dead code, a check wired to
the wrong id), not gate *conception* — a failure mode the author never imagined gets no
assertion and no mutant (#117 was exactly that). Conception gaps are caught by the outer
layers (real-world failure, judge, human review) and flow back as new assertions WITH
their mutants. OQ2 names the research extension that would attack conception bias.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. The loop runs `gate-selftest.sh` on a task's corpus at the moment that task's gate
   FIRST GOES GREEN, before the commit its green would bless (v1.1 — see §14: selftest
   measures a gate against BUILT work; pristine, a red-first gate fails everything and
   every mutant dies vacuously, so "before any attempt" proved nothing). Any SURVIVOR,
   WRONG-REASON, HUNG, or uncovered-assertion result STOPs the run with a distinct named
   exit (6), the built tree left in place — a gate that cannot fail correctly is not
   qualified to pass anything, and it is the GATE that needs the human.
2. The preflight records: `SELFTEST_EVID` defaults to the worked repo's `.evidence/` so
   every run appends kill/survivor rows (the `20260830f` seam, unchanged) and the ledger
   stays regenerable. Dogfood runs generate the research data as a side effect of running.
3. A new-shape spec whose task has NO `mutants/` corpus is refused the same way (per
   OQ1's ratified answer; the default proposal is refuse-new/warn-legacy by spec date).
4. `new-spec.sh` scaffolds a `mutants/` stub beside each task's `verify.sh` (a template
   mutant carrying the `MUTANT:`/`TARGET:`/`WHY:` header contract), and
   `new-spec.sh --check` fails a spec whose task has no well-formed mutant.
5. `specs/TEMPLATE.md` teaches the authoring move in one paragraph: one mutant per
   assertion id, authored by inverting the assertion, before the build starts — the same
   place the per-task-gate shape is taught, because a convention that lives only in the
   spec that ratified it loses to the template (amendments, 2026-08-31).
6. On ratification, `specs/amendments.md` gains the supersession entry for `20260828k`
   outcome 8, stating what changed (selftest joins the loop's critical path, scoped to
   the current spec) and what did not (the sweep stays an operator recording tool; past
   corpora stay history).

## 3. Entities · [E — Entities]

A **corpus**: `tasks/T<NN>-<slug>/mutants/`, one file per plausible defect, each declaring
`MUTANT:` (assertion id it must break), `TARGET:` (repo-relative file it replaces),
`WHY:` (the blind-spot hypothesis). The **preflight verdicts**: KILLED (gate failed
naming the declared id) is the only pass; SURVIVOR / WRONG-REASON / HUNG / uncovered-id
each refuse. The **selftest rows**: `selftest-<slug>.jsonl` per `20260830f`.

## 4. Approach · [A — Approach]

The loop grows one preflight block beside the ones it already has (tools/MCP, and
`STRATEGY_ENV_REQUIRED` from `20260831r` T2): enumerate the spec's task dirs, delegate
each to `gate-selftest.sh`, refuse on any non-KILLED verdict. No new verdict logic — the
tool owns verdicts (`20260831a` §4's rule), the loop owns refusal. Cost is bounded and
small: the whole 31-mutant historical corpus sweeps in ~35s; one spec's corpus at
preflight is seconds against a run that takes minutes to hours. The executor cannot game
it: `20260831r` T5 already rejects any attempt that touches the spec dir, and the
preflight runs BEFORE attempt 1 from the operator's tree. Rejected: running selftest per
attempt (the corpus and gate cannot change mid-run — T5 — so once per run proves
everything re-proving would); rejected: a repo-wide preflight sweep (regression-suite
drift; past gates are history); rejected: generating mutants mechanically at run time
(an unreviewed generator produces equivalent-mutant noise, and the WHY hypothesis is
what makes a survivor mean something — see OQ2 for the curated research version).

## 5. Scope · [S — Structure: boundary]

### In scope
The files under **Touches**, this spec dir.

### Out of scope
`gate-selftest.sh` and `mutant-ledger.py` (verdict semantics and the recording seam are
`20260828k`/`20260830f` law and are consumed, not changed); `selftest-sweep.sh` (stays
the operator's recording command); every existing spec's gates and corpora (history —
nothing is backfilled); live mutation of generated WORK (OQ2, its own spec if wanted);
the fleet-monitoring visualization itself (consumes the rows this spec starts producing).

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- `20260828k`: kill = non-zero exit AND the declared assertion id named — two
  requirements, not one; outcome 5 fails a corpus that leaves an assertion id
  undeclared; outcome 8 is the line this spec supersedes on ratification.
- `20260830f`: `SELFTEST_EVID` names the evidence dir; when set, gate-selftest appends
  one row per mutant plus a `run_complete` marker. The seam is emission-only.
- `20260831a` §4: the sweep pattern — enumerate, delegate, never re-implement verdicts.
- `20260831r` T2 is the preflight house shape: refuse early, exit distinct, name the
  problem, before any phase runs.
- `20260831r` T5: the executor cannot edit the spec dir, so gate + corpus are frozen for
  the run's duration — which is what makes once-per-run sufficient.
- The monolithic-refusal arc (`20260828i` → amendments → `20260831p`) is the precedent
  for OQ1's shape: a structural defect in a NEW spec is refused outright; legacy gets a
  narrow, dated story, not a hatch that generalizes.

## 7. Norms · [N — Norms]

House script style: bash 3.2 floor, `set -uo pipefail` where owned, refusals name the
thing refused, values never invented. Preflight output is operator-facing: one line per
corpus verdict, loud only on refusal.

## 8. Safeguards · [S — Safeguards]

- The preflight must not mutate the operator's tree — `gate-selftest.sh`'s hermetic copy
  is the mechanism, and the gate for T1 asserts the tree is byte-identical after.
- A refusal must be distinguishable from a gate failure: distinct exit, distinct wording
  ("your GATE failed its selftest" vs "the work failed the gate").
- Legacy specs (pre-this-spec, no corpus) must keep their ratified behavior under OQ1's
  answer — a warn is a warn, never a silent skip.

## 9. Task breakdown · [O — Operations]

- **T1 — preflight selftest** (`tasks/T01-preflight-selftest`): the loop runs each task
  corpus before attempt 1; non-KILLED refuses with the named exit; rows recorded via
  `SELFTEST_EVID`; operator tree untouched.
- **T2 — corpus required** (`tasks/T02-corpus-required`): the refusal policy per OQ1's
  ratified answer, in the loop, beside the monolithic refusal.
- **T3 — scaffolder + template** (`tasks/T03-scaffolder-mutants`): `new-spec.sh` emits
  the `mutants/` stub, `--check` requires a well-formed mutant per task, TEMPLATE.md
  teaches the inversion move.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- **T1** — WHEN a task's gate goes green and its corpus kills, the run SHALL converge
  with the verdict visible in the output (ac1); IF any mutant survives THEN the loop
  SHALL stop with exit 6 BEFORE committing, naming the verdict (ac2); the refusal
  wording SHALL blame the GATE ("gate failed its selftest"), never the work (ac3); the
  selftest rows SHALL land in the worked repo's `.evidence/` by default (ac4); the loop
  SHALL parse (ac5).
- **T2** — WHEN a new-shape spec's task has no `mutants/` THEN the loop SHALL apply
  OQ1's ratified policy (refuse, naming the task) (ac1); legacy specs SHALL get the
  ratified legacy behavior, stated out loud, never silently skipped (ac2).
- **T3** — a freshly scaffolded spec SHALL carry a mutants stub whose header parses
  under gate-selftest's contract (ac1); `--check` SHALL fail a task with no well-formed
  mutant and pass the scaffold (ac2); TEMPLATE.md SHALL carry the authoring paragraph
  (ac3).

## 11. Verification — the gates

Per-task gates under `tasks/`, driving the REAL `ralph-build.sh` and `new-spec.sh`
against `mktemp` fixtures with stub executors — no network. Authored red-first after this
spec passes review (the scaffold's stubs hold the red until then). And this spec eats its
own cooking: each task gate ships WITH its corpus, making these the first post-`20260829c`
corpora — the same "first consumer" move `20260828k` made for per-task gates.

## 12. Open questions

- **OQ1 — corpus-required policy.** DECIDED with the merge (2026-08-31), as proposed:
  refuse a corpus-less task in specs dated `20260831u` or later (structural defect,
  monolithic precedent, no hatch); pre-existing specs run with a loud one-line warn.
  Backfilling old corpora is explicitly NOT the alternative — that would be editing
  history's rigor into existence.
- **OQ2 — live mutation of generated work.** The research extension that attacks
  conception bias: mutate the EXECUTOR'S actual diff (not a hand-authored replacement)
  and measure whether the gate notices — gate sensitivity against the real artifact,
  author-independent. Curated operators, its own spec, feeding the same ledger. Not in
  scope here; named so the visualization roadmap can see it coming.

## 14. Tuning log

- **v1.1 (2026-08-31, at implementation)** — Three findings the build itself produced:
  1. **The kill-proof moment moved from before-attempt-1 to FIRST-GREEN.** gate-selftest
     measures a gate against built work (it copies the working tree); pristine, a
     red-first gate fails everything and every mutant dies vacuously — v0.1's "before any
     attempt runs" would have proven nothing. Preflight keeps the static half (corpus
     present, authored, not the sentinel template); the kill-proof runs when the gate's
     green is about to buy a commit, which is the only moment its trustworthiness is
     consumed.
  2. **The first selftest of this spec's own corpus found a real survivor** —
     `headerless-accepted.sh` survived because T03's ac5 observed a `--check` failure
     caused by ac4's leftover fixture state, not by the headerless file. The gate was
     fixed to isolate the case (restore T02's corpus first) and the mutant now dies. The
     mechanism caught a blind spot in the gate of the spec that installs the mechanism,
     on its first run.
  3. **Blast radius, recorded not repaired:** `20260831r` T01/T05 go red under the new
     law — their fixtures scaffold future-dated specs whose corpora are the scaffold
     template, which the corpus-era preflight now refuses. The behaviors they pinned
     (convergence runs; spec-dir edits refused) are UNCHANGED; per the gates-are-history
     doctrine (20260831t v1.1) those gates are not edited — their red records the law
     arriving. Also hardened here: the scaffolder's template headers are printf-composed,
     never literal, so a mutant targeting `new-spec.sh` itself survives gate-selftest's
     header-strip at install (the planted-needle trap the tool documents).
- **v1.0 (2026-08-31)** — Built from the merged draft the same day. 17 mutants across
  the three tasks, first corpora since `20260829c`; all killed (after finding 2 above).
- **v0.1 (2026-08-31)** — Drafted from the mutants conversation the same day: the tool
  survived, the habit died with nothing scaffolding/checking/running corpora; ratified
  direction is selftest on the loop's critical path, scoped to the run's own spec,
  never a repo-wide suite.
