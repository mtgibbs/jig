# Bringing your own executor

**Status:** guide, 2026-08-30. Owner: Matt.

This document exists so that adding Claude, Gemini, or an agent nobody here has heard of needs
**no PR against this repo**. If you find yourself editing `scripts/` to add a model, something has
gone wrong — read the table below and find the layer you actually meant to change.

---

## 1. Three layers, and which of them varies

| layer | artifact | varies |
|---|---|---|
| the loop | `run-task.sh`, `run-loop.sh`, `ralph-*.sh`, `specs/lib/` | never — it is the invariant |
| the strategy | `<name>.conf` — `STRATEGY_PHASES` plus operator-layer bindings | per run, named on the wire |
| the binding + its CLI | `exec-<tool>.sh` plus the executable it drives | **per image — the extension point** |

The loop is the part that must not vary: it is what makes two runs comparable, and the evidence
corpus is worthless if the machinery underneath it moved. The strategy is chosen per run and
travels on the dispatch intent. The binding is where your agent goes.

`ghcr.io/mtgibbs/harness-base` is the loop with **no model CLI in it at all**. That is not an
oversight — a base carrying one vendor's CLI is a base that has already chosen for you, and the
image is public precisely so `FROM harness-base` works for someone who is not this account.

## 2. The worked example

Four files. Copy them.

```dockerfile
# Dockerfile
FROM ghcr.io/mtgibbs/harness-base:0.1.0

# 1. your CLI. This is the ONLY thing the derived image adds.
RUN npm install -g @your-vendor/your-cli

# 2. your binding and your strategy, into the harness tree.
COPY exec-yourtool.sh  $HARNESS_HOME/scripts/exec-yourtool.sh
COPY build-yours.conf  $HARNESS_HOME/scripts/loops/build-yours.conf
RUN chmod +x $HARNESS_HOME/scripts/exec-yourtool.sh
```

```bash
# exec-yourtool.sh — one prompt in on stdin, the agent's work on the tree, output on stdout.
# Model it on scripts/exec-qwen.sh; the contract is that narrow on purpose.
#!/usr/bin/env bash
set -euo pipefail
exec your-cli --print --dangerously-allow-writes "$(cat)"
```

```bash
# build-yours.conf
STRATEGY_DESC="build-converge driven by your-cli"
STRATEGY_PHASES="build"
STRATEGY_TOOLS="your-cli"          # preflighted; an absent binary stops the run before any work
export RALPH_EXEC="$HARNESS_HOME/scripts/exec-yourtool.sh"
```

Then dispatch against it. The strategy name selects both the phases and — through
`HARNESS_WORKER_IMAGE_BUILD_YOURS` — the image that can run them:

```
@harness fix myrepo specs/my-feature build-yours
```

`STRATEGY_TOOLS` is worth the one line. Without it, `build-yours` on an image with no `your-cli`
fails as a confusing shell error partway through a build phase; with it, the run stops at preflight
naming both the missing executable and the strategy that declared it.

## 3. Credentials: the harness ships none

**The harness ships no credentials, no API keys, and no model weights.** Not in the base, not in
the loop, not in any conf in this repo. There is no key here that you are failing to find.

Auth belongs to the **derived image and the operator** — your `Dockerfile`, your secret, your
`envFrom`. The binding reads it from the environment like any other program. This is the boundary
that lets the base be public.

### The contract is a set of names

`exec-opencode.sh` acquires nothing — it takes provider configuration from the environment and
execs. So what a worker needs is a set of **variable names**, and every context supplies the same
names its own way:

| variable | what it is |
|---|---|
| the provider key | whatever your CLI reads — `HARNESS_LITELLM_KEY`, `ANTHROPIC_API_KEY`, yours |
| `HARNESS_REPORT_URL` | the coordinator to report to. Unset means report nothing, silently and deliberately |
| `HARNESS_REPORT_TOKEN` | the bearer token presented when reporting |
| `HARNESS_CLONE_PAT` | the clone credential: a GitHub PAT, supplied through the credential helper — never in a URL. Read-only on contents; it is not the outcome PAT |
| `HARNESS_OUTCOME_PAT` | reserved: the identity that pushes a branch and opens a PR. Nothing consumes it yet |

| context | how they arrive |
|---|---|
| a laptop | already exported; `oc` reads Keychain or 1Password |
| a local container | `docker run -e` / `--env-file` |
| a k8s Job | `envFrom` a Secret, named by `HARNESS_WORKER_SECRET_<STRATEGY>` |

**A local run needs no Kubernetes concept at all.** `envFrom` is not rendered when nothing is
configured, so the dispatcher's Job body is byte-identical to what it was before any of this
existed, and a laptop or a `docker run` never encounters it. That is the property this design is
arranged around — the fleet is not a prerequisite for using the harness.

Secrets are resolved **per strategy**: `HARNESS_WORKER_SECRET_BUILD_CODEX` falls back to
`HARNESS_WORKER_SECRET` and then to nothing, never to a sibling strategy's. A `build-codex` worker
therefore never holds the LiteLLM key it would never use.

`HARNESS_CLONE_PAT` and `HARNESS_OUTCOME_PAT` are named as a pair on purpose. Earlier drafts called
the first one `HARNESS_GITHUB_PAT` — written before these were two identities, and a name that says
"the GitHub PAT" is the single-identity assumption this design exists to remove. If you are writing
the entrypoint that populates `~/.git-credentials`, `HARNESS_CLONE_PAT` is the variable it reads,
and it is the only one of the two that a worker which never lands work should hold at all.

### Three identities, and what each may do

| identity | held by | may |
|---|---|---|
| dispatch API token | the coordinator | create compute — launch Jobs |
| clone credential | every worker | read the repo it was handed |
| outcome PAT | a worker that lands work | push a branch, open a PR — and **never launch compute** |

The last two are separated on purpose. One PAT doing both means a worker that only ever needed to
read is holding the credential that can write. And the worker is the **least-trusted component in
the system**: it runs a model that writes code into a working tree and then executes that
repository's own `verify.sh`. Its credentials should be the narrowest in the fleet, not the widest
— which is also why the outcome PAT may never launch compute. A worker that can start more workers
turns one compromise into a fleet.

## 4. Two different things are called "container"

Read this section before you write anything, because conflating these two produces
docker-in-docker and a very confusing afternoon.

| | `exec-container.sh` | an in-pod binding |
|---|---|---|
| where the loop runs | on the **host** | **already inside the pod** |
| what the binding does | starts a fresh container per prompt | talks to its CLI or an API over the network |
| when you want it | a laptop with no CLI installed locally | a dispatched Kubernetes Job |

`scripts/exec-container.sh` is a binding that runs the loop **on the host** and sends each prompt
into a throwaway container. In a dispatched Job the situation is inverted: the loop is already
inside the container, so its binding is an ordinary `exec-*.sh` that invokes a CLI present in that
same image. **If you are writing a derived image, you want the second one.** Nesting the first
inside a pod is the mistake this table exists to prevent.

## 5. What a consumer repo looks like

A repo the harness works on carries its specs and its gates, and **no vendored harness**:

```
specs/<feature>/spec.md, verify.sh, tasks.txt, tasks/<T>/verify.sh
.harness/loops/*.conf        # optional — your own strategies, or shadow a built-in
.harness/exec-*.sh           # optional — your own bindings
```

That is the whole convention. No copy of `assert.sh` — the gates resolve it from `$HARNESS_HOME`
with the in-repo path only as a fallback, so a repo that vendors one gets a copy that drifts and
buys nothing.

A conf in `.harness/loops/` is preferred over a built-in of the same name, so you can shadow
`build-converge` without forking anything.

**Sourcing a conf from the worked repo executes shell from that repo.** That is worth saying out
loud, and it is not a new hole: the loop already runs that repo's `verify.sh` and already hands an
agent write access to its working tree. A repo you would not trust to run a strategy conf is a repo
you should not be pointing the harness at in the first place.

## 6. What this does NOT provide

Stated plainly, because a reader who assumes otherwise finds out inside a pod that is already being
deleted:

- **No Job body.** The base image is not a fleet worker. The Kubernetes Job spec — its
  `nodeSelector`, its pull secret, its `envFrom` — lives in the deploy repo, not here.
- **No code egress.** The loop commits to its worktree and, on success, **prints** the `git push`
  and `gh pr create` commands. Nothing runs them. Bot identity, PR body, and what happens when the
  gate is red are decisions a separate spec owns.
- **No credential provisioning.** See §3. Provisioning is the operator's, and nothing in this repo
  will create, mount, or rotate a secret for you.
