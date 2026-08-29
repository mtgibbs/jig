# Spec: the executor is an image layer, not a fork

- **Status:** Draft v0.1
- **Owner:** mtgibbs
- **Constitution:** `specs/constitution.md` (+ `/CLAUDE.md` Core Mandates)
- **Touches:** `docker/harness-base.Dockerfile` (new), `docker/harness-base.VERSION` (new),
  `docker/loop-executor.Dockerfile`, `docker/loop-executor.VERSION`,
  `.github/workflows/build-images.yml`, `scripts/run-loop.sh`, `scripts/loops/README.md`,
  `scripts/dispatch/dispatcher.py`, `docs/executors.md` (new)
- **Tools:** git, python3, bash
- **MCP:** none
- **Permissions:** write:docker/**, write:scripts/**, write:docs/**, exec:git, exec:python3

---

## 1. Why · [R — Requirements]

`specs/20260825c-executor-binding` made the executor a **parameter**: one build loop, a
2-to-6-line `exec-*.sh`, and a strategy file. It deleted a 204-line fork and the three specs
that policed its symmetry. That seam is the reason a third party could bring Claude, Gemini or
their own agent to this harness at all.

The fleet work is about to cement the opposite shape. `docker/loop-executor.Dockerfile` installs
opencode, carries **no harness at all**, and sets `ENTRYPOINT ["opencode"]` — the image *is* the
executor rather than a host for one. Nothing in it can be extended: a Claude image would have to
be a second Dockerfile that also re-solves how the loop gets in, which is the 204-line fork
wearing a container. Two more seams are shut alongside it: `run-loop.sh` resolves strategies only
from `$SCRIPT_DIR/loops`, so a consumer repo can bring `specs/` but never a binding; and the
dispatcher pins one `HARNESS_WORKER_IMAGE` for every strategy, so even a strategy that IS
selectable cannot reach an image that can run it.

This spec restores the seam at the image and dispatch layers, so that adding an executor stays
what §20260825c made it: a small file and a config entry, never a fork.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. The loop ships in an image that carries **no model CLI**, and an executor image is that base
   plus one CLI — so `FROM harness-base` is the whole cost of a new executor.
2. A repo that is not this one can supply its own strategy and its own binding, without a PR to
   the harness.
3. A strategy declares the executable it needs, and a mismatch between strategy and image fails
   in preflight with a message naming the missing tool — not mid-run with a shell error.
4. Dispatch can ask for a strategy other than the default, and the image it lands on is the one
   that can run it.
5. A laptop run of `scripts/run-loop.sh build-converge specs/<feature>` behaves **exactly** as it
   does today.

## 3. Entities · [E — Entities]

**Three layers, and which of them varies.** This table is the spec's thesis; every acceptance
criterion below serves it.

| layer | artifact | varies |
|---|---|---|
| the loop | `run-loop.sh`, `ralph-build.sh`, `ralph-judge.sh`, `ralph-log.sh`, `specs/lib/` | never — the invariant |
| the strategy | `<name>.conf` — phases + bindings | per run, named on the wire |
| the binding + its CLI | `exec-<tool>.sh` + the executable it drives | **per image — the extension point** |

**`harness-base` image** — the loop with no model CLI.

```
HARNESS_HOME=/harness          # the harness checkout; scripts/ and specs/lib/ live under it
PATH                           # includes $HARNESS_HOME/scripts
ENTRYPOINT ["/usr/bin/tini", "--", "run-loop.sh"]
contains                       # scripts/**, specs/lib/**, git, ripgrep, python3, bash, tini
does NOT contain               # any model CLI, any credential, any model weights
```

The `exec-*.sh` bindings DO ship in the base; only the CLIs they drive do not. A binding is six
lines and costs nothing to carry, and shipping them means a derived image that installs `codex`
gets `build-codex` working with no file of its own.

**strategy search path** — an ordered list, first match wins:

```
$HARNESS_REPO_ROOT/.harness/loops/<name>.conf     # the consumer repo's own, wins
$HARNESS_HOME/scripts/loops/<name>.conf           # built-in
```

`HARNESS_REPO_ROOT` is the git toplevel of the repo being worked on. A consumer conf names its
binding relative to that root (`$HARNESS_REPO_ROOT/.harness/exec-claude.sh`).

**strategy conf — the contract, extended by exactly one key.** Unchanged from
`scripts/loops/README.md` except:

```
STRATEGY_TOOLS="codex"     # optional, space-separated; executables preflighted with command -v
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
that varies becomes a layer, not a copy. `loop-executor.Dockerfile` is split into
`harness-base.Dockerfile` (the loop) and a thin `loop-executor.Dockerfile` that is `FROM
harness-base` plus `npm install -g opencode-ai`. `run-loop.sh` gains a search path for strategy
files the way `ralph-build.sh` already gained a per-task gate resolver in
`specs/20260828i-per-task-gates` — **additive and fallback-first**, so a missing `.harness/`
directory means today's behaviour exactly. `parse_intent` widens by one optional field, and
`launch_run`'s image argument is resolved from the strategy the way the namespace is already
resolved from the environment.

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
- `docker/loop-executor.Dockerfile`, `docker/loop-executor.VERSION`
- `.github/workflows/build-images.yml` — one matrix entry, ordered after the base
- `scripts/run-loop.sh` — strategy search path, `STRATEGY_TOOLS` preflight
- `scripts/loops/README.md` — the contract gains one key and one search path
- `scripts/dispatch/dispatcher.py` — `parse_intent` grammar, strategy-to-image resolution
- `docs/executors.md` — how to bring your own

### Out of scope
- **The k8s Job body.** Pull secrets, `envFrom`, resources, ServiceAccount, the `harness-fleet`
  nodeSelector and namespace are the deploy-side follow-on in `pi-cluster`. This spec makes the
  image and the strategy composable; it renders no Job field.
- **How the consumer repo arrives in the pod** (clone step, initContainer, volume). See OQ1.
- `exec-qwen.sh`, `exec-codex.sh`, `exec-container.sh` — the binding contract does not change.
- `ralph-build.sh`, `ralph-judge.sh`, the gates, the evidence writers, the coordinator.
- Writing an `exec-claude.sh`. This spec makes one possible; it does not ship one.
- Authelia/auth, credential provisioning, egress policy.

## 6. Prior decisions / facts the implementer must know · [S — Structure: system fit & deps]

**Verified against the tree and the live cluster on 2026-08-29.**

- `docker/loop-executor.Dockerfile` today: `FROM node:22-bookworm-slim`, apt-installs
  `git ripgrep ca-certificates curl tini`, `npm install -g opencode-ai@1.17.10`,
  `WORKDIR /home/agent/run-container`, `ENTRYPOINT ["/usr/bin/tini", "--", "opencode"]`.
  It contains **no harness**. Preserve the tini entrypoint wrapper and the apt set — they move
  down into the base.
- `docker/loop-executor.VERSION` holds `0.1.0`. `ghcr.io/mtgibbs/loop-executor:0.1.0` exists,
  is **private**, and is built for `linux/amd64,linux/arm64`.
- `.github/workflows/build-images.yml` is a matrix over `{image, dockerfile, version-file}`,
  triggered on push to `main` under `docker/**`. It currently builds `loop-executor` and
  `harness-coordinator`. Its header comment records that a GHCR package must be flipped public
  after first push. **`harness-base` must build before `loop-executor`** — a matrix runs its
  entries in parallel, so the dependent build needs the base pushed first (see OQ2).
- **`run-loop.sh` sources the strategy conf BEFORE any loop script runs, and `ROOT` is not set at
  that point.** `ralph-build.sh:196` is what exports `ROOT="$(git rev-parse --show-toplevel)"`,
  and it runs later. So a conf cannot reference `$ROOT`; `run-loop.sh` must compute and export
  `HARNESS_REPO_ROOT` itself before the `. "$ENV_FILE"` line.
- `run-loop.sh` already has a fatal preflight for the **spec's** `Tools:` field — `command -v`
  each, accumulate misses, exit **3** with "container needs attention, not another retry". T3's
  `STRATEGY_TOOLS` check joins that same accumulation and reuses that exit code and phrasing; do
  not add a second preflight block.
- `scripts/loops/README.md` states the conf contract: a strategy file may ONLY declare
  `STRATEGY_DESC` / `STRATEGY_PHASES` and export env knobs the loop scripts already accept. It
  may not define functions, add stopping logic, or invoke anything. `STRATEGY_TOOLS` is a
  declaration, so it fits that contract without widening it.
- **The HTTP API is already open on strategy.** `scripts/dispatch/api.py:59` reads
  `body.get("strategy", "build-converge")` and passes it to `launch_run`. What is pinned is the
  **text** path: `dispatcher.py:parse_intent` requires exactly 4 whitespace-separated parts and
  hardcodes `"strategy": "build-converge"`. T4 widens the parser; the API needs no change.
- `dispatcher.py:launch_run` takes `image=` from the caller, and `api.py:73` sources it from a
  single `HARNESS_WORKER_IMAGE` env var. One image serves every strategy today.
- `dispatcher.py:render_job` puts `REPO`, `SPEC`, `STRATEGY` on the container env and nothing
  else. It is otherwise out of scope here — T4 changes which image the Job names, not its body.
- `scripts/exec-codex.sh` carries a comment about `run-task.sh --repo`. **No `scripts/run-task.sh`
  exists in this repo.** Do not build against it; the clone question is OQ1.
- `ghcr.io/mtgibbs/harness-coordinator:0.1.0` is deployed and healthy in the `harness` namespace
  of pi-cluster, with a Flux `ImagePolicy`/`ImageUpdateAutomation` pinned to that image name.
  **There is no Flux automation for `loop-executor`**, so renaming it is cheap today and gets
  expensive the moment the fleet manifests land (OQ3).

## 7. Norms · [N — Norms]

- **Naming.** Image `harness-base`; version file `docker/harness-base.VERSION`; env var
  `HARNESS_HOME` for the in-image harness root and `HARNESS_REPO_ROOT` for the repo being worked
  on. Do not overload `ROOT` — `ralph-build.sh` owns it and means the worked repo.
- **Fallback-first, like the per-task gate resolver.** Every new path is checked, and its absence
  means the existing behaviour, not an error. A repo with no `.harness/` is not misconfigured.
- **Document the similar-but-different pair.** `docs/executors.md` must contrast
  `exec-container.sh` (loop on host, prompt into a container) with an in-pod direct binding (loop
  in the container already). The constitution names this trap; here it has two things called
  "container" one line apart.
- **Error messages name the missing thing and the fix.** Match the existing preflight's voice:
  it says which tool is missing and that the container needs attention rather than another retry.
  A strategy/image mismatch must read the same way.
- **Comment the load-bearing choices in the file that carries them**, as the rest of the repo
  does — the Dockerfile says why the base has no CLI, `run-loop.sh` says why the consumer path
  wins, `build-images.yml` says why ordering matters.

## 8. Safeguards · [S — Safeguards]

- **No credential, token or model weight in any image.** The base ships the loop and nothing that
  authenticates. Auth belongs to the Job's `envFrom` and the operator, never to a layer.
- **Today's laptop run is byte-for-byte the same command with the same behaviour.**
  `scripts/run-loop.sh build-converge specs/<feature>` from this repo, with no `.harness/`
  directory and no new env var set, resolves the built-in conf and runs as it does now.
- **A consumer conf gains no power a built-in conf lacks.** Same contract: declarations and
  exports only. Note plainly in `docs/executors.md` that sourcing a conf from the worked repo
  executes shell from that repo — and that this is **not** a new hole: the loop already runs that
  repo's `verify.sh` and hands an agent write access to its tree. Kerckhoffs; do not add
  obscurity, do state the boundary.
- **`STRATEGY_TOOLS` must fail closed and fail early.** A declared tool that is absent stops the
  run in preflight with exit 3. It must never degrade to a warning, and it must never be
  satisfied by a tool that merely appears in a comment or a doc.
- **The base image must not be able to run a loop it has no executor for and call it a pass.** A
  strategy whose binding names an absent CLI is a preflight failure, not an attempt that produces
  an empty transcript and a red gate — those two states must read differently.
- **The dispatcher stays thin** (`docs/design/fleet-dispatch.md` cliff 2): validate → map →
  launch → record. Strategy-to-image is a *map*. No policy, no judgement, no fallback chain
  beyond the single documented default.

## 9. Task breakdown · [O — Operations]

Sequential; T2 and T4 are independent of each other and could run in parallel if the loop ever
supports it, but the gate order below assumes the listed sequence.

1. **T1** — split the image: `harness-base.Dockerfile` + a thin `loop-executor.Dockerfile`.
2. **T2** — the strategy search path in `run-loop.sh`, plus `HARNESS_REPO_ROOT`.
3. **T3** — `STRATEGY_TOOLS`, preflighted in the existing accumulation.
4. **T4** — the dispatcher: optional strategy in the intent grammar, strategy-to-image resolution.
5. **T5** — `docs/executors.md` and the `loops/README.md` contract update.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

**T1 — the image split**

- **AC-1** The system shall provide `docker/harness-base.Dockerfile` producing an image that
  contains `scripts/run-loop.sh`, `scripts/ralph-build.sh`, `scripts/ralph-judge.sh`,
  `scripts/exec-qwen.sh`, `scripts/exec-codex.sh` and `specs/lib/assert.sh`.
- **AC-2** The base image shall contain **no** model CLI: neither `opencode`, `codex` nor
  `claude` shall resolve on its `PATH`.
- **AC-3** `docker/loop-executor.Dockerfile` shall begin `FROM` the base image, and shall contain
  no `apt-get install` and no harness copy of its own.
- **AC-4** The base image shall put `$HARNESS_HOME/scripts` on `PATH` and set `ENTRYPOINT` to
  `run-loop.sh` under `tini`.
- **AC-5** `.github/workflows/build-images.yml` shall build `harness-base` from
  `docker/harness-base.VERSION`, for `linux/amd64,linux/arm64`, and shall push it before
  `loop-executor` is built.

**T2 — the strategy search path**

- **AC-6** When `$HARNESS_REPO_ROOT/.harness/loops/<name>.conf` exists, `run-loop.sh` shall use
  it in preference to a built-in conf of the same name.
- **AC-7** When no `.harness/loops/` directory exists, `run-loop.sh` shall resolve strategies from
  `$SCRIPT_DIR/loops` exactly as it does today.
- **AC-8** `run-loop.sh` shall export `HARNESS_REPO_ROOT` **before** sourcing the conf, so a
  consumer conf can name a binding inside its own repo.
- **AC-9** `run-loop.sh --list` shall list strategies from both locations, marking which is which,
  and shall not show a built-in that a consumer conf shadows.
- **AC-10** If a named strategy exists in neither location, then `run-loop.sh` shall exit non-zero
  naming both paths it searched.

**T3 — the tool declaration**

- **AC-11** Where a conf sets `STRATEGY_TOOLS`, `run-loop.sh` shall check each named executable
  with `command -v` and shall exit 3 if any is absent.
- **AC-12** The failure message shall name the missing executable **and** the strategy that
  declared it.
- **AC-13** A conf with no `STRATEGY_TOOLS` shall behave exactly as today.
- **AC-14** If both a spec `Tools:` entry and a `STRATEGY_TOOLS` entry are missing, then the run
  shall report both in one message and exit 3 once.

**T4 — dispatch**

- **AC-15** When an intent carries a fifth field, `parse_intent` shall return it as `strategy`.
- **AC-16** When an intent carries exactly four fields, `parse_intent` shall return
  `build-converge`, unchanged.
- **AC-17** If an intent carries more than five fields, then `parse_intent` shall return `None`.
- **AC-18** When `HARNESS_WORKER_IMAGE_<STRATEGY>` is set for the requested strategy, the launched
  Job shall name that image.
- **AC-19** When no per-strategy image variable is set, the Job shall name `HARNESS_WORKER_IMAGE`.
- **AC-20** The rendered Job's `STRATEGY` env value and the image it resolved shall come from the
  same requested strategy — a run shall never be launched with one strategy's name and another's
  image.

**T5 — documentation**

- **AC-21** `docs/executors.md` shall carry the three-layer table from §3 and a copy-pasteable
  `FROM harness-base` Dockerfile adding a CLI, a binding and a conf.
- **AC-22** It shall state that the harness ships no credentials, and that auth is the derived
  image's and the operator's.
- **AC-23** It shall contrast `exec-container.sh` with an in-pod direct binding explicitly.
- **AC-24** It shall record what this does NOT provide: no Job body, no clone step, no credential
  provisioning.
- **AC-25** `scripts/loops/README.md` shall document `STRATEGY_TOOLS` and the search path.

## 11. Verification (the harness)

Per-task gates under `tasks/T<NN>-<slug>/verify.sh` (`specs/20260828i-per-task-gates`), sourcing
`specs/lib/assert.sh`. No root `verify.sh`; `pend` does not exist in a per-task gate.

**Docker-free assertion.** The image gates must not require a build — CI builds for two
architectures and a gate that shells out to `docker build` is neither deterministic nor offline.
Assert on the **Dockerfile text and the matrix entry** instead: the `FROM` line, the absence of
`apt-get` in the derived file, the `COPY` set in the base, the `PATH`/`ENTRYPOINT` lines, and the
version-file/matrix wiring. AC-2 ("no model CLI on PATH") is asserted as "no `npm install -g`,
`pip install` or download of a model CLI appears in the base Dockerfile", scoped to the base file
with comments stripped.

**The trap this gate must dodge (Trap A).** Every string worth grepping — `harness-base`,
`opencode`, `STRATEGY_TOOLS`, `build-converge` — will appear in `spec.md`, in `docs/executors.md`
and in comments, in this very repo. A check that greps the tree, or greps a file without
stripping comments, passes with the feature absent. Scope every search to the region the feature
produces: the Dockerfile's instruction lines, the conf's declarations, the resolver's code path.

**Positive controls (Trap B).** AC-2, AC-7 and AC-13 are absence/no-change assertions. Each needs
a constructed case where the probe fires: a fixture base Dockerfile that DOES install a CLI must
make AC-2 fail; a fixture repo WITH `.harness/loops/` must make AC-7's "resolved built-in" probe
read differently; a conf WITH `STRATEGY_TOOLS` naming an absent tool must make AC-13's probe fire.

**Fixtures.** `lib/fixtures.sh` builds a throwaway repo carrying the real `scripts/`, in the shape
`specs/20260828m-worker-channel/lib/fixtures.sh` already establishes — reuse it rather than
cloning a second copy. It additionally needs a consumer-repo fixture with `.harness/loops/` and a
stub binding, for T2 and T3.

**Mutants.** Each task dir ships `mutants/` for `scripts/gate-selftest.sh`. The mutants that
matter: a derived Dockerfile that copies the harness itself (AC-3), a resolver that checks the
consumer path but does not prefer it (AC-6), a resolver that exports `HARNESS_REPO_ROOT` *after*
sourcing (AC-8), a `STRATEGY_TOOLS` check that warns instead of exiting (AC-11), and a dispatcher
that resolves the image from the default while passing the requested strategy on the env (AC-20).

## 11b. Loop execution

`scripts/run-loop.sh build-converge specs/20260829a-executor-image-layer` from a worktree on a
throwaway branch. Five tasks, one per iteration, fresh context.

## 12. Open questions

- **OQ1 — how does the worked repo get into the pod?** The base image's `ENTRYPOINT` is
  `run-loop.sh`, which requires a checked-out repo at the worked root. A clone step (initContainer,
  entrypoint wrapper, or a `run-task.sh` that does not yet exist) has to exist for the Job to
  work. It is deliberately out of scope — but the base image's entrypoint contract is the thing
  that answer will touch, so resolve it before the Job body is written, not after.
- **OQ2 — how is the base/derived build ordered in CI?** A single matrix runs entries in
  parallel. Options: two jobs with `needs:`, or a matrix that includes an order key. The `needs:`
  split is the boring one and is probably right; confirm before T1 is handed over.
- **OQ3 — does `loop-executor` keep its name?** It currently claims a generality it does not have;
  `loop-executor-opencode` says what it is. There is no Flux automation on it yet, so renaming is
  free today and costs a manifest change once the fleet lands. Recommend renaming now. Not
  assumed by any AC above — if it renames, T1 and AC-5 take the new name.
- **OQ4 — should `STRATEGY_TOOLS` be inferred from the binding rather than declared?** Declaring
  duplicates a fact the `exec-*.sh` already contains. Inferring it means parsing shell, which is
  worse. Declared, for now; note it in `loops/README.md` as a known duplication.

## Two-way sync rule

Logic change → spec first. Refactor → code, then sync back. A taste correction made in review
goes into §7 or it recurs next iteration.
