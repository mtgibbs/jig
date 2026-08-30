# Spec: the dispatcher ships as an image, and the worker it launches can clone

**Status:** draft, 2026-08-30. Owner: Matt.

Tools: git python3 bash
MCP: none
Permissions: read, write, bash

## 1. Why · [R — Requirements]

Every other half of fleet dispatch is finished. `dispatcher.py` renders a Job, resolves the image
and the secret per strategy, and dedupes on event id. `api.py` serves the dispatch endpoint.
pi-cluster has landed the namespace, the quota, the LimitRange, the RBAC, the pull secret on the
`default` ServiceAccount and both worker Secrets, and registered it with Flux.

**None of it can run.** `scripts/dispatch/dispatcher.py` and `api.py` are in no image —
`docker/coordinator.Dockerfile` copies `coordinator.py` and `board.html` and nothing else, and CI
builds exactly three images, none of which is a dispatcher. So there is nothing for pi-cluster's
`harness-dispatcher` ServiceAccount to be attached to, and the namespace it built sits empty.

And if it were launched today, the worker would fail at its first step. `run-task.sh` clones over
plain https and relies on a credential helper "already written by `entrypoint.sh`" — a file that
does not exist in this repo. A private clone would fail, as an **auth** error rather than a
missing-file one, inside a Job with no shell attached.

These are one unit of work because neither alone produces a run: an image that can launch a worker
that cannot clone is not closer to a dispatched run than no image at all.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A `harness-dispatcher` image exists, published by CI, carrying `dispatcher.py`, `api.py` and a
   `kubectl` it can actually invoke.
2. A worker handed `HARNESS_CLONE_PAT` can clone a private repo, and the token appears in no
   argv, no log and no image layer.
3. A run that is not handed one behaves **exactly** as it does today — the local `docker run` and
   laptop paths are unchanged, and no Kubernetes concept appears in them.
4. When a launch fails, the dispatcher says why. "No `kubectl` on PATH" and "the API server
   rejected this Job" are today the same signal, and in a Deployment that signal is the whole
   diagnostic surface.
5. Restarting the dispatcher does not re-launch work it has already launched.

## 3. Entities · [E — Entities]

| thing | what it is | where it runs |
|---|---|---|
| `harness-dispatcher` image | `dispatcher.py` + `api.py` + pinned `kubectl` | a Deployment in `harness-fleet` (pi-cluster) |
| `entrypoint.sh` | writes `~/.git-credentials` from `HARNESS_CLONE_PAT`, then execs `run-task.sh` | inside every executor image, via `harness-base` |
| the dispatch API token | `HARNESS_API_TOKEN` — the identity that creates compute | the dispatcher only, never a worker |

The dispatcher is the **only** component in the fleet that may create compute. That is why it is a
separate image from the executors rather than a mode of one: a single image that both launches Jobs
and runs model-written code is one compromise away from a worker that starts workers.

## 4. Approach · [A — Approach]

### The image follows the coordinator, not the base

`harness-base` bakes the loop, the scripts and a node runtime, because an executor runs model-written
code. The dispatcher runs neither a loop nor a model — it renders a dict and shells out once. So it
copies `coordinator.Dockerfile`'s shape: `python:3.12-slim`, stdlib only, non-root uid 10001, state
on a `VOLUME`, `ENTRYPOINT` straight to the script. Deriving it from `harness-base` would hand the
one component that can create compute an image full of things it does not use.

### `kubectl` is baked, and the swap is not this spec

`launch()` shells `kubectl apply -f -`, honours a `HARNESS_KUBECTL` override, and is asserted on by
`20260828f` and `20260829a` T05. Rewriting it onto the Python Kubernetes client is a defensible
change — typed errors, no binary, in-cluster config in one call — and it is **out of scope here**.
Packaging a thing and changing how it works are two changes, and doing both means a failure at
deploy time has two candidate causes. Bake a pinned `kubectl`, verify its checksum, move on.

### The entrypoint's obvious implementation is the wrong one

`harness-base` today ends with:

```
ENTRYPOINT ["/usr/bin/tini", "--", "/harness/scripts/run-task.sh"]
```

so `docker run <image> specs/fx --repo proj` passes those arguments to `run-task.sh`. The natural
way to insert an entrypoint — `ENTRYPOINT [... entrypoint.sh]` with `exec "$@"` and a `CMD` — makes
that same command try to execute `specs/fx`. **Every existing invocation breaks, and the error does
not mention the entrypoint.** So `entrypoint.sh` must end by exec'ing `run-task.sh` **by name with `"$@"`**, rather than
deferring to `CMD`, and the "Key contracts" comment at the top of the Dockerfile must be updated to
say so.

Resolve it **beside the entrypoint** — `$(dirname "$0")/run-task.sh` — not as the absolute
`/harness/scripts/run-task.sh`. The absolute path is correct in the image and untestable outside
it, and a gate that cannot run the thing it asserts on is how this trap survives review a second
time.

### Writing the credential without leaking it

`printf` into a file created at mode 0600, `git config --global credential.helper store`, and the
variable unset afterwards. Not `echo` into a world-readable file, not a URL, not `git config` with
the token in argv — argv is readable from `/proc` for the life of the process and lands in any
transcript that ships to the coordinator.

Unset means **no-op**: no file written, no git config touched, no message. A laptop run and a
`docker run` with no credential must be byte-identical to today, which is Outcome 3.

## 5. Scope · [S — Structure: boundary]

### In scope
- `docker/dispatcher.Dockerfile` + `docker/dispatcher.VERSION`, and its job in `build-images.yml`.
- `scripts/entrypoint.sh`, and the `harness-base` ENTRYPOINT change that reaches it.
- `launch()`'s failure reporting in `scripts/dispatch/dispatcher.py`.
- `docs/executors.md` — the entrypoint is the mechanism behind a contract it already documents.

### Out of scope
- **The Deployment.** It is pi-cluster's, named as step 7 of `clusters/pi-k3s/harness-fleet/README.md`,
  and it gets a spec there. This repo ships the image and the contract; the cluster runs it.
- **`loop-executor-codex`.** `harness-worker-build-codex` has credentials and no image, which is a
  real gap and a separate unit of work: a second executor image is `20260829a`'s pattern applied
  again, not part of making the first dispatch work.
- **Replacing `kubectl` with the Python client.** Argued above.
- **Code egress.** `HARNESS_OUTCOME_PAT` stays reserved and unconsumed; `run-task.sh` still prints
  the push and PR commands rather than running them.
- **Anything about `render_job`'s body.** Adding a field there is `20260830a`'s territory.

## 6. Prior decisions / facts the implementer must know · [S]

- **`launch()` never raises.** It returns an exit status, and on exception returns `1`. It captures
  `stderr` into a PIPE and then discards it. So "kubectl is not installed" and "the API server
  refused this Job" are today the same integer with no text. That is the defect Outcome 4 names.
- **`api.py` already refuses to serve without `HARNESS_API_TOKEN`** (`serve()` exits 1). The image
  must not supply a default, and no `ENV HARNESS_API_TOKEN=` line may appear in the Dockerfile.
  A default here is a dispatcher that accepts unauthenticated requests to create compute.
- **`already_seen()` / `record_seen()` read and write `HARNESS_LEDGER_PATH`**, and `record_run()`
  writes `HARNESS_REGISTRY_PATH`. If those default inside the image, a restart forgets every event
  and a redelivered webhook launches a second Job for work already running. Outcome 5 is a claim
  about where those default to, exactly as `COORD_STATE_PATH` is for the coordinator.
- **This container has no `docker`.** No gate in this repo can build or run an image, so every
  acceptance criterion below is written against the Dockerfile's *text* and against scripts run
  directly. What that leaves unproven is stated in §11 rather than papered over.
- **`HARNESS_CLONE_PAT`** is the pinned name (`docs/executors.md`, #67). Not `HARNESS_GITHUB_PAT`,
  which predates the identity split and survives only as a superseded line in `20260829a`.
- `20260829a` T04's gate exports both names with one sentinel value and greps run-task.sh's output
  for it. An entrypoint that echoes the token will turn that gate red, which is the intent.

## 7. Norms · [N — Norms]

- The image ships **no credential**, no key, no default token. Same rule as the base.
- Pin `kubectl` by version **and** verify its SHA256. An unverified `curl | install` in a component
  whose job is to create compute is the supply-chain shape this repo refuses elsewhere.
- Non-root, uid 10001, matching the coordinator. A dispatcher does not need to write to `/app`.
- Change no behaviour of a run that configures nothing.

## 8. Safeguards · [S — Safeguards]

- The dispatch API token appears in **no** worker secret and in no executor image. Only the
  dispatcher image and pi-cluster's Deployment env ever see it.
- `entrypoint.sh` writes the credential file at 0600 **before** any repository code is fetched, and
  never to a path inside a cloned tree.
- No `ENV` line in `dispatcher.Dockerfile` may name a token, key, PAT or secret.
- The entrypoint must not `set -x`, and must not print the value under any failure path.

## 9. Task breakdown · [O — Operations]

Four tasks, in `tasks.txt`, each with a gate under `tasks/`. T01 and T02 are independent of T03;
T04 depends on T03 existing.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- **AC-1** — The `harness-dispatcher` image shall copy `scripts/dispatch/dispatcher.py` and
  `scripts/dispatch/api.py`, and shall install a `kubectl` whose version is pinned to a literal in
  the Dockerfile.
- **AC-2** — The Dockerfile shall verify the downloaded `kubectl` against a SHA256 recorded beside
  the version, and shall fail the build when it does not match.
- **AC-3** — Where the Dockerfile declares environment, it shall declare no variable whose name
  contains `TOKEN`, `SECRET`, `PAT` or `KEY`.
- **AC-4** — The image shall declare a non-root `USER` with uid 10001.
- **AC-5** — The ledger and registry paths shall default to a directory declared as a `VOLUME`,
  such that a restart of the dispatcher preserves seen-event state.
- **AC-6** — When `launch()` fails, it shall return non-zero and emit the captured `stderr`, and a
  missing runner shall produce a message distinguishable from a rejected apply.
- **AC-7** — When `HARNESS_CLONE_PAT` is set, `entrypoint.sh` shall write `~/.git-credentials` with
  mode 0600 and configure the `store` credential helper before exec'ing `run-task.sh`.
- **AC-8** — When `HARNESS_CLONE_PAT` is unset, `entrypoint.sh` shall write no credential file,
  change no git configuration, and still exec `run-task.sh`.
- **AC-9** — `entrypoint.sh` shall not emit the credential value on any path, and shall not pass it
  as an argument to any command.
- **AC-10** — When `entrypoint.sh` is invoked with `specs/fx --repo proj --strategy build-converge`,
  those arguments shall reach `run-task.sh` unchanged and in order, with `run-task.sh` resolved
  beside the entrypoint rather than relying on `CMD` or on an absolute `/harness` path.
- **AC-11** — `build-images.yml` shall build and publish `harness-dispatcher` from
  `docker/dispatcher.Dockerfile`, tagged from `docker/dispatcher.VERSION`, on the same triggers as
  the coordinator.
- **AC-12** — `docs/executors.md` shall state that `entrypoint.sh` is what consumes
  `HARNESS_CLONE_PAT`, so the contract table's row points at a mechanism that exists.

## 11. Verification (the harness)

`specs/20260830b-dispatcher-image/verify.sh` plus a gate per task under `tasks/`, in this repo's
binary `ok`/`no` shape — `specs/lib/assert.sh` defines no `pend` on purpose, and a per-task gate
asserting only its own task has nothing to defer.

**Tier: STATIC + SCRIPT.** There is no `docker` in the container this runs in, so the gate reads
the Dockerfile as text and runs `entrypoint.sh` and `launch()` directly against stubs.

What that leaves **unproven**, to be checked at deploy time and not claimed here:

1. That the pinned `kubectl` actually runs on arm64 in the built image.
2. That `kubectl` in a pod picks up the ServiceAccount token with no kubeconfig. It is the standard
   in-cluster fallback and it is *expected* to work, but this gate cannot demonstrate it, and it is
   the single most likely thing to be wrong on first deploy. If it is: `HARNESS_KUBECTL` exists as
   the escape hatch, and it can point at a wrapper that passes `--server` and `--token` explicitly.
3. That a real private clone succeeds with the credential the entrypoint wrote.

Every one of those is a LIVE check against the cluster, in that order, and each one's failure is
loud and local rather than silent.

## 12. Open questions

- **OQ1** — Does the dispatcher image need `git`? Nothing in `dispatcher.py` or `api.py` shells to
  it today. Leaving it out keeps the image small and the blast radius smaller; adding it later is
  one line. Proposed: leave it out.
- **OQ2** — `harness-dispatcher` and `harness-coordinator` are two Deployments, two images and two
  ports for what a reader may reasonably expect to be one service. They are separate because one
  creates compute and one receives status, and merging them would put the dispatch API token in the
  process a human points a browser at. Recording this so the question is answered once rather than
  re-asked at every deploy.
