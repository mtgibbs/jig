# ADR-001: harness-dispatch — the contract between an event and a run

## Status

**Proposed.** Nothing here is built. Merging this ADR is the acceptance; the spec that follows
implements it.

## Date

2026-08-28

## Why this is an ADR and not a spec

`docs/design/fleet-dispatch.md` sequences this as item 3 and says why: the dispatcher **service**
deploys in `pi-cluster` under Flux, while its **contract** — what an event means, what a run
record is, what the API promises — belongs to the framework. A spec with a `verify.sh` can gate an
implementation; it cannot gate a seam that spans two repositories. This document fixes the seam so
the spec on either side has something to be correct against.

**It lives in `mtgibbs/harness`**, starting this repo's own ADR sequence at 001, because
`docs/design/fleet-dispatch.md` is explicitly written to be read cold by a worker container that
has this repo and nothing else. A contract the worker cannot read is not a contract. The
`pi-cluster` ADR series (currently 008) stays the home for cluster-topology decisions; this one
cross-references it rather than living there.

## Context

Items 0, 1 and 2 landed on 2026-08-27/28:

- **`20260826a-evidence-replayable`** — every attempt persists prompt, gate output + exit status,
  an applyable patch on pass, and a `metadata.json`.
- **`20260827b-fleet-run-key`** — run directories are `<spec>/<host>/<agent>-<pid>`, so two
  workers sharing a pid cannot collide. Cliff 6 is fenced.
- **`20260828a-exec-container`** — `scripts/exec-container.sh` runs the executor in a container.
  **Half-verified**: the image build and the `exec-qwen` vs `exec-container` parity run need a
  host with docker and are a runbook in `docs/loop-container.md`.

Item 2's asterisk is a precondition on this ADR's implementation, not on the ADR.

## Decisions

### D1 — Events arrive by Matrix `/sync` long-poll, not by webhook

`scripts/agent-bus wait --room tasks --mention` already blocks on the Matrix client-server
`/sync` endpoint with a `since` cursor, and the service-bot identity already exists
(`MATRIX_TOKEN`, `MATRIX_HOMESERVER`, `MATRIX_DOMAIN`).

The dispatcher is therefore an **outbound-only** client. It opens no port to the internet, needs
no Cloudflare Tunnel, no HMAC verification, and no new edge exposure. This is the largest
divergence from the prototype, which used an issue-tracker webhook because it had no other
channel, and it deletes an entire class of security surface rather than configuring it.

**Consequence, and it is not free:** a long-poll consumer owns a cursor. The `since` token must
survive a pod restart or the dispatcher either replays events it has already actioned or silently
skips events that arrived while it was down.

**Decision:** the cursor is persisted, and **event dedupe does not depend on it**. Each Matrix
event carries a unique event id; the dispatcher records the ids it has actioned and ignores a
repeat. The cursor is an optimisation for not re-reading; the id ledger is the correctness
mechanism. Cliff 3 names idempotent event dedupe as the replacement for the human, not plumbing —
so it may not be derived from a cursor that can be lost.

### D2 — Intent is a fixed alias table. One verb.

`@harness fix <repo> <spec>` and nothing else in v1. Parsed by a literal table, never by a model.
An unrecognised verb posts the help text into the thread and **launches nothing**.

Rejected: the prototype's LLM router and confidence gate. They exist there because issues arrive
unrouted across many repos; our triggers name repo and spec explicitly, and specs live in the repo
they change. No router, no confidence machinery.

Every added verb doubles the dispatcher's surface. `explain` (read-only) is the plausible second
and is deliberately not in v1.

### D3 — The dispatcher does validate → map → launch → record, and nothing else

Every judgment lives in the worker. The prototype held ~140 lines across its whole life because of
this rule, and cliff 2 names the failure mode: the always-on component attracts logic.

**The thinness test is structural, not aspirational.** The dispatcher's own spec will carry a gate
asserting it contains no model call, no gate invocation, and no retry logic — the same shape as
`20260825c-executor-binding`'s thinness assertions for a binding. A budget in lines is a proxy; an
assertion that it never imports an LLM client is the property.

### D4 — Workers are k8s Jobs, bounded from day one

One Job per run, from the loop-executor image, in a dedicated namespace.

| bound | value | why |
|---|---|---|
| ServiceAccount RBAC | `create/get/list/delete` on `batch/v1` Jobs, **namespaced Role, one namespace** | there is precedent — see below — and this is deliberately tighter than it |
| concurrency | 1–2 | cliff 5: loop Jobs share the Pis with Pi-hole and media |
| `activeDeadlineSeconds` | set | a wedged run must die on its own |
| `ttlSecondsAfterFinished` | set | finished Jobs must not accumulate |
| ResourceQuota | on the namespace | a runaway fleet must not take DNS down |

**On the RBAC precedent.** A service in this cluster already creates Jobs:
`clusters/pi-k3s/mcp-homelab/clusterrole.yaml` grants `batch/jobs: [create]` under the comment
"Action: Create manual backup jobs" — that is the `trigger_backup` MCP tool. So this is not new
authority, and the pattern is established.

It is granted there as a **ClusterRole** bound cluster-wide, because `trigger_backup` addresses
CronJobs in whichever namespace holds them. The dispatcher has no such need: it launches into
exactly one namespace, so it takes a **namespaced `Role`**, not a `ClusterRole`. Following the
precedent's shape while declining its scope is the decision.

The worker invokes **the same `scripts/run-loop.sh` a human runs locally** (cliff 1: one engine,
two front doors). The day the container path forks from the local path, the local one rots.

### D5 — Evidence must leave the pod, and today it cannot

`.gitignore` in this repo is exactly `.evidence/runs/`. A run's prompts, gate outputs, patches and
metadata are written to a path that is **never committed**. On a workstation that is fine — the
directory outlives the process. In a k8s Job the pod is the filesystem, and when it exits the
evidence is gone.

This was demonstrated accidentally on 2026-08-28: transcripts needed for a write-up had already
been destroyed with the worktree that held them.

Cliff 4 says `evidence-replayable` is the fence at the top of this cliff. It is necessary and it is
**not sufficient** — it writes the record, and nothing carries it off the machine.

**Decision:** a run's durable output is the **`run_summary` record plus the evidence index**, and
both travel in the PR the run opens. The bulky per-attempt artefacts stay gitignored and die with
the pod by design; what survives is the summary, the index, and the patch that became the PR. A
run that opens no PR (see D7) still emits its `run_summary` to the dispatcher over the API, so a
failed run is not a silent one.

**This is a change to what a run must produce, and the implementing spec owns it.**

### D6 — The outcome taxonomy is fail-loud

Every run emits exactly one structured `run_summary`. A specific outcome maps to a coarse status:

| coarse | meaning |
|---|---|
| `shipped` | gate green, PR opened |
| `deferred` | ran, produced nothing to ship, said why |
| `noop` | nothing to do — already satisfied |
| `failed` | anything else |

Two rules carry the weight, both ported from the prototype:

1. **An unknown outcome reads as `failed`.** Not as unknown, not as pending.
2. **A run that exits still tagged `started` crashed before classifying itself** — and is
   therefore `failed`.

This is "green is not proof" expressed as a status mapper. `failed` notifies over ntfy; everything
else is quiet and joins the `loop-doctor` corpus.

### D7 — No green `verify.sh`, no PR

The single most important divergence from the prototype, which ships whatever the agent committed
with the agent's own summary as the only check.

Here the gate decides done. A run whose gate is not green opens **no PR at all**, or at most a
draft hard-labelled `gate:failed` — and the label is applied by the harness after the loop, never
requested of the model. Structural enforcement beats prose instruction: agents observably skip
prose, and today's session produced nine attempts that dropped an instruction they had been given
explicitly.

### D8 — The registry is thin; the Job is the source of truth for liveness

The dispatcher keeps an index of runs — event id, repo, spec, strategy, Job name, coarse status.
It does **not** become a database of run history. Liveness is read from the Job object; durable
history is the `run_summary` in the PR and the `loop-doctor` corpus.

Rationale: a registry that owns history is a registry that must be backed up, migrated and
reconciled, and cliff 2 says the always-on component is exactly where that weight must not land.

### D9 — The HTTP API is cluster-internal, and its MCP client is a SEPARATE server

`launch_run(repo, spec, strategy)`, `run_status`, `list_runs`, `cancel_run`, `fetch_evidence`.

No ingress. The laptop reaches it through the existing private-network path, and the MCP server is
a **client** of this API rather than a second copy of the machinery. That answers the standing
"orchestrator from the laptop or a permanent fixture" question with *both, split correctly*: the
dispatcher is the fixture, the laptop gets a handle.

**These tools do not go into `mcp-homelab`.** They belong to a separate `mcp-harness` server, as
`fleet-dispatch.md` item 4 already names it.

**The reason is the concern boundary, not the risk.** `mcp-homelab` is *cluster administration* —
DNS, media, backups, certificates, Flux reconciliation. `mcp-harness` is *loop infrastructure* —
launching runs, reading their status, fetching their evidence. Two domains, two audiences, two
toolsets. An agent administering the cluster has no business dispatching fleet runs, and a fleet
orchestrator has no business restarting Jellyfin or rebuilding Pi-hole's gravity.

**And the split runs both ways**, which is the half easily missed. It is not only that a
diagnostic agent should not gain `launch_run`; it is equally that a fleet orchestrator should not
inherit `restart_deployment`, `update_pihole_gravity` or `trigger_backup`. Folding either into the
other hands each audience a toolset containing a domain it never asked for.

What follows from that boundary, rather than motivating it:

- **Capability scoping.** `cluster-diagnostics` fans out with `mcp-homelab` read-only. If
  `launch_run` lived there, every agent given diagnostic access would silently also be able to
  spin up compute and open PRs.
- **RBAC.** `mcp-homelab` runs under a cluster-wide `ClusterRole` with 21 resource rules.
  `mcp-harness` only speaks HTTP to the dispatcher and needs **no cluster RBAC at all** — folding
  it in would attach it to that grant for nothing.
- **Precedent.** The cluster already runs one MCP server per domain — `mcp-homelab`,
  `local-llm-mcp`, `kiwix-mcp`. A fourth for the fleet follows the established shape rather than
  overloading the first.

### D10 — Who owns what, concretely

The seam only works if both sides know their half. **The rule: the repo that owns the code owns
its build; the cluster owns everything needed to run it.**

**`mtgibbs/harness` owns (framework):**

| thing | status |
|---|---|
| dispatcher source + its Dockerfile | to write |
| `docker/loop-executor.Dockerfile` | **exists** (`20260828a-exec-container`) |
| `scripts/run-loop.sh` and the loop machinery the worker invokes | exists |
| this contract | this document |
| **CI that builds and pushes both images, multi-arch** | **does not exist — see the gap below** |

**`mtgibbs/pi-cluster` owns (instance):** everything required to run it, following the shape
`clusters/pi-k3s/review-hub/` already uses.

| thing | why |
|---|---|
| `clusters/pi-k3s/harness-dispatch/` — `namespace`, `deployment`, `service` (ClusterIP, no ingress), `kustomization` | the always-on fixture |
| `serviceaccount` + **namespaced `Role`** + `rolebinding` for `batch/v1` Jobs | D4; deliberately narrower than `mcp-homelab`'s cluster-wide grant |
| a **second namespace for loop Jobs**, with `ResourceQuota` and `LimitRange` | cliff 5 — loop Jobs share the Pis with Pi-hole and media |
| `external-secret.yaml` — Matrix token, the PR-opening bot identity, the LiteLLM key | secrets stay in 1Password; only `op://` paths in git |
| a numbered Kustomization entry in `flux-system/infrastructure.yaml` | that file is the deploy-order DAG; review-hub is #29 |
| `image-automation.yaml` | the established auto-bump pattern |
| Homepage tile + AutoKuma monitor | the `add-service` convention |
| **node placement** | see below |

**Node placement is not optional here.** The cluster is three Pi 5s at 8 GB and one Pi 3 at 1 GB,
and `ARCHITECTURE.md` already restricts the Pi 3 to lightweight services. A loop Job scheduled
there will fail or evict something that matters. Both the dispatcher and the Jobs need a
nodeSelector or affinity keeping them on the Pi 5s — and the images must be `linux/arm64`, which
is why item 2's multi-arch requirement is load-bearing rather than tidy.

**Credential reuse before minting.** The PR-opening identity should be an existing role-scoped bot,
not a new per-service token — `feedback_credentials_scale_by_role`: a bot gets one identity usable
across repos. The Matrix token is the existing agent-bus service-bot identity. Only genuinely new
credentials get new 1Password items.

### The gap this exposed: nothing builds either image

`mtgibbs/harness` has **no `.github/` directory at all**. `docs/loop-container.md` documents a
manual `docker buildx … --push` for the loop-executor image, which is right for a one-off
verification and wrong for a fleet that pulls the image on every Job.

The precedent is `pi-cluster/.github/workflows/build-review-hub.yml` — multi-arch build on push to
main, with Flux ImageUpdateAutomation bumping the manifest. But it lives in `pi-cluster` because
review-hub's *code* lives there. The dispatcher's code lives here, so **the workflow belongs here**,
and this repo has never had one.

That is a prerequisite for item 3's implementation and a small piece of work in its own right:
one workflow, two images (`harness-dispatch`, `loop-executor`), `linux/amd64,linux/arm64`, pushed
to GHCR, packages flipped public after first push.

## Consequences

**Accepted:**

- A second Job-creating identity in the cluster. Not novel — `mcp-homelab` has held
  `batch/jobs: [create]` for `trigger_backup` — but it is scoped to a namespaced `Role` rather
  than that precedent's cluster-wide `ClusterRole`, and it is worth reviewing on its own merits
  rather than as a detail of this design.
- The dispatcher becomes a permanent fixture to operate: an always-on Deployment with a Matrix
  token, an event-id ledger, and a cursor.
- D5 changes what a run must produce. The implementing spec has to define `run_summary` and make
  it travel, which is work that did not exist before this ADR looked at cliff 4 closely.

**Deliberately not in v1:** review/CI feedback modes; A/B runtime lanes (the executor-binding seam
gives these back for free via a strategy `.conf` whenever wanted); any second verb; any public
ingress.

**Preconditions before the implementing spec can be gated end to end:**

0. **Image CI in this repo** (D10). Nothing builds either image today; the fleet cannot pull what
   nobody publishes.
1. Item 2's runbook executed on a host with docker — the loop-executor image must build for
   `linux/arm64` and a containerised run must differ from a local one only in `binding`.
2. `harness#15` — attempt records currently ship with `outcome` and `duration_s` never populated.
   D6's taxonomy is built on `outcome`. **The field the status mapper reads is the field that is
   empty today**, so this is a blocker for D6 rather than a tidy-up.

## The test this design has to keep passing

From `fleet-dispatch.md`'s simplicity bar — one command locally, one message remotely, one place
to look when it breaks, and adding a repo to the fleet means that repo adds `specs/` and the
dispatcher changes not at all.

If a future change to the dispatcher is required in order to onboard a repo, that change is the
signal that this ADR has been violated.
