# Spec: `mcp-harness` — the fleet's MCP surface, as a client of the dispatch API

Tools: python3
MCP: none
Permissions: read, write, bash

## 1. Why · [R — Requirements]

`20260828h` shipped the dispatch API. **It has no client.** The only way to start a fleet run today
is a Matrix message, which is why the question that opened this arc — *"are those exposed as
endpoints we can bake into an MCP or other orchestration tools?"* — is still only half-answered.
The endpoints exist; nothing speaks to them.

Sequencing item 4. ADR-001 **D9** already fixes the shape: the tools live in a **separate
`mcp-harness` server** that is a **client** of the HTTP API, not a second copy of the machinery,
and not an extension of `mcp-homelab`.

The boundary is a concern boundary, not a risk one. `mcp-homelab` is cluster administration — DNS,
media, backups, Flux. `mcp-harness` is loop infrastructure — launching runs and reading their
evidence. **And it cuts both ways:** a diagnostic agent should not silently gain `launch_run`, and
a fleet orchestrator has no business inheriting `restart_deployment` or `update_pihole_gravity`.
Folding either into the other hands each audience a domain it never asked for. As a bonus,
`mcp-harness` needs **no cluster RBAC at all** — it only speaks HTTP.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A stdio MCP server at `scripts/mcp-harness/server.py`, standard library only.
2. It answers `initialize`, `tools/list` and `tools/call` as JSON-RPC 2.0 over stdin/stdout.
3. It exposes exactly four tools: `list_runs`, `run_status`, `fetch_evidence` — reads — and
   `launch_run`, **the only tool that changes anything**.
4. It reaches the dispatcher over HTTP and **never imports `dispatcher`**. No cluster access, no
   kubectl, no second copy of the launch logic.
5. It refuses to start without `HARNESS_API_URL` and `HARNESS_API_TOKEN`, naming the missing one.
6. `launch_run` requires an explicit `idempotency_key`. There is no generated default.
7. A `401` is reported as an authentication problem, a `404` as no-such-run, and a `501` as a
   capability that does not exist yet. **None of the three collapses into another.**
8. The bearer token never appears in any tool result, error message, or log line.

## 3. Entities · [E — Entities]

### 3.1 The four tools

| tool | HTTP | notes |
|---|---|---|
| `list_runs` | `GET /runs` | read |
| `run_status` | `GET /runs/<id>` | read; unknown id is a clean "no such run", not an error |
| `fetch_evidence` | `GET /runs/<id>/evidence` | read; **today always 501** — reported as "not built yet" |
| `launch_run` | `POST /runs` | the only mutation |

### 3.2 `cancel_run` is deliberately NOT in this cut

D9 names five tools. This spec ships four, and the sequencing gate says why: *"read tools first;
`launch_run` the only mutation."*

The reason is not that cancelling is risky in itself — it deletes one Job the registry already
knows about. It is that **`cancel_run` is the tool a model reaches for while tidying up**, it has
no undo, and it is the one tool whose blast radius grows with the size of the fleet. It gets its
own spec, after there is a fleet to observe it against. Naming the omission here is the point:
a tool absent by decision is different from one nobody got to.

### 3.3 The tool description IS the contract

An MCP tool's `description` and JSON schema are what the calling model reads; they are prompt, not
documentation. Two consequences the implementation must honour:

- **`idempotency_key` is a REQUIRED parameter with no default.** The tempting shape — optional,
  defaulting to a fresh UUID — is precisely the bug `docs/dispatch-api.md` warns clients about: a
  retried tool call becomes a duplicate run, and the API's replay protection never engages because
  every attempt arrives with a new key. Requiring it forces the caller to pass the id of *the thing
  that caused this* — an issue number, a commit sha, an event id.
- **The descriptions must say what a tool does NOT do.** `fetch_evidence` says evidence does not
  leave the pod yet; `launch_run` says a replayed key returns the existing run rather than starting
  a second one.

## 4. Approach · [A — Approach]

JSON-RPC 2.0 over stdio, `urllib.request` for HTTP, nothing else — the same stdlib-only constraint
`api.py` carries, for the same reason: the loop container has no `mcp` SDK and no `requests`, and a
server that cannot be run without a network install cannot be gated hermetically.

That constraint is a gift to verification. A stdio server is **fully deterministic to test**: write
JSON-RPC lines to stdin, read frames off stdout, with a stub HTTP layer standing in for the
dispatcher. No sockets, no ports, no waiting for a server to come up — none of the flakiness that
cost `20260828h` two gate rewrites.

## 5. Scope · [S — Structure: boundary]

### In scope
- `scripts/mcp-harness/server.py`, its four tools, its error mapping, and `docs/mcp-harness.md`.

### Out of scope
- `cancel_run` (§3.2). Its own spec.
- The Dockerfile and image CI — D10 gives those to this repo but they are sequencing item 0's
  unfinished half, tracked separately; this spec ships the source.
- Everything in `clusters/pi-k3s/harness-dispatch/` — deployment is pi-cluster's half of D10.
- Any MCP feature beyond tools: no resources, no prompts, no sampling.

## 6. Prior decisions / facts the implementer must know · [S]

| fact | source | consequence |
|---|---|---|
| the API is cluster-internal, no ingress | ADR-001 D9 | the server takes a base URL; it never hardcodes a host |
| `mcp-harness` is a CLIENT, not a second dispatcher | ADR-001 D9 | `import dispatcher` in this file is a design failure, and the gate treats it as one |
| evidence returns 501 by design, never 404 | `docs/dispatch-api.md` | the tool must preserve that distinction rather than flattening both to "error" |
| a replayed idempotency key returns success and starts no second run | `docs/dispatch-api.md` | do not treat a replay as a failure |
| `mcp-harness` needs no cluster RBAC | ADR-001 D9 | no kubectl, no kubeconfig, no service account token |
| the tool schema is read by a model, not a human | §3.3 | an optional idempotency key is an unsafe default, not a convenience |

## 7. Norms · [N — Norms]

1. **Stdlib only.** No third-party import.
2. **Fail closed on configuration**, exactly as `api.py` does: missing URL or token means refuse to
   start and name the variable, never a default.
3. **Never echo the credential.** Not in an error, not in a debug line, not in a tool result.
4. **Distinguish the three failure kinds.** 401 / 404 / 501 carry different meanings to the caller
   and must not be flattened into a single "request failed".
5. **A tool result says what happened, in words the model can act on.** "HTTP 500" is not a result;
   "the dispatcher rejected the request because `spec` was missing" is.

## 8. Safeguards · [S — Safeguards]

- `launch_run` is the only tool that changes anything, and the gate asserts the other three issue
  **no** non-GET request — a read tool that mutates is the failure mode that matters here.
- A malformed JSON-RPC frame gets a JSON-RPC error response and the server stays up. A crash on bad
  input is a denial of the whole session.
- The server never invents a run id, and never retries a `POST` on its own: a retry it did not
  decide is a duplicate run the caller cannot see.

## 9. Task breakdown · [O — Operations]

See `tasks.txt`. Six tasks: the JSON-RPC skeleton and config; the tool catalogue; the two read
tools; evidence; `launch_run`; the docs.

## 10. Acceptance criteria (EARS) · [O]

- **AC-1** When `HARNESS_API_URL` or `HARNESS_API_TOKEN` is missing, the server shall exit non-zero
  naming the missing variable, and shall serve nothing.
- **AC-2** When sent `initialize`, the server shall answer a JSON-RPC result carrying a protocol
  version and a server name.
- **AC-3** When sent `tools/list`, the server shall return exactly the four tools of §3.1, and shall
  not list `cancel_run`.
- **AC-4** The `launch_run` schema shall mark `repo`, `spec`, `strategy` and `idempotency_key` as
  **required**, and shall declare no default for `idempotency_key`.
- **AC-5** When `list_runs` or `run_status` is called, the server shall issue a GET to the
  corresponding route with an `Authorization: Bearer` header, and shall issue no non-GET request.
- **AC-6** When the dispatcher answers 401, the tool result shall name authentication and shall not
  claim the run does not exist.
- **AC-7** When `run_status` is called for an unknown id (404), the result shall say no such run;
  when `fetch_evidence` receives 501, the result shall say the capability is not built yet, and the
  two shall be distinguishable.
- **AC-8** When `launch_run` is called, the server shall POST the four fields to `/runs` and shall
  report a replayed key as an existing run rather than an error.
- **AC-9** When any tool errors for any reason, the value of `HARNESS_API_TOKEN` shall not appear in
  the response.
- **AC-10** The module shall not import `dispatcher`, and shall import nothing outside the standard
  library.
- **AC-11** `docs/mcp-harness.md` shall document all four tools, the two configuration variables,
  why `cancel_run` is absent, and how the three failure codes differ.

## 11. Verification (the harness)

The gate drives the server as a subprocess over stdio with a **stub HTTP transport**, so every
assertion is hermetic and bounded — no port binding, no readiness race. Each call into the server is
run under `timeout` with an explicit branch for the call that never returned (`20260828h`'s ac1
hung the whole gate by omitting exactly that), and every failure message carries the server's own
stderr rather than a symptom.

**Migration note:** this spec is written with a monolithic `verify.sh` because `20260828i` had not
landed when it was authored. If per-task gates are available when this is run, it should be
migrated to `tasks/T<NN>-*/verify.sh` first — six tasks judged by one gate is the shape that cost
`20260828g` and `20260828h` most of their attempts.
