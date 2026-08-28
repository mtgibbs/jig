# Spec: the executor runs in a container, and the loop cannot tell

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor qwen)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, sed
- **MCP:** none
- **Permissions:** write:scripts/**, write:docker/**, write:docs/**, exec:git
- **Touches:** `scripts/exec-container.sh` (new), `docker/loop-executor.Dockerfile` (new),
  `scripts/loops/build-container.env` (new), `docs/loop-container.md` (new), and a deferred-work
  note in `docs/design/fleet-dispatch.md`. **No change** to
  `ralph-build.sh`, `run-loop.sh`, `exec-qwen.sh`, `exec-codex.sh`, or any existing `verify.sh`.

> **`Tools:` declares what the TASKS need, not what the artifact needs at runtime.** Writing a
> shell script and a Dockerfile needs `git` and `sed`. The *artifact* needs `docker`, and
> declaring that here would make `run-loop.sh` refuse to start on any host without it — including
> the container this spec is being built in. Do not "fix" this by adding `docker`.

---

## 1. Why · [R — Requirements]

`docs/design/fleet-dispatch.md` item 2. Loop containers are the premise of the fleet: an event
spins up an ephemeral worker, it runs a spec, it dies. Today the only executor bindings are
`exec-qwen.sh` and `exec-codex.sh`, both of which run a CLI that must already be installed on the
host. A Pi worker and the Beelink are different architectures with different toolchains, and
"install opencode on every node" is the thing containers exist to stop.

The loop must not learn anything new. `specs/executor-binding` §3/§7 makes a binding thin by
contract — prompt in `$1`, `ROOT` from the environment, transcript on stdout, no retry, no gate,
no evidence, no stopping logic — and that is exactly what lets a third binding be added without
touching the loop. `exec-container.sh` is that third binding and nothing more.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `scripts/exec-container.sh` honours the binding contract: prompt `$1`, `ROOT` from the
   environment, transcript on stdout, and it `exec`s — no retry, no gate, no evidence.
2. The container sees the worktree **at the same absolute path** the loop uses, so a path in the
   prompt means the same thing inside and out.
3. The container writes as the **invoking uid**, so files it creates are files the loop can
   commit and clean up.
4. The container is removed after every run.
5. The prompt survives byte-for-byte, including a leading `-n` and backslashes.
6. Image and network are overridable by environment, with defaults that work unconfigured.
7. `docker/loop-executor.Dockerfile` builds for **both** `linux/amd64` and `linux/arm64` — no
   architecture is hardcoded.
8. Adding this binding changes **no** existing file.

## 3. Entities · [E — Entities]

### 3.1 The binding's contract with the runtime

`exec-container.sh` builds exactly one command. Every part of it is load-bearing:

| element | value | why |
|---|---|---|
| `--rm` | always | outcome 4; an ephemeral worker that leaks containers is not ephemeral |
| `-v "$ROOT:$ROOT"` | same path both sides | outcome 2 |
| `-w "$ROOT"` | the worktree | the executor starts where the loop is |
| `-e ROOT="$ROOT"` | passed through | the contract's own variable |
| `--user "$(id -u):$(id -g)"` | invoking uid | outcome 3 |
| `$LOOP_IMAGE` | default `ghcr.io/mtgibbs/loop-executor:latest` | outcome 6 |
| `--network "$LOOP_NETWORK"` | default `ai-internal` | the executor must reach LiteLLM |
| the prompt | **the last argument, unquoted-expanded exactly once** | outcome 5 |

### 3.2 Environment the executor needs

Passed through with `-e NAME` (value from the loop's environment, never re-derived):
`HARNESS_LITELLM_KEY`, `OC_SHEET`, and any `RALPH_*` the loop already exports. A variable that is
unset in the loop must be unset in the container, not set to the empty string.

### 3.3 The image

Mirrors `beelink-ansible/files/coding-harness-qwen/Dockerfile`, minus everything a one-shot
executor does not need (no tmux, no gh, no persistent `$HOME`):

- base `node:22-bookworm-slim` — published for both target architectures
- `opencode-ai` pinned by `ARG`, installed with `npm install -g`
- any architecture-dependent download resolved with `dpkg --print-architecture`, never a literal
- entrypoint takes the prompt as its argument and runs the executor against `$ROOT`

## 4. Approach · [A — Approach]

Same shape as `exec-qwen.sh`: a comment block explaining the contract, then one `exec`. The
container is a detail of *how* the executor is reached, not a new concept for the loop.

**Rejected: running the whole loop in the container.** The gate for item 2 is "binding contract
unchanged". A loop-in-container is item 3's dispatcher, and conflating them means the binding
seam — the thing that makes a third executor cost one file — gets rebuilt as a service.

**Rejected: `--platform` in the Dockerfile.** It pins the image to one architecture at build time,
which is precisely what outcome 7 forbids. Multi-arch is a property of how it is *built*
(`docker buildx build --platform linux/amd64,linux/arm64`), and that belongs in the runbook.

## 5. What this spec CANNOT verify, and who does · [A — Approach]

**There is no `docker` in the harness container this spec is built in.** The gate therefore proves
the *contract* — by putting a mock `docker` on `PATH` and asserting the exact argv the binding
produces — and it cannot prove that the image builds or that a real run works.

Those are real acceptance criteria and they are **not** silently skipped. They are handed to a
host that has `docker`, written down in `docs/loop-container.md` as a runbook:

1. `docker buildx build --platform linux/amd64,linux/arm64` succeeds.
2. The design doc's own sketch: one spec run via `exec-qwen.sh` and via `exec-container.sh`, and
   `.evidence/` differs **only** in `binding`.

They are deliberately not written as `pend` ACs. A `pend` that no run in this environment can ever
clear would fail the final task forever under `specs/last-task-strict` — and a gate that cannot
pass is a broken control, not a strict one. The honest form is a runbook with an owner, not an
assertion pretending to be checkable here.
