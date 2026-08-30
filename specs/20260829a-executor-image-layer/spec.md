# Spec: the executor is an image layer, not a fork

- **Status:** Draft v0.4
- **Owner:** mtgibbs
- **Constitution:** `specs/constitution.md` (+ `/CLAUDE.md` Core Mandates)
- **Touches:** `docker/harness-base.Dockerfile` (new), `docker/harness-base.VERSION` (new),
  `docker/loop-executor-opencode.Dockerfile` (renamed from `loop-executor`),
  `docker/loop-executor-opencode.VERSION`,
  `.github/workflows/build-images.yml`, `scripts/run-task.sh` (new), `scripts/run-loop.sh`,
  `scripts/exec-container.sh`, `scripts/exec-opencode.sh` (renamed from `exec-qwen.sh`),
  `scripts/ralph-build.sh` (the default binding), `scripts/run-loop.sh`, `scripts/supervise.sh`,
  `scripts/loops/*.conf`,
  `scripts/loops/README.md`, `specs/lib/assert.sh`,
  `scripts/dispatch/dispatcher.py`, `docs/executors.md` (new), `docs/loop-container.md`
- **Tools:** git, python3, bash
- **MCP:** none
- **Permissions:** write:docker/**, write:scripts/**, write:specs/lib/**, write:docs/**, exec:git, exec:python3

---

## 1. Why · [R — Requirements]

`specs/20260825c-executor-binding` made the executor a **parameter**: one build loop, a
2-to-6-line `exec-*.sh`, and a strategy file. It deleted a 204-line fork and the three specs that
policed its symmetry. That seam is the reason a third party could bring Claude, Gemini or their
own agent to this harness at all.

Four things now stand between that seam and a fleet that anyone can join.

**The image inverts it.** `docker/loop-executor.Dockerfile` installs opencode, carries **no
harness at all**, and sets `ENTRYPOINT ["opencode"]` — the image *is* the executor rather than a
host for one. Nothing in it can be extended: a Claude image would be a second Dockerfile that
also re-solves how the loop gets in, which is the 204-line fork wearing a container.

**The remote entry point has already forked — three ways.** `run-task.sh` lives in
`beelink-ansible` as three copies, one per `coding-harness-*` container, differing in workspace
root, positional-argument order and executor default. One of them carries a comment explaining
that `--repo` had to become a flag rather than a positional *"so deploy order stops mattering"* —
a workaround for drift between copies. It is the same defect the executor-binding spec removed,
one level up.

**A consumer repo cannot bring a binding.** `run-loop.sh` resolves strategies only from
`$SCRIPT_DIR/loops`, and every per-task gate opens with `. "$ROOT/specs/lib/assert.sh"` — the
*worked* repo. So a repo that follows the convention ("specs and gates, no harness") must still
vendor a copy of the assertion vocabulary, which then drifts.

**The dispatcher pins one image for every strategy.** `HARNESS_WORKER_IMAGE` is a single value,
so even a strategy that IS selectable cannot reach an image that can run it.

This spec restores the seam at the image, entry-point and dispatch layers, so that adding an
executor stays what §20260825c made it: a small file and a config entry, never a fork.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. The loop ships in a **public** image that carries no model CLI, and an executor image is that
   base plus one CLI — so `FROM harness-base` is the whole cost of a new executor.
2. There is **one** `run-task.sh`, it lives in this repo, and it reaches the loop through
   `run-loop.sh` — so the remote front door gets strategies, phases and the judge, not just
   `ralph-build.sh`.
3. A repo that is not this one can supply its own strategy, its own binding, and gates that
   source the harness's assertion vocabulary — without vendoring any harness file.
4. A strategy declares the executable it needs, and a mismatch between strategy and image fails
   in preflight naming the missing tool — not mid-run with a shell error.
5. Dispatch can ask for a strategy other than the default, and the image it lands on is one that
   can run it.
6. A laptop run of `scripts/run-loop.sh build-converge specs/<feature>` behaves **exactly** as it
   does today.

## 3. Entities · [E — Entities]

**Three layers, and which of them varies.** This table is the spec's thesis; every acceptance
criterion serves it.

| layer | artifact | varies |
|---|---|---|
| the loop | `run-task.sh`, `run-loop.sh`, `ralph-*.sh`, `specs/lib/` | never — the invariant |
| the strategy | `<name>.conf` — phases + bindings | per run, named on the wire |
| the binding + its CLI | `exec-<tool>.sh` + the executable it drives | **per image — the extension point** |

**`harness-base` image** — the loop with no model CLI. **Public**, so that `FROM harness-base`
works for someone who is not this account.

```
HARNESS_HOME=/harness          # the harness tree; scripts/ and specs/lib/ live under it
PATH                           # includes $HARNESS_HOME/scripts
ENTRYPOINT ["/usr/bin/tini", "--", "run-task.sh"]
contains                       # scripts/**, specs/lib/**, and the runtime below
does NOT contain               # any model CLI, any credential, any model weights, node
```

**The runtime, derived from the scripts rather than guessed.** The current `loop-executor`
installs `git ripgrep ca-certificates curl tini` and is missing two things the loop needs:

| | | when absent |
|---|---|---|
| `jq` | `ralph-judge.sh`, `ralph-log.sh` | judge **dies** (`die 1 "jq is required"`); the attempt record vanishes **silently** |
| `python3` | `loop-index.py`, `ralph-status.sh` fallbacks | the evidence index is never written |
| `git bash coreutils sed awk grep curl ca-certificates tini` | everywhere | nothing runs |

One missing tool, one loud path and one silent path, is itself a state a reader cannot tell
apart — so AC-1 asserts the runtime is **installed**, not that `COPY` lines exist.

Optional and guarded, absent from the base by design: `node` (codesheet only), `perl`
(`bound.sh`'s fallback; the container has `timeout`), `ripgrep` (the executor's, not the
loop's), `sqlite3`, `agent-bus`.

**`HARNESS_DIR` — baked or cloned, both supported.**

| state of `$HARNESS_DIR` | behaviour | who uses it |
|---|---|---|
| exists, is a git checkout | fetch + fast-forward to `$HARNESS_REF`, non-fatal on failure | Beelink `coding-harness-*` containers |
| exists, is **not** a git checkout | use as-is, no clone, no network | the fleet image (baked at its own version) |
| absent | clone `$HARNESS_REPO` at `$HARNESS_REF` | first run in a fresh workstation container |

**strategy search path** — ordered, first match wins:

```
$HARNESS_REPO_ROOT/.harness/loops/<name>.conf     # the consumer repo's own, wins
$HARNESS_HOME/scripts/loops/<name>.conf           # built-in
```

`HARNESS_REPO_ROOT` is the git toplevel of the repo being worked on. A consumer conf names its
binding relative to that root (`$HARNESS_REPO_ROOT/.harness/exec-claude.sh`).

**assertion-vocabulary resolution** — the same shape, so a consumer repo vendors nothing:

```
$HARNESS_HOME/specs/lib/assert.sh    # the harness's, wins
$ROOT/specs/lib/assert.sh            # fallback: this repo's own, today's behaviour
```

**strategy conf — the contract, extended by exactly one key:**

```
STRATEGY_TOOLS="codex"     # optional, space-separated; executables preflighted with command -v
```

**`run-task.sh`** — the remote front door. One file, flags only:

```
run-task.sh <spec-dir> [--repo <name>] [--branch <b>] [--base <b>] [--strategy <s>]
  --repo      default $HARNESS_REPO_NAME          bare name; rejected if it needs escaping
  --branch    default ralph/<spec>-<epoch>
  --base      default main
  --strategy  default build-converge              passed to run-loop.sh
  $HARNESS_WORKSPACE                              root the repo is cloned/worktreed under
```

**dispatch intent** — grammar widens by one optional trailing field:

```
@<mention> fix <repo> <spec>              -> strategy build-converge   (unchanged)
@<mention> fix <repo> <spec> <strategy>   -> strategy <strategy>
```

**strategy-to-image resolution** — env-configured, defaulted:

```
HARNESS_WORKER_IMAGE_<STRATEGY_UPPER_SNAKE>   # e.g. HARNESS_WORKER_IMAGE_BUILD_CODEX
HARNESS_WORKER_IMAGE                          # fallback, today's single value
```

## 4. Approach · [A — Approach]

Mirror what `specs/20260825c-executor-binding` did to the loop scripts, one level out: the thing
that varies becomes a layer, not a copy.

`loop-executor.Dockerfile` splits into `harness-base.Dockerfile` (the loop) and a thin `FROM
harness-base` file that adds opencode. The three `beelink-ansible` copies of `run-task.sh`
collapse into one `scripts/run-task.sh` here, reconciled to the flag-only argument shape all
three already reach for, and routed through `run-loop.sh` so the remote path gains strategies.
`run-loop.sh` and `assert.sh` gain search paths in the shape `ralph-build.sh` already established
for per-task gates in `specs/20260828i-per-task-gates` — **additive and fallback-first**, so a
missing `.harness/` directory means today's behaviour exactly. `parse_intent` widens by one
optional field, and the worker image is resolved from the strategy the way the namespace is
already resolved from the environment.

**Baked, not cloned — for the fleet only.** Today's `run-task.sh` clones the harness at runtime,
with the stated reason that *"a harness change is a `git pull` here, not an image rebuild."* That
is right for a long-lived workstation container a human attaches to. It is wrong for a Job that
lives thirty minutes: two runs of the same image would behave differently, and the evidence
corpus could not attribute a regression to a harness version. So the fleet image bakes the
harness at its own version and `$HARNESS_DIR` is a plain directory; the workstation containers
keep cloning. One script serves both — the only change is that a non-git `$HARNESS_DIR` is used
as-is instead of triggering a clone.

**`loop-executor` becomes `loop-executor-opencode`.** After the split, the thing that executes
loops is the BASE — it holds `run-loop.sh`, `ralph-build.sh`, the gates, and its entrypoint is
`run-task.sh`. The derived image adds one CLI, so the generic name now describes the base better
than the image carrying it. And the name has to scale: `loop-executor-codex` and
`loop-executor-claude` are the point, and whichever one keeps the bare name reads as the
canonical one — the opinionation the split exists to remove.

The concrete cost of not renaming lands in T5's config, where the name becomes load-bearing:
`HARNESS_WORKER_IMAGE = ghcr.io/mtgibbs/loop-executor` does not tell a reader whether that is
*the opencode image* or *the default for any strategy*, and the dispatcher's fallback behaviour
depends on which they believe. Renamed, the fallback reads as "the opencode image happens to be
the default", which is what it is. Doing it now costs one VERSION file, one matrix entry and one
line in `exec-container.sh` — nothing outside this repo names the image yet (§6). Doing it after
the fleet manifests land is a coordinated change across two repos. The existing
`loop-executor:0.1.0` tag stays where it is; the package simply stops receiving new ones.

**The default binding drives `opencode`, not `oc`.** `exec-qwen.sh` execs `oc`, which is not in
this repo and not in the image: it is a private laptop shim that reads a LiteLLM key from the
macOS Keychain, falls back to `op read op://pi-cluster/opencode-coder/password`, exports
`OPENCODE_QWEN_KEY`, applies its own watchdog, and execs `opencode`. Three of those four things
do not belong in a binding. **Credential acquisition is the operator's** — Keychain or 1Password
on a laptop, `envFrom` a Secret in a Job — and the **watchdog is already the loop's**
(`run_bounded`), which `exec-qwen.sh`'s own header says. What is left is the binding: take
provider configuration from the environment and exec `opencode`. That is what makes the derived
image runnable by someone who is not this account, and it is the single change that decides
whether Claim 2 (§2 outcome 3) is real. `oc` survives as a laptop convenience that sets the env
and calls the same binding.

**`node` is not in the base.** The loop needs `bash`, `git`, `jq` and `python3`; only
`gen-codesheet.mjs` needs node, and the derived images that want it (`opencode` and
`claude-code` are both npm) install it themselves. The cost is that `RALPH_SHEET` defaults ON
and is guarded by `command -v node`, so in a node-less image the codesheet turns off **silently**
— the failure this repo catalogues most. So the base excludes node AND the absence is announced
once per run, rather than being discovered by comparing token counts.

**Rejected: one image per executor, built here.** It scales by fork — every new agent is a PR to
this repo, which is the thing §20260825c removed. The base image is the seam precisely so the
harness does not have to know who its executors are.

**Rejected: making `exec-container.sh` the in-pod binding.** It is a binding that *containerises*
— the loop runs on the host and each prompt goes into a fresh container. Inside a k8s Job the
loop is already in the pod, so using it there means docker-in-docker. In-cluster the pod uses a
**direct** binding (`exec-qwen.sh` over the network to LiteLLM). Same word, two roles; §7 makes
the contrast explicit because the constitution's similar-but-different trap is exactly this.

## 5. Scope · [S — Structure: boundary]

### In scope
- `docker/harness-base.Dockerfile`, `docker/harness-base.VERSION`
- `docker/loop-executor-opencode.Dockerfile` + `.VERSION`, **renamed** from `loop-executor`
- `.github/workflows/build-images.yml` — the base entry, ordered before the derived build
- `scripts/run-task.sh` — new, the single reconciled remote entry point
- `scripts/run-loop.sh` — strategy search path, `STRATEGY_TOOLS` preflight, `--strategy` plumbing
- `scripts/exec-container.sh` — the `:latest` default and the renamed image (see §6)
- `scripts/exec-opencode.sh` — renamed from `exec-qwen.sh`; drives `opencode` from env instead
  of the private `oc` shim
- the landed gates that name the binding — `20260825c`, `20260828a`, `20260827a` (see §6)
- `scripts/loops/*.conf` — every built-in strategy declares `STRATEGY_TOOLS`
- `specs/lib/assert.sh` + the gates that source it — `HARNESS_HOME`-first resolution
- `scripts/loops/README.md`, `docs/executors.md`, `docs/loop-container.md`
- `scripts/dispatch/dispatcher.py` — `parse_intent` grammar, strategy-to-image resolution

### Out of scope
- **`beelink-ansible`.** Deleting the three `run-task.sh` copies, dropping the symlink, moving
  the harness clone into `entrypoint.sh`, and retiring `specs/harness-multi-repo/verify.sh` are a
  **follow-on PR in that repo**, and it must land *after* this one — the containers must have a
  `scripts/run-task.sh` to point at before their own copies go. See §6 for the intended shape.
- **The k8s Job body.** Pull secrets, `envFrom`, resources, ServiceAccount, the `harness-fleet`
  nodeSelector and namespace are the deploy-side follow-on in `pi-cluster`. This spec makes the
  image, the entry point and the strategy composable; it renders no Job field.
- **Code egress.** Nothing in the loop pushes a branch or opens a PR — `run-task.sh` prints the
  commands for a human. That is correct for an attached workstation and fatal for an ephemeral
  Job, but it is its own spec (see OQ1).
- `exec-qwen.sh`, `exec-codex.sh` — the binding contract does not change.
- `ralph-build.sh`, `ralph-judge.sh`, the gates, the evidence writers, the coordinator.
- Writing an `exec-claude.sh`. This spec makes one possible; it does not ship one.
- Credential provisioning, egress policy, Authelia.

## 6. Prior decisions / facts the implementer must know · [S — Structure: system fit & deps]

**Verified against both repos, GHCR and the live cluster on 2026-08-29.**

### The image

- `docker/loop-executor.Dockerfile` today (to be renamed `loop-executor-opencode`):
  `FROM node:22-bookworm-slim`, apt-installs
  `git ripgrep ca-certificates curl tini`, `npm install -g opencode-ai@1.17.10`,
  `WORKDIR /home/agent/run-container`, `ENTRYPOINT ["/usr/bin/tini", "--", "opencode"]`.
  It contains **no harness**. The apt set and the tini wrapper move DOWN into the base.
- `ghcr.io/mtgibbs/loop-executor` holds exactly **one** tag: `0.1.0`. It is currently private.
- **`ghcr.io/mtgibbs/loop-executor:latest` does not exist**, but `scripts/exec-container.sh`
  defaults `LOOP_IMAGE` to it. CI pushes only the VERSION-file tag, deliberately —
  `docs/loop-container.md` says a mutable `:latest` would defeat the `ImagePolicy` pattern — while
  that same doc's manual-build fallback pushes `:latest`. The binding's default is therefore
  broken unless someone ran the manual build. Fix the default to a pinned tag and fix the doc's
  fallback command to match; do not start pushing `:latest`.
- **`harness-base` is to be PUBLIC.** Decided 2026-08-29: the implementation is going to public
  space eventually, and a private base cannot be extended by anyone else, which defeats the
  point. The base contains `scripts/**` and `specs/lib/**` — no credentials, no PII. Follow
  `docs/loop-container.md`'s existing note: a GHCR package must be flipped public after first
  push (`gh api -X PATCH /user/packages/container/harness-base -f visibility=public`).
- `.github/workflows/build-images.yml` is a matrix over `{image, dockerfile, version-file}`,
  triggered on push to `main` under `docker/**`, building `loop-executor` and
  `harness-coordinator` for `linux/amd64,linux/arm64`. **A matrix runs its entries in parallel**,
  so a third row would race: the derived build would pull a base tag still being built. Use a
  separate base job with `needs:` — decided over `max-parallel: 1` because the constraint should
  be stated in the workflow graph, not implied by declaration order that a later edit can shuffle.
  Note this only bites when base and derived change in the same push, which makes it an
  intermittent failure and therefore worse to leave implicit.

### `run-task.sh` as it exists today

Three copies under `beelink-ansible/files/coding-harness-{qwen,claude,codex}/`, `COPY`'d into
each image by `playbooks/50-ai-stack.yml` (tag `harness-images`) and invoked as
`/usr/local/bin/run-task.sh`. What they share, and must be preserved:

- `--repo <name>` is scanned out of `"$@"` **as a flag, in any position**, and a name containing
  anything outside `[A-Za-z0-9._-]` is **rejected, never sanitised** — the value becomes both a
  path and a URL.
- The target repo is cloned on demand over plain `https` with **no token in the URL**;
  `entrypoint.sh` has already written `~/.git-credentials` from `HARNESS_GITHUB_PAT`, so no
  secret reaches argv or the logs. Keep that property exactly.
- A worktree is created off `origin/$BASE_BRANCH` on a throwaway branch. `git worktree remove
  --force` **and** `git worktree prune` both run before `add`: `rm -rf` alone leaves the worktree
  registered in `.git/worktrees`, which made a spec runnable exactly once per container.
- `--base` exists because a spec authored on `spec/<feature>` by another session is invisible to a
  worktree cut from `origin/main`. Found for real 2026-07-09.
- A path that is present but not a git checkout is **refused, never clobbered**.
- The harness is resolved from `$HARNESS_DIR`, **not** from the target repo. The comment records
  why: `notes-from-hearing` deleted its harness copy exactly as asked, and from that moment could
  not be dispatched to at all.

Where they differ, and how to reconcile:

| | qwen | claude / codex |
|---|---|---|
| workspace root | `/home/agent/workspace`, repo at `$WS/<repo>`, worktree at `$WS/tasks/<spec>` | `/Users/mtgibbs/dev`, worktree as a **sibling** `<repo>-<spec>` |
| positionals | 3 (`spec`, `branch`, `base`) | 4 (`spec`, `repo`, `branch`, `base`) |
| executor | `exec-qwen.sh` | codex: `exec-codex.sh` + `RALPH_AGENT=codex` + `RALPH_SHEET=off` |
| preflight | none | codex only: `codex login status`, fail early |

Reconcile to **flags only** past positional 1, with `$HARNESS_WORKSPACE` naming the root and the
sibling-worktree layout (it is what the constitution's manual pattern shows). The per-executor
env block is exactly what a strategy conf already is — `build-codex.conf` sets `RALPH_AGENT` and
`RALPH_SHEET` today — so routing through `run-loop.sh --strategy` deletes that difference rather
than porting it. The codex login check does **not** fold cleanly; see OQ3.

- **`run-task.sh` invokes `ralph-build.sh` directly, never `run-loop.sh`.** The remote path
  therefore has no strategies, no phases and no judge — which is why `STRATEGY` on the dispatched
  Job env has nowhere to land today.
- On success it prints `cd $TASK_DIR && git push -u origin $BRANCH && gh pr create` for a human.
  **Nothing in this repo runs `git push` or `gh pr create`.** Preserve the print; do not add the
  push (out of scope, OQ1).
- **Intended follow-on shape in `beelink-ansible`** (do not build here): `entrypoint.sh` clones or
  fast-forwards the harness — it already holds the credentials and already clones the work repo —
  and `/usr/local/bin/run-task.sh` becomes a **symlink** to `$HARNESS_DIR/scripts/run-task.sh`. A
  symlink is a path, not a copy, so there is genuinely one implementation.

### What `oc` is

Read at `~/.local/bin/oc` on 2026-08-29. It is a laptop shim, not a harness file:

1. reads a LiteLLM/qwen key from the macOS Keychain (`security find-generic-password -s
   opencode-qwen`), falling back to `op read op://pi-cluster/opencode-coder/password`
2. exports `OPENCODE_QWEN_KEY`, plus a homelab MCP key for its `ops` agent
3. applies `OC_RUN_TIMEOUT` (default 600s) to `oc run`
4. execs `opencode`

Only (4) is the binding. (1) and (2) are the operator's, (3) is the loop's — `ralph-build.sh`'s
`run_bounded` already bounds the executor, which is why `exec-qwen.sh` carries no timeout and
says so. A container has no Keychain and no `op`, so every step but (4) is unreachable there.

### What the rename drags with it

`exec-qwen.sh` is named functionally in six places outside itself. All six move in T1, or the
rename lands as a second name and a red gate:

| file | what it does with the name |
|---|---|
| `scripts/ralph-build.sh:53` | `RALPH_EXEC_CMD="${RALPH_EXEC_CMD:-$_SD/exec-qwen.sh}"` — the default |
| `scripts/run-loop.sh:73` | the MCP-config fallback `exec-qwen.json`, derived from the binding's basename |
| `scripts/supervise.sh:77` | the process-pattern list the supervisor matches on |
| `specs/20260825c-executor-binding/verify.sh:23,40,42,101` | asserts the default **by name**, and `cat`s the file for its shrink assertion — a missing path breaks the measurement, not just the check |
| `specs/20260828a-exec-container/verify.sh:26,28,29,141` | treats it as the binding contract's reference implementation and **exits 1** if absent |
| `specs/20260827a-spec-manifest/verify.sh:162` | runs it directly as `RALPH_EXEC_CMD` |

`specs/20260828n-mcp-reachable`'s fixtures also use the name, for files they create in their own
temp dir. Those are self-contained and stay as they are — renaming them is churn, not a fix.

**Not in scope, and worth knowing:** `scripts/ralph-judge-exec-qwen.sh` is a different binding —
the judge's executor — and it hard-requires `oc` on PATH (`:12`). So `build-then-judge` and
`judge-refine` still cannot run in an image after this spec. That is the same defect one layer
over, and it is its own change.

### The scripts

- **`run-loop.sh` sources the strategy conf BEFORE any loop script runs, and `ROOT` is not set at
  that point.** `ralph-build.sh:215` is what exports `ROOT="$(git rev-parse --show-toplevel)"`,
  and it runs later. A conf cannot reference `$ROOT`; `run-loop.sh` must compute and export
  `HARNESS_REPO_ROOT` itself before the `. "$ENV_FILE"` line.
- `run-loop.sh` already has a fatal preflight for the **spec's** `Tools:` field — `command -v`
  each, accumulate misses, exit **3** with "container needs attention, not another retry".
  `STRATEGY_TOOLS` joins that same accumulation and reuses that exit code and phrasing; do not add
  a second preflight block.
- `scripts/loops/README.md` states the conf contract: a strategy file may ONLY declare
  `STRATEGY_DESC` / `STRATEGY_PHASES` and export env knobs the loop scripts already accept. It may
  not define functions, add stopping logic, or invoke anything. `STRATEGY_TOOLS` is a declaration,
  so it fits without widening the contract.
- **Every per-task gate opens `. "$ROOT/specs/lib/assert.sh"`** — verified across
  `20260828k/l/m/o`. `ROOT` is the worked repo, so a consumer repo must vendor `assert.sh` today.
  Resolve `$HARNESS_HOME` first with a `$ROOT` fallback, and update the existing gates' source
  line to the resolved form. This repo's own gates must keep passing unchanged, since here the
  two paths point at the same file.

### Dispatch

- **The HTTP API is already open on strategy.** `scripts/dispatch/api.py:59` reads
  `body.get("strategy", "build-converge")` and passes it to `launch_run`. Only the **text** path is
  pinned: `dispatcher.py:parse_intent` requires exactly 4 whitespace-separated parts and hardcodes
  `build-converge`. Widen the parser; the API needs no change.
- `dispatcher.py:launch_run` takes `image=` from the caller and `api.py:73` sources it from a
  single `HARNESS_WORKER_IMAGE`. One image serves every strategy today.
- `dispatcher.py:render_job` puts `REPO`, `SPEC`, `STRATEGY` on the container env and nothing else.
  Out of scope here beyond which image the Job names.

## 7. Norms · [N — Norms]

- **Naming.** Image `harness-base`; `docker/harness-base.VERSION`; `HARNESS_HOME` for the
  in-image harness root, `HARNESS_REPO_ROOT` for the repo being worked on, `HARNESS_WORKSPACE`
  for the clone root. Do not overload `ROOT` — `ralph-build.sh` owns it and means the worked repo.
- **Fallback-first, like the per-task gate resolver.** Every new path is checked, and its absence
  means the existing behaviour, not an error. A repo with no `.harness/` is not misconfigured.
- **One entry point.** Anything `run-task.sh` needs to vary by executor belongs in a strategy
  conf, not in a second copy of `run-task.sh`. That rule is the whole spec; state it in the file.
- **Document the similar-but-different pair.** `docs/executors.md` must contrast
  `exec-container.sh` (loop on host, prompt into a container) with an in-pod direct binding (loop
  in the container already). The constitution names this trap; here it has two things called
  "container" one line apart.
- **Error messages name the missing thing and the fix**, matching the existing preflight's voice:
  which tool is missing, and that the container needs attention rather than another retry.
- **Comment the load-bearing choices in the file that carries them**, as the rest of the repo
  does — the Dockerfiles say why the base has no CLI, `run-loop.sh` says why the consumer path
  wins, `build-images.yml` says why ordering matters, `run-task.sh` says why it is the only one.

## 8. Safeguards · [S — Safeguards]

- **No credential, token or model weight in any image.** The base ships the loop and nothing that
  authenticates. Auth belongs to the Job's `envFrom` and the operator, never to a layer. This
  matters more now that the base is public.
- **No secret in argv or logs.** `run-task.sh` clones over plain `https` and relies on the
  credential helper. A token in a URL would land in process listings and in the transcript the
  evidence channel ships to the coordinator.
- **`--repo` is rejected, never sanitised.** The value becomes a path and a URL; a name needing
  escaping is a name to refuse.
- **Never clobber a non-checkout.** A workspace path that exists but is not a git clone stops the
  run. Deleting it to make room is the worst possible recovery.
- **Today's laptop run is unchanged.** `scripts/run-loop.sh build-converge specs/<feature>` from
  this repo, with no `.harness/` directory and no new env var set, resolves the built-in conf and
  runs as it does now.
- **The live workstation containers must keep working.** They invoke `run-task.sh` with a
  positional spec-dir and the `--repo` flag; both survive. Their copies are deleted in a separate,
  later PR — nothing in this spec touches them.
- **A consumer conf gains no power a built-in conf lacks.** Same contract: declarations and
  exports only. Note plainly in `docs/executors.md` that sourcing a conf from the worked repo
  executes shell from that repo — and that this is **not** a new hole: the loop already runs that
  repo's `verify.sh` and hands an agent write access to its tree. Kerckhoffs; state the boundary,
  do not add obscurity.
- **`STRATEGY_TOOLS` fails closed and fails early.** An absent declared tool stops the run in
  preflight with exit 3. Never a warning; never satisfied by a tool that merely appears in a
  comment or a doc.
- **A baked harness must not silently become a cloned one.** If `$HARNESS_DIR` exists and is not a
  git checkout, use it — do not clone over it, and do not fail. A fleet run that quietly pulled
  `main` would break the one property baking exists to provide.
- **The dispatcher stays thin** (`docs/design/fleet-dispatch.md` cliff 2): validate → map →
  launch → record. Strategy-to-image is a *map*. No policy, no judgement, no fallback chain beyond
  the single documented default.

## 9. Task breakdown · [O — Operations]

Sequential. T4 depends on T2 and T3 (it routes through the `run-loop.sh` they change).

1. **T1** — the image, **and proof it runs**: `harness-base.Dockerfile` + a thin
   `loop-executor-opencode.Dockerfile` (renamed), the real runtime, public base, CI ordering
   AND rebuild triggers, the default binding off `oc`, the image `exec-container.sh` defaults
   to, and a CI smoke job that runs a fixture task end to end.
2. **T2** — the two search paths: strategies in `run-loop.sh`, `assert.sh` in the gates.
3. **T3** — `STRATEGY_TOOLS`, preflighted in the existing accumulation.
4. **T4** — one `scripts/run-task.sh`, reconciled, routed through `run-loop.sh`, baked-or-cloned.
5. **T5** — the dispatcher: optional strategy in the intent grammar, strategy-to-image resolution.
6. **T6** — `docs/executors.md`, `loops/README.md`, `loop-container.md`.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

**T1 — the image split**

- **AC-1** The system shall provide `docker/harness-base.Dockerfile` producing an image containing
  `scripts/run-task.sh`, `scripts/run-loop.sh`, `scripts/ralph-build.sh`, `scripts/ralph-judge.sh`,
  `scripts/exec-qwen.sh`, `scripts/exec-codex.sh` and `specs/lib/assert.sh`.
- **AC-2** The base image shall contain **no** model CLI: no `opencode`, `codex` or `claude`
  install instruction shall appear in `harness-base.Dockerfile`.
- **AC-3** `docker/loop-executor-opencode.Dockerfile` shall exist, shall begin `FROM` the base
  image, and shall contain no `apt-get install` and no harness copy of its own.
  `docker/loop-executor.Dockerfile` shall no longer exist.
- **AC-4** The base image shall put `$HARNESS_HOME/scripts` on `PATH` and set `ENTRYPOINT` to
  `run-task.sh` under `tini`.
- **AC-5** `.github/workflows/build-images.yml` shall build `harness-base` from
  `docker/harness-base.VERSION` for `linux/amd64,linux/arm64`, in a job the derived build declares
  in `needs:`, and shall build `loop-executor-opencode` rather than `loop-executor`.
- **AC-6** `scripts/exec-container.sh` shall default `LOOP_IMAGE` to an image CI publishes —
  both the renamed repository and a tag that exists — and `docs/loop-container.md`'s manual
  fallback shall push that same tag rather than `:latest`.

- **AC-6b** `.github/workflows/build-images.yml` shall rebuild `harness-base` when `scripts/**`
  or `specs/lib/**` change, not only `docker/**`.
- **AC-6c** `scripts/exec-opencode.sh` shall exist, shall invoke `opencode` and not `oc`, shall
  take provider configuration from the environment, and shall acquire no credential itself.
  `scripts/exec-qwen.sh` shall no longer exist, and `RALPH_EXEC_CMD` shall default to the new
  name.
- **AC-6f** No script and no gate shall still reach for `exec-qwen.sh` functionally. A rename
  that leaves a landed gate asserting the old name is not a rename; it is a second name.
- **AC-6d** The workflow shall run a smoke job, after the images are pushed, that executes a
  fixture task through `run-task.sh` in the derived image and fails if the declared binding is
  absent, if no commit is produced, or if no attempt record is written.
- **AC-6e** Where the codesheet is enabled and `node` is absent, the run shall say so once —
  it shall not turn the codesheet off silently.

**T2 — the search paths**

- **AC-7** When `$HARNESS_REPO_ROOT/.harness/loops/<name>.conf` exists, `run-loop.sh` shall prefer
  it to a built-in conf of the same name.
- **AC-8** When no `.harness/loops/` directory exists, `run-loop.sh` shall resolve strategies from
  `$SCRIPT_DIR/loops` exactly as it does today.
- **AC-9** `run-loop.sh` shall export `HARNESS_REPO_ROOT` **before** sourcing the conf.
- **AC-10** `run-loop.sh --list` shall list strategies from both locations, marking which is
  which, and shall not show a built-in that a consumer conf shadows.
- **AC-11** If a named strategy exists in neither location, then `run-loop.sh` shall exit non-zero
  naming both paths it searched.
- **AC-12** A per-task gate shall resolve `assert.sh` from `$HARNESS_HOME` when that file exists
  and from `$ROOT` otherwise, and every existing gate in this repo shall still pass.

**T3 — the tool declaration**

- **AC-13** Where a conf sets `STRATEGY_TOOLS`, `run-loop.sh` shall check each named executable
  with `command -v` and shall exit 3 if any is absent.
- **AC-14** The failure message shall name the missing executable **and** the strategy that
  declared it.
- **AC-15** A conf with no `STRATEGY_TOOLS` shall behave exactly as today.
- **AC-16** If both a spec `Tools:` entry and a `STRATEGY_TOOLS` entry are missing, then the run
  shall report both in one message and exit 3 once.
- **AC-16b** Every built-in strategy in `scripts/loops/` shall declare `STRATEGY_TOOLS` naming
  the executable its binding invokes. A strategy that declares nothing is the case the
  preflight cannot protect, and the default strategy is the one that matters most.

**T4 — one remote entry point**

- **AC-17** `scripts/run-task.sh` shall accept `<spec-dir>` positionally and `--repo`, `--branch`,
  `--base` and `--strategy` as flags in any position.
- **AC-18** If `--repo` contains any character outside `[A-Za-z0-9._-]`, then `run-task.sh` shall
  exit non-zero without cloning, and shall not attempt to sanitise the value.
- **AC-19** `run-task.sh` shall clone over an `https` URL containing **no** token, and no
  invocation shall place a credential in argv.
- **AC-20** `run-task.sh` shall run `git worktree remove --force` and `git worktree prune` before
  `git worktree add`, so the same spec can be run twice in one container.
- **AC-21** If the resolved workspace path exists but is not a git checkout, then `run-task.sh`
  shall exit non-zero and shall not delete it.
- **AC-22** `run-task.sh` shall invoke `run-loop.sh` with the requested strategy, not
  `ralph-build.sh` directly.
- **AC-23** When `$HARNESS_DIR` exists and is not a git checkout, `run-task.sh` shall use it as-is
  and shall neither clone nor fetch.
- **AC-24** When `$HARNESS_DIR` is a git checkout, `run-task.sh` shall fast-forward it to
  `$HARNESS_REF` and shall continue with the existing checkout if the fetch fails.
- **AC-25** On success `run-task.sh` shall print the push and PR-open commands, and shall not run
  them.

**T5 — dispatch**

- **AC-26** When an intent carries a fifth field, `parse_intent` shall return it as `strategy`.
- **AC-27** When an intent carries exactly four fields, `parse_intent` shall return
  `build-converge`, unchanged.
- **AC-28** If an intent carries more than five fields, then `parse_intent` shall return `None`.
- **AC-29** When `HARNESS_WORKER_IMAGE_<STRATEGY>` is set for the requested strategy, the launched
  Job shall name that image; otherwise it shall name `HARNESS_WORKER_IMAGE`.
- **AC-30** The rendered Job's `STRATEGY` env value and the image it resolved shall come from the
  same requested strategy — a run shall never be launched with one strategy's name and another's
  image.

**T6 — documentation**

- **AC-31** `docs/executors.md` shall carry the three-layer table from §3 and a copy-pasteable
  `FROM harness-base` Dockerfile adding a CLI, a binding and a conf.
- **AC-32** It shall state that the harness ships no credentials, and that auth is the derived
  image's and the operator's.
- **AC-33** It shall contrast `exec-container.sh` with an in-pod direct binding explicitly.
- **AC-34** It shall record what this does NOT provide: no Job body, no code egress, no credential
  provisioning.
- **AC-35** `scripts/loops/README.md` shall document `STRATEGY_TOOLS` and both search paths.

## 11. Verification (the harness)

Per-task gates under `tasks/T<NN>-<slug>/verify.sh` (`specs/20260828i-per-task-gates`), sourcing
the resolved `assert.sh`. No root `verify.sh`; `pend` does not exist in a per-task gate.

**Docker-free assertion.** The image gates must not build anything — CI builds two architectures
and a gate that shells out to `docker build` is neither deterministic nor offline, which is the
reason `docs/loop-container.md` exists as a runbook rather than as criteria. Assert on the
**Dockerfile text and the workflow structure**: the `FROM` line, the absence of `apt-get` in the
derived file, the `COPY` set in the base, the `PATH`/`ENTRYPOINT` lines, the `needs:` edge.

**The trap this gate must dodge (Trap A).** Every string worth grepping — `harness-base`,
`opencode`, `STRATEGY_TOOLS`, `HARNESS_DIR`, `build-converge` — appears in `spec.md`, in
`docs/executors.md`, and in comments, inside this very repo. A check that greps the tree, or greps
a file without stripping comments, passes with the feature absent. Scope every search to the
region the feature produces: Dockerfile instruction lines, the conf's declarations, the resolver's
code path, the workflow's job keys.

**Positive controls (Trap B).** AC-2, AC-8, AC-15, AC-23 and AC-25 are absence or no-change
assertions, and each needs a constructed case where the probe fires — a fixture base Dockerfile
that DOES install a CLI; a fixture repo WITH `.harness/loops/`; a conf WITH `STRATEGY_TOOLS`
naming an absent tool; a `$HARNESS_DIR` that IS a git checkout; a `run-task.sh` that DOES push.
AC-19 in particular is an absence assertion about a token, and the probe that looks for one must
be shown to find a planted one.

**Fixtures.** `lib/fixtures.sh` builds a throwaway repo carrying the real `scripts/`, in the shape
`specs/20260828m-worker-channel/lib/fixtures.sh` establishes — reuse it rather than cloning a
second copy. It additionally needs a consumer-repo fixture with `.harness/loops/` and a stub
binding (T2, T3), and a bare origin plus a pre-made worktree so T4's clone, re-run and refusal
paths can be exercised without network.

**Mutants — when each corpus lands.** `T1` and `T6` ship theirs **with this spec**: their
targets are a Dockerfile, a workflow, a doc — artifacts whose shape §6 and §10 already determine,
so a mutant leaks nothing an implementer does not already have. Both are validated (T1: 6 killed,
0 survivors; T6: 5 killed, 0 survivors; no uncovered ids).

`T2`-`T5` ship **gates now and corpora with the task**, for two reasons found while writing this
one (`evidence/2026-08-29-writing-the-first-mutant-corpus.md`). First, `gate-selftest.sh`
installs a mutant as a COMPLETE replacement file, so a mutant for a behavioural assertion is the
finished `run-loop.sh` or `run-task.sh` with one thing wrong — shipping four of those up front
puts the implementation in the directory the loop reads, which `specs/TEMPLATE.md` forbids:
*"Keep the adversary OUT of the repo, or a later loop run stops being a fair measurement."*
Second, it would not measure anything: a per-task gate has no `pend`, so on an unbuilt tree every
assertion already fails and a mutant either "kills" an assertion that was failing anyway or comes
back WRONG-REASON because a sibling artifact is missing. Mutation is a post-implementation check.

**Two tooling defects stand in the way, both recorded in `evidence/`.** `gate-selftest.sh` bounds
each run with `timeout`, which macOS does not ship, and reports the resulting 127 as
WRONG-REASON on every mutant rather than as "the gate never ran" — the amendment's own failure
mode, in the tool that enforces it. And a mutant's `WHY:` header is grepped along with the
artifact, so a WHY line saying a token is absent satisfies a gate looking for that token; two
doc mutants passed that way before `lib/fixtures.sh` grew `content()`/`hasc()`. The proper fix
for both is in the tool, not in this spec.

**The mutants that matter.** For the corpora above and for the ones landing with T2-T5: a derived
Dockerfile that copies the harness itself (AC-3); a resolver that checks the consumer path but
does not prefer it (AC-7); a resolver that exports `HARNESS_REPO_ROOT` *after* sourcing (AC-9); a
`STRATEGY_TOOLS` check that warns instead of exiting (AC-13); a `run-task.sh` that sanitises
`--repo` instead of rejecting it (AC-18); one that `rm -rf`s a non-checkout (AC-21); one that
clones over a baked `$HARNESS_DIR` (AC-23); and a dispatcher that resolves the image from the
default while passing the requested strategy on the env (AC-30).

## 11b. Loop execution

`scripts/run-loop.sh build-converge specs/20260829a-executor-image-layer` from a worktree on a
throwaway branch. Six tasks, one per iteration, fresh context.

## 12. Open questions

- **OQ1 — code egress: how does the work leave the pod?** `run-task.sh` prints
  `git push … && gh pr create` for a human, and nothing in this repo runs either. Evidence egress
  exists (`20260828o`) — prompts, diffs, gate output and transcripts reach the coordinator as they
  are written — but the **commits do not**. An ephemeral Job therefore finishes with its work on a
  branch inside a pod that `ttlSecondsAfterFinished` is about to delete. Deliberately out of scope
  here; it is the largest remaining gap between this spec and a working fleet, and it needs its
  own spec covering the bot identity, the PR body, and what happens when the gate is red.
- **OQ2 — `beelink-ansible` sequencing.** Decided: fold the three copies out entirely, symlink
  `/usr/local/bin/run-task.sh` at `$HARNESS_DIR/scripts/run-task.sh`, move the harness clone into
  `entrypoint.sh`. Open only on ordering and blast radius: that PR must land *after* this one, and
  it retires `beelink-ansible/specs/harness-multi-repo/verify.sh`, which currently gates the three
  files by name. Confirm the containers are rebuilt (`--tags harness-images`) as part of it, since
  a `COPY`'d file change is inert until the image is rebuilt.
- **OQ3 — the codex login preflight.** `coding-harness-codex`'s copy checks `codex login status`
  and fails early rather than burning a worktree setup on an unauthed container. `STRATEGY_TOOLS`
  covers "codex is missing", not "codex is not logged in". The conf contract forbids a strategy
  file from invoking anything, so a `STRATEGY_PREFLIGHT` hook would widen it. Options: let
  `exec-codex.sh` check on first invocation (cheapest, but the binding contract says it holds no
  decisions), or accept the loss and let the first attempt fail with codex's own error. Do not
  invent a hook without deciding this.
- **OQ4 — `STRATEGY_TOOLS` declared vs inferred.** Declaring duplicates a fact the `exec-*.sh`
  already contains; inferring it means parsing shell, which is worse. **Closing as declared**, with
  the duplication recorded in `loops/README.md`. Noted here only so it is not re-litigated.

- **OQ5 — does `loop-executor` keep its name?** **Closed 2026-08-29: renamed to
  `loop-executor-opencode`**, folded into T1 and into AC-3, AC-5 and AC-6. After the split the
  BASE is what executes loops, so the generic name described the wrong layer; and the name has to
  scale to `loop-executor-codex` / `loop-executor-claude`, where whichever image keeps the bare
  name reads as canonical. Reasoning in §4, cost evidence in §6. Noted here so it is not
  re-litigated.

- **OQ6 — does `exec-qwen.sh` keep its name?** **Closed 2026-08-29: renamed to
  `exec-opencode.sh`**, folded into T1 and AC-6c/AC-6f. Once the binding drives `opencode` from
  the environment rather than a qwen-specific shim, the filename names a model it no longer knows
  about — the same argument as OQ5. Unlike the image rename this one is **not free**: three
  landed gates name it, and §6 lists them. Recorded so it is not re-litigated.

## Two-way sync rule

Logic change → spec first. Refactor → code, then sync back. A taste correction made in review
goes into §7 or it recurs next iteration.
