# Fleet dispatch — events spin up ephemeral loop containers

**Status:** design, 2026-08-27. Nothing here is built. Precondition: `specs/20260826a-evidence-replayable`
and `specs/20260827a-spec-manifest` implemented (both merged as specs, both gated, both unbuilt).

This document is self-contained on purpose: it is written to be read cold — by Matt, or by
a worker container that has this repo and nothing else. It records what we are building,
what evidence it rests on, and the failure modes we named **before** starting.

## The goal

A general system where **events** spin up **ephemeral LLM loop containers** that produce
**reviewable outputs** — PRs first, generalizable later. The model backend is qwen served
centrally (LiteLLM on the Beelink); the loop machinery is this repo; the consumer repos
bring only `specs/<feature>/{spec.md,tasks.txt,verify.sh}`, per the existing convention.

The shape, end to end:

```
event (chat mention, later webhook)
  └─ dispatcher (thin, deterministic, always-on)
       └─ launches one ephemeral worker (k8s Job from the loop-container image)
            └─ worker runs the SAME run-loop.sh a human runs locally
                 └─ gate green → PR opened, .evidence/ aboard → container dies
```

## The evidence this design rests on

A working prototype of this exact shape exists (Matt's, from work — private; we port
**ideas by concept, never code**, and the archive stays out of git). It listens for issue-
tracker mentions via a webhook, a ~140-line serverless dispatcher validates and launches
one cloud container per run, the container drives a coding agent headlessly against a
cloned repo, and opens a draft MR with the disclosure trailers enforced by the harness
rather than trusted to the agent. It has bounded feedback modes (revise-on-review-comment,
fix-on-CI-failure, rebase-on-request, capture-reject-signal) driven by MR webhooks.

What it proves, and what we port:

1. **The three-tier split.** The dispatcher does validate → map → launch → record and
   *nothing else*; every judgment lives in the worker. The dispatcher stayed ~140 lines
   over its whole life because of this rule.
2. **Deterministic intent.** WHAT to do is the human's verb, parsed by a tiny fixed alias
   table — never an LLM. The default verb is read-only. Only writes get gated.
3. **Fail-loud outcome taxonomy.** Every run emits one structured `run_summary` record;
   a specific outcome maps to a coarse status (`shipped/deferred/noop/failed`); **unknown
   outcomes read as `failed`**, and a run that exits still tagged `started` crashed before
   classifying itself. This is "green is not proof" as a status mapper.
4. **Structural enforcement beats prose instruction.** Squashed conforming commits,
   robot-disclosure trailers, rebase-onto-moved-target — all done *by the harness after
   the agent runs*, because agents observably skip prose instructions. (Its prediction
   file is written by a separate structural call for exactly this reason.) Same lesson as
   our gate discipline; keep applying it.
5. **Bounded feedback with loop-guards.** Attempt caps counted from the bot's own comment
   markers; ignore the bot's own comments; an opt-in label so the bot never touches PRs it
   doesn't own; push-rejection surfaced as a reported outcome carrying the server's reason,
   not a crash.
6. **The scorer argument.** Its eval loop scores a countable **vector, never a weighted
   sum** — "a weighted total is the most direct route to reward hacking." Progress = no
   dimension regressed AND at least one improved; stop when the *weakest* dimension hasn't
   risen for two turns; a regression is terminal. This resolves our judge-rubric design:
   keep **anchors, floors, and a declared category set**; drop weights and the composite.

## What we deliberately do NOT port

- **Its trust model.** The prototype's fix path ships whatever the agent committed — the
  agent's summary is the only check before the draft MR. Here, **the gate decides done:
  no green `verify.sh`, no PR** (at most a draft hard-labeled `gate:failed`). This is the
  single most important divergence.
- **The LLM router + confidence gate.** It exists there because issues arrive unrouted
  across many repos. Our triggers name repo+spec explicitly and specs live in the repo
  they change. No router, no confidence machinery — the biggest simplification available.
- **Seven intents.** We start with exactly one: `fix` (spec → PR). Read-only `explain`
  maybe second. Each added intent doubles the dispatcher surface; add only when pulled.
- **A/B runtime lanes.** The executor-binding seam (`specs/20260825c-executor-binding`) gives this
  back for free any time via a strategy `.env`; building it into the dispatcher doubles
  everything for no current need.

## Homelab mapping

| Prototype (cloud) | Here | Notes |
|---|---|---|
| Issue-tracker mention → webhook | **Matrix mention in `#tasks`** (agent-bus, already live) | zero new edge exposure; the service-bot pattern already exists |
| Serverless dispatcher | **`harness-dispatch`** — small in-cluster service, GitOps-deployed | the permanent fixture |
| One cloud task per run | **k8s Job** from the loop-container image | ServiceAccount RBAC scoped to creating Jobs in one namespace |
| Model inside the task | **qwen via LiteLLM on the Beelink** (network call) | key difference: model serving is centralized, so workers are cheap CPU-only pods |
| Draft MR | **GitHub PR** via the existing role-scoped bot identity | PR-gated always; reuse before mint |
| Cloud log lines | `run_summary` JSONL in `.evidence/` + ntfy on `failed` | joins the loop-doctor corpus |
| Review/CI feedback modes | later phase, same caps + loop-guards | not in v1 |

**The MCP question** ("orchestrator from the laptop OR a permanent fixture"): both, split
correctly. The **dispatcher is the fixture** — event listeners, launch policy, run
registry, HTTP API. An **MCP server is a thin client** over that API: `launch_run(repo,
spec, strategy)`, `run_status`, `list_runs`, `cancel_run`, `fetch_evidence`. The laptop
gets a handle, not a copy of the machinery.

**Worker placement:** k8s Jobs on the Pi cluster (everything-as-code, Flux-deployed,
RBAC-bounded; the heavy lifting is in the model on the Beelink anyway). The Beelink's
long-lived `coding-harness-*` workstation containers are a separate lifecycle class owned
by the human — they are **not** fleet members and don't get retrofitted.

## The cliffs (named before we start, so we can check the mirror later)

1. **Two harnesses.** The container must invoke the *same* `run-loop.sh` a human runs
   locally. One engine, two front doors. The day the paths diverge, the simple one rots.
2. **The dispatcher accreting judgment.** The always-on thing attracts logic. Rule:
   validate → map → launch → record. When the dispatcher can't be described in a
   paragraph, this cliff has been gone over.
3. **Unwatched triggers without the boring parts.** Event triggers replace the human at
   the start of every run. The caps, own-bot loop-guards, and idempotent event dedupe are
   the *replacement for the human*, not plumbing. None are skippable.
4. **Ephemeral before replayable.** A wedged k8s Job is a dead pod. If
   `evidence-replayable` isn't implemented first, ephemeral = evidence gone. It is the
   fence at the top of this cliff.
5. **Blast radius on the family cluster.** Loop Jobs share the Pis with DNS and media:
   dedicated namespace + ResourceQuota, concurrency cap 1–2, `activeDeadlineSeconds`,
   `ttlSecondsAfterFinished`, from day one. A runaway fleet must not take Pi-hole down.
6. **Run-key collision.** `run_id = <agent>-<pid>` is unique per *host*. Two workers on
   two nodes collide silently and corrupt the corpus. Fix **before** the first concurrent
   fan-out, not after.

## The simplicity bar

"A simple tool is the one people reach for." Concretely:

- one command locally: `scripts/run-loop.sh <strategy> specs/<feature>`
- one message remotely: `@harness fix <repo> <spec>`
- one place to look when it breaks: `.evidence/` + `loop-doctor`
- one mental model: every phase is Gen → Eval; only the evaluator differs
- adding a repo to the fleet = the repo adds `specs/` — zero dispatcher changes

## Sequencing

| # | Work | Gate |
|---|---|---|
| 0 | Implement `evidence-replayable`, then `spec-manifest` (loop-run) | their own verify.sh, STRICT |
| 1 | Fleet-safe run key (host discriminator + `RUN_LABEL`) | before ANY fan-out |
| 2 | `exec-container.sh` + loop-container Dockerfile (arm64+amd64) | binding contract unchanged: `docker run --rm -v ROOT -e ROOT` |
| 3 | `harness-dispatch` ADR → spec (Matrix listener, Job launcher, outcome taxonomy, registry, HTTP API) | dispatcher stays thin |
| 4 | `mcp-harness` thin client | read tools first; `launch_run` the only mutation |
| 5 | Judge rubric: anchors/floors/declared set, vector not composite, `review.md` | below-floor fixture must FAIL |
| 6 | Gate-gap ↔ red-before-green join (judge-of-the-judge) | no new model in the path |
| 7 | Later: GitHub-webhook edge; revise/cifix feedback modes on bot PRs | caps + loop-guards ported |
| 8 | Later: fine-grained per-container executor permissions | replaces the blanket `--auto`, below |

### Deferred: the executor runs with `--auto`

Item 2's build needed `opencode run --auto` — "auto-approve permissions that are not explicitly
denied". Without it the executor **aborts**: it explores the directory it is writing into, hits a
`read` guard on `*.env` (which every agent tool treats as secret-bearing, and which is the
extension this repo uses for loop strategy files that hold no secrets), and the session ends. The
loop scores that as `changed nothing` three times, so a permission surprise is indistinguishable
from a lazy model — see `specs/20260828a-exec-container/evidence/`.

`--auto` is acceptable today: the container already grants `edit` and `bash` and explicitly denies
`webfetch`, and every run is PR-gated, so it grants strictly less than what is already granted.
It is a blunt instrument all the same, and an ephemeral fleet worker is exactly where a blunt one
is least wanted.

**Revisit when per-container permission sets exist** (item 8): a loop container should declare the
narrow set it needs — and `specs/20260827a-spec-manifest`'s `Permissions:` field is the seam that was built
for it, currently recorded-but-unenforced. Two smaller fixes stand on their own: grant `read` for
`*.env` rather than everything, or stop naming secret-free strategy files `.env` at all
(`run-loop.sh` resolves `scripts/loops/<name>.env`, so it is a contained change).

Item 3 starts as an ADR because it crosses the framework/instance seam: the dispatcher
*service* deploys in pi-cluster (GitOps), while its *contract* lives here.

## Verification sketch

- **1** — two simulated runs with identical pids on different "hosts" get distinct run ids;
  the corpus attributes both correctly.
- **2** — one spec run via `exec-qwen.sh` and via `exec-container.sh`; `.evidence/`
  differs only in `binding`.
- **3** — a Matrix `fix` mention launches a Job that opens a PR with evidence aboard; an
  unknown verb posts help and launches nothing; a Job killed mid-run leaves a `failed`
  run_summary (kill one to prove it — a gate must show it can fail).
- **4** — MCP `launch_run` → `run_status` round-trip from the laptop against a live run.
