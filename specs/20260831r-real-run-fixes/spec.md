# Spec: 20260831r-real-run-fixes

- **Status:** In progress v1.0
- **Owner:** mtgibbs
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Touches:** `scripts/ralph-build.sh`, `scripts/run-loop.sh`, `scripts/ralph-judge.sh`, `scripts/loops/README.md`
- **Tools:** git, bash
- **MCP:** none

## 1. Why · [R — Requirements]

The jig's first two real-project runs (notes-from-hearing, 2026-08-31 — PRs #16/#17 there)
surfaced a findings list. This spec addresses exactly the diagnosed ones and nothing else:
a mid-run auth abort that a preflight should have caught (H1), a judge that errors instead
of logging its prompt every round (H6), an index-row guard that warns falsely on every
per-task run (H7), and — ratified fail-closed by Matt — an executor that edited its own
task gate inside the attempt that satisfied it (H8). One finding (H5, "the loop never runs
the convergence gate") turned out to be a misdiagnosis; its task became a pin of the
behavior that actually exists. H4 (scaffolder retrofit mode) is deferred as issue #114.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `STRATEGY_ENV_REQUIRED` refuses early (exit 3, variables named, values never
   printed) before any phase. Built-in confs never declare it — which env an executor
   needs is operator knowledge; operators declare it in a `.harness/loops/` overlay conf
   or export it at launch (an environment value flows through an undeclaring conf).
2. `ralph-judge.sh` sources `ralph-log.sh` guarded (with no-op fallbacks) and initializes
   logging, so judge prompts are recorded and "command not found" is gone.
3. The index-row guard probes with the bare task label (`T1`), matching what
   `loop-index.py` writes.
4. An attempt that changes anything under `$SPEC_DIR` is rejected wholesale before the
   gate — refusal names the files, tree reset, feedback teaches "report gate gaps, never
   edit them".
5. The existing per-task convergence behavior (task gates STRICT + spec-level verify at
   the end) is pinned by a gate that runs the real loop.

## 3. Entities · [E — Entities]

`STRATEGY_ENV_REQUIRED` — space-separated variable NAMES in a strategy conf; consumed by
`run-loop.sh` preflight via bash-3.2-safe `eval` indirection. The spec-dir guard —
tracked diffs plus untracked files under `$SPEC_DIR`, evaluated between the executor
attempt and the gate, alongside the scope guard it mirrors.

## 4. Approach · [A — Approach]

Smallest change at each diagnosed site, in the file's own idiom: the env preflight sits
beside the existing tools/MCP preflight, and the requirement itself lives with the
OPERATOR (overlay conf or export) because the built-ins cannot know any executor's
credential names — v1.0 hardcoded `OPENCODE_QWEN_KEY` into `build-then-judge.conf` and
was corrected on review; the judge's sourcing block mirrors
`ralph-build.sh`'s guarded pattern for the same file; the label fix adopts the expansion
the adjacent `loop-metrics.sh` call already uses; the spec-dir guard is the scope guard's
reject-wholesale/log/reset/feedback shape with a different predicate. Rejected: acquiring
credentials in the binding (20260825c decided operator-owns), and filtering spec-dir
changes out of a commit instead of rejecting the attempt (a gate green because of edits it
smuggled is a lie in history — same reasoning as the scope guard).

## 5. Scope · [S — Structure: boundary]

### In scope
The four files under **Touches**, this spec dir.

### Out of scope
`scripts/exec-opencode.sh` (its no-credentials contract is the point), `loop-index.py`,
`new-spec.sh` (retrofit mode deferred, #114), any change to what the judge prompt says.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- `exec-opencode.sh` refuses credential acquisition by design (20260825c) — the fix is a
  named early refusal, never a fallback lookup.
- `log_prompt` self-gates on `LOG_OK`; sourcing without `log_init` silences the error but
  records nothing — the judge must init (RALPH_AGENT=judge names the run dir).
- `loop-index.py` writes `"task": "T1"` (bare label); `${HB_TASK%%:*}` produces it;
  `${HB_TASK%% *}` produces `T1:` and can never match.
- The scope guard (20260831d) is the template for attempt rejection: reject wholesale,
  log_failure BEFORE `_reset_tree`, feedback, continue.
- The convergence block at `ralph-build.sh` ~661-679 already runs task gates STRICT plus
  the spec-level verify for per-task specs — silent when green (the H5 misread).

## 7. Norms · [N — Norms]

House script style: `set -uo pipefail`, bash 3.2 floor (no arrays, no `${!var}`-hostile
constructs — `eval` indirection), guarded cross-file calls, secrets never echoed, warn
paths stay warn (the index guard must not become fatal).

## 8. Safeguards · [S — Safeguards]

- The env preflight prints variable NAMES only — a value in output is a failure (T02 ac3
  pins it).
- The spec-dir guard must not reject honest attempts (T05 ac4 pins it) and must restore
  the edited files before the next attempt (T05 ac2).
- Strategies without `STRATEGY_ENV_REQUIRED` are byte-for-byte unaffected (T02 ac4).

## 9. Task breakdown · [O — Operations]

- **T1 — convergence pinned** (`tasks/T01-run-convergence-gate`): fixture specs through
  the REAL `ralph-build.sh` — red convergence stops nonzero, green converges, exactly one
  convergence run, legacy path unchanged.
- **T2 — env preflight** (`tasks/T02-strategy-env-preflight`): `STRATEGY_ENV_REQUIRED`
  refusal semantics; built-ins provably declare nothing; operator export flows through.
- **T3 — judge logs its prompt** (`tasks/T03-judge-prompt-logged`): guarded source +
  fallback + source-before-call ordering.
- **T4 — index guard label** (`tasks/T04-index-guard-label`): bare-label expansion in the
  guard block, nowhere the colon-keeping form.
- **T5 — spec-dir guard** (`tasks/T05-executor-gate-edits-refused`): the gate-rewriting
  stub is refused, named, restored; the honest stub converges.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- **T1** — WHEN a per-task fixture's task gates pass and its spec-level verify exits
  nonzero, the loop SHALL exit nonzero having run it (ac1); WHEN it exits 0 the loop
  SHALL converge at 0 (ac2); the convergence verify SHALL run exactly once across a
  two-task run (ac3); a no-tasks-dir spec SHALL still be judged by its spec verify (ac4).
- **T2** — IF a declared variable is unset or empty THEN run-loop SHALL exit 3 naming it
  before any phase (ac1–ac2); WHEN satisfied it SHALL proceed with the value absent from
  all output (ac3); undeclared strategies SHALL behave as before (ac4); NO built-in conf
  SHALL set `STRATEGY_ENV_REQUIRED` (ac5); an operator-exported value SHALL be enforced
  through an undeclaring conf (ac6); `loops/README.md` SHALL document the operator
  contract (ac7).
- **T3** — `ralph-judge.sh` SHALL source `ralph-log.sh` guarded (ac1) with a no-op
  fallback (ac2); `ralph-log.sh` SHALL define `log_prompt` (ac3); the source SHALL
  precede the call (ac4).
- **T4** — The guard block SHALL use `${HB_TASK%%:*}` (ac2) and the colon-keeping form
  SHALL be absent from the file (ac1); the expansion SHALL match a real indexer row (ac3).
- **T5** — WHEN an attempt changes any file under the spec dir the loop SHALL reject it
  before the gate, exit nonzero overall (ac1), restore the files (ac2), and name them
  (ac3); an attempt touching only product files SHALL converge (ac4).

## 11. Verification — the gates

Per-task gates under `tasks/`, all driving the REAL scripts against `mktemp` git fixtures
(scaffolded by `new-spec.sh`, stub executors ≥512B transcripts) — no network, no
simulators. Red: `evidence/red-before-green.txt` (15 FAILs across T02–T05; T01 green at
capture, which is what exposed the H5 misdiagnosis). Green: `evidence/green-after.txt`
(31 checks, 0 FAIL).

## 12. Open questions

None. H4 is issue #114; H2 (probe-literal hygiene) needed no change — TEMPLATE Trap A
already covers it and the run proved it on Swift comments.

## 14. Tuning log

- **v1.1 (2026-08-31)** — T2 corrected on Matt's review ("generalization, convention,
  and portability"): v1.0 hardcoded `OPENCODE_QWEN_KEY` into the built-in
  `build-then-judge.conf` — one laptop's opencode config baked into a shared file the
  same way `exec-qwen.sh`'s rename warned about. Reverted; built-ins now provably
  declare nothing (T02 ac5 refuses it), operators declare via overlay conf or export
  (ac6), README carries the contract (ac7).
- **v1.0 (2026-08-31)** — Authored from the notes-from-hearing run findings the same day.
  T1 began as a fix for "the loop never runs convergence" and its red-first gate came back
  GREEN — the convergence block at ~661-679 already does it. The task was rewritten as a
  pin instead of being deleted: the gate that disproved the diagnosis is exactly the gate
  that keeps the behavior from regressing. H8's fail-closed posture (reject spec-dir
  edits outright, let blind spots escalate to humans) was Matt's explicit call.
