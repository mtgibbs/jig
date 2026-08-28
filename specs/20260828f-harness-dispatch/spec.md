# Spec: the dispatcher turns an event into exactly one run

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor qwen)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, python3
- **MCP:** none
- **Touches:** `scripts/dispatch/dispatcher.py` (new), `scripts/dispatch/README.md` (new).
  **No change** to `ralph-build.sh`, `run-loop.sh`, `ralph-log.sh`, `ralph-status.sh`, or any
  other spec.

---

## 1. Why · [R — Requirements]

`docs/adr/001-harness-dispatch.md` fixed the contract. This builds its core: the always-on piece
that turns a chat message into exactly one k8s Job and records what happened.

The ADR's D3 is the whole design constraint — **validate → map → launch → record, and nothing
else.** Cliff 2 names the failure mode: the always-on component attracts logic, and the prototype
this is modelled on stayed ~140 lines across its entire life precisely because that rule held.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A message matching the one supported verb yields an intent naming repo, spec and strategy.
2. A message that does **not** match yields no intent and **launches nothing**.
3. The same event, seen twice, launches **once** — dedupe is keyed on the event id, never on a
   cursor (ADR D1: the cursor is losable, the ledger is the correctness mechanism).
4. A launch renders a Job bounded from the start: fleet namespace, node selector,
   `activeDeadlineSeconds`, `ttlSecondsAfterFinished` (ADR D4 / cliff 5).
5. The dispatcher contains **no model call, no gate invocation, no retry loop** — every judgment
   lives in the worker (ADR D3).
6. A malformed message never crashes the listener.

## 3. Entities · [E — Entities]

### 3.1 The intent

One verb in v1. The alias table is literal and fixed; there is no router and no confidence
machinery, because triggers name repo and spec explicitly (ADR D2).

```
@harness fix <repo> <spec>   →  Intent(verb="fix", repo=..., spec=..., strategy="build-converge")
anything else                →  None  (post help, launch nothing)
```

`strategy` defaults to `build-converge` and is not user-supplied in v1 — a second dimension of
input doubles the validation surface for no current need.

### 3.2 The ledger

A file of event ids already actioned, one per line. `seen(event_id)` is the only question asked of
it. It is append-only and its absence is not an error — a fresh dispatcher has actioned nothing.

**It is separate from the `/sync` cursor on purpose.** The cursor can be lost on restart; the
ledger is what makes a replayed event harmless.

### 3.3 The rendered Job

Bounded by construction, not by convention:

| field | value | why |
|---|---|---|
| `namespace` | the fleet namespace | blast radius (cliff 5) |
| `nodeSelector` | `harness-fleet: "true"` | ADR D11 — a label, so a dedicated node is a purchase not a redesign |
| `activeDeadlineSeconds` | set | a wedged run must die on its own |
| `ttlSecondsAfterFinished` | set | finished Jobs must not accumulate |
| `image` | the loop worker image | see §5 |
| env | `REPO`, `SPEC`, `STRATEGY` | what the worker needs and nothing more |

## 4. Approach · [A — Approach]

One Python module of pure functions plus one thin side-effecting launcher. Parsing, dedupe and
rendering take values and return values, so the gate can assert them directly rather than through
a running service.

The launcher shells out to a **configurable command** (`HARNESS_KUBECTL`, default `kubectl`) so
the gate can substitute a mock and assert on the argv — the same technique
`20260828a-exec-container` used for the container runtime, which is the only way to test a launch
without a cluster.

**Rejected: a k8s client library.** It would make the launch untestable without either a cluster or
heavy mocking, and the dispatcher's whole design constraint is that it stays small enough to read.

**Rejected: the HTTP API in this spec.** ADR D9's read tools are a separate surface; adding them
here doubles the spec and the API is useless until a run exists to ask about. It is the natural
follow-up.

## 5. What this spec does NOT settle · [S — Scope]

**Which image the Job runs.** `docker/loop-executor.Dockerfile` contains `opencode` and **no
harness scripts**, with `ENTRYPOINT ["opencode"]` — correct for `exec-container.sh`, which mounts a
worktree and runs the executor per attempt from a host-side loop. But ADR D4 says the Job runs
`run-loop.sh`, which is **not in that image**. They are different images with different entrypoints:
an *executor* image, and a *worker* image that carries the harness and runs the loop.

This spec renders the image name from configuration (`HARNESS_WORKER_IMAGE`) and does not decide
which image that is. Deciding it is a separate change, and pretending otherwise here would bake a
wrong assumption into the launcher.
