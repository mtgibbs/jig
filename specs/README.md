# Specs — how Jig develops itself

This directory is where Jig practices its own convention: **spec-driven development
(SDD)**. The spec is the primary artifact, and the implementation is a *regenerable
output* of it. We write the spec first, agree on it, then execute against it — by hand,
with Claude, or by handing it to a local agent through the loop. This repo is its own
first subscriber: a change to Jig is gated exactly the way a consumer's is.

> Why: agents (and humans) drift when the target is fuzzy. A rigorous spec is the shared
> source of truth — it aligns us *before* code exists, and it's the thing a reviewer
> checks the diff against. (Sean Grove, OpenAI: code is a lossy projection of the spec;
> Geoffrey Huntley: "specs are the real asset.")

## The layers

| Layer | What | Where it lives |
|---|---|---|
| **Constitution** | Harness law every spec inherits | [`constitution.md`](constitution.md) + append-only [`amendments.md`](amendments.md) |
| **Consumer overlay** | A consumer repo's own law, assembled after the generic law | that repo's own `specs/constitution.md` (+ amendments); absent = declares nothing |
| **Spec** | Per-feature: outcomes, scope, EARS criteria, tasks | `specs/<date-slug>/spec.md` — copy [`TEMPLATE.md`](TEMPLATE.md) |
| **Execute** | One task per iteration, fresh context | `scripts/run-loop.sh <strategy> specs/<feature>` |
| **Verify** | The deterministic gate, then human PR review | `verify.sh` per spec; per-task gates under `tasks/*/` with `mutants/` |
| **Evidence** | What the run left behind, committed | `.evidence/` at the repo root, plus each spec's own `evidence/` |

## Tiered context — what each reader is handed

Context is budgeted, and choosing what goes in each tier is the actual skill:

| Tier | What | Who reads it |
|---|---|---|
| **1 — Law** | [`constitution.md`](constitution.md) + [`amendments.md`](amendments.md) | the judge, on every review (harness pair first, then the target repo's overlay pair) |
| **1 — Executor brief** | `AGENTS.md` at the repo root — the same law, projected lean for a small context window | the executor, on every handoff |
| **2 — The spec** | the feature's slice: entities, approach, worked examples, literal values | whoever executes the task |
| **3 — Deep reference** | `docs/` runbooks, [`design-principles.md`](design-principles.md), past specs' evidence | on demand |

> Tier 1 is sized to the model. A local executor (~32k window) cannot afford what an
> orchestrator can, so it gets its own lean entry file, not the full law. Same underlying
> truth, two model-sized projections — keeping the local model's window clean is a
> feature, not a shortcut.

## Acceptance criteria use EARS

[EARS](https://alistairmavin.com/ears/) (Easy Approach to Requirements Syntax) — five
templates that make a requirement testable instead of vibey:

- **Ubiquitous:** The `<system>` shall `<response>`.
- **Event-driven:** When `<trigger>`, the `<system>` shall `<response>`.
- **State-driven:** While `<state>`, the `<system>` shall `<response>`.
- **Unwanted behavior:** If `<condition>`, then the `<system>` shall `<response>`.
- **Optional:** Where `<feature>`, the `<system>` shall `<response>`.

## Lifecycle

1. Copy [`TEMPLATE.md`](TEMPLATE.md) → `specs/<date-slug>/spec.md` (Draft). Capture
   what's known; list unknowns as **Open Questions**. A prior-art pass over agent history
   (`ctx search`) inherits memory the executor doesn't have.
2. **Plan**: resolve the open questions, record decisions back into the spec (*living
   document*). Resolve three kinds of unknown: **correctness** (real values), **granularity**
   (the exact field a criterion needs, not a proxy), **design** (the tasteful pattern, per
   [`design-principles.md`](design-principles.md)).
3. **Execute** against `tasks.txt`, one task per iteration.
4. **Verify** with the gate — red-before-green recorded in the spec's `evidence/` — then
   open a PR and review the diff against the acceptance criteria.

## Index — this repo's specs

- [`20260801a-scored-gate`](20260801a-scored-gate/spec.md) — a scored gate: turn the pass/fail verify into a convergence signal
- [`20260802a-judge-loop`](20260802a-judge-loop/spec.md) — judge loop: climb above the deterministic gate toward "good"
- [`20260810a-loop-report`](20260810a-loop-report/spec.md) — loop-report: one-screen summary of a strategy run
- [`20260818a-ralph-retry-contract`](20260818a-ralph-retry-contract/spec.md) — the retry contract: a retry must be clean, informed, and honest about regression
- [`20260818b-loop-doctor`](20260818b-loop-doctor/spec.md) — loop-doctor: read the loop's own telemetry and name the fault
- [`20260818c-run-regression-guard`](20260818c-run-regression-guard/spec.md) — a later task must not destroy an earlier task's work
- [`20260818d-tasks-ledger`](20260818d-tasks-ledger/spec.md) — the task ledger: a sidecar that remembers which tasks are already green
- [`20260825a-evidence-convention`](20260825a-evidence-convention/spec.md) — a project brings specs and gates; Jig owns everything else
- [`20260825b-evidence-spec-nesting`](20260825b-evidence-spec-nesting/spec.md) — file run evidence under the spec it was produced for
- [`20260825c-executor-binding`](20260825c-executor-binding/spec.md) — the build phase takes an executor binding, like the judge phase already does
- [`20260826a-evidence-replayable`](20260826a-evidence-replayable/spec.md) — an attempt's record is replayable, not just readable
- [`20260827a-spec-manifest`](20260827a-spec-manifest/spec.md) — a spec declares what it needs, and the loop refuses to start without it
- [`20260827b-fleet-run-key`](20260827b-fleet-run-key/spec.md) — a run key that survives two workers
- [`20260827c-last-task-strict`](20260827c-last-task-strict/spec.md) — the last task's gate is the strict gate
- [`20260828a-exec-container`](20260828a-exec-container/spec.md) — the executor runs in a container, and the loop cannot tell
- [`20260828b-index-nested-runs`](20260828b-index-nested-runs/spec.md) — the index can see a run that lives one level deeper
- [`20260828c-strategy-file-extension`](20260828c-strategy-file-extension/spec.md) — a strategy file stops looking like a secrets file
- [`20260828d-image-ci`](20260828d-image-ci/spec.md) — the images this repo defines are actually published
- [`20260828e-record-fields`](20260828e-record-fields/spec.md) — the attempt record says what happened and how long it took
- [`20260828f-harness-dispatch`](20260828f-harness-dispatch/spec.md) — the dispatcher turns an event into exactly one run
- [`20260828g-dispatch-core`](20260828g-dispatch-core/spec.md) — one dispatch core, many transports
- [`20260828h-dispatch-api`](20260828h-dispatch-api/spec.md) — the dispatch API, and the tools that call it
- [`20260828i-per-task-gates`](20260828i-per-task-gates/spec.md) — per-task gates, a shared assertion vocabulary, and mutation self-test
- [`20260828j-mcp-harness`](20260828j-mcp-harness/spec.md) — the fleet's MCP surface, as a client of the dispatch API
- [`20260828k-gate-selftest`](20260828k-gate-selftest/spec.md) — gate-selftest: prove a gate can fail, and finish the per-task migration
- [`20260828l-run-control`](20260828l-run-control/spec.md) — resume, retry, and the seam a run-control surface hangs on
- [`20260828m-worker-channel`](20260828m-worker-channel/spec.md) — the worker's outbound channel: report status, notice controls
- [`20260828n-mcp-reachable`](20260828n-mcp-reachable/spec.md) — a declared MCP is reachable, not merely configured
- [`20260828o-evidence-egress`](20260828o-evidence-egress/spec.md) — the attempt's artifacts leave the worker as they are produced
- [`20260829a-executor-image-layer`](20260829a-executor-image-layer/spec.md) — the executor is an image layer, not a fork
- [`20260829b-resume-bound`](20260829b-resume-bound/spec.md) — resume-bound: the question "is this already done?" must afford the answer
- [`20260829c-hermetic-gate`](20260829c-hermetic-gate/spec.md) — a gate measures the work, not the environment it was launched from
- [`20260830a-product-naming`](20260830a-product-naming/spec.md) — the product is named Jig: identity renames, the bones do not
- [`20260830a-worker-credentials`](20260830a-worker-credentials/spec.md) — a worker gets exactly the credentials its strategy needs
- [`20260830b-dispatcher-image`](20260830b-dispatcher-image/spec.md) — the dispatcher ships as an image, and the worker it launches can clone
- [`20260830c-constitution-split`](20260830c-constitution-split/spec.md) — the constitution carries harness law only: consumers bring their own

The gate for [`20260830c-constitution-split`](20260830c-constitution-split/spec.md) checks this
index both ways: a spec directory that isn't listed here fails it, and so does an entry whose
directory doesn't exist.
