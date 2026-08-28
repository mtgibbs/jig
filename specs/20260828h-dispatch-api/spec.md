# Spec: the dispatch API, and the tools that call it

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor qwen)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, python3
- **MCP:** none
- **Touches:** `scripts/dispatch/api.py` (new), `scripts/dispatch/README.md`,
  `docs/dispatch-api.md` (new). **No change** to `dispatcher.py`'s core, `ralph-build.sh`,
  `run-loop.sh`, or any other spec.

---

## 1. Why · [R — Requirements]

`20260828g-dispatch-core` cut the transport seam: `dispatch(intent, event_id)` is shared, and
adapters around it decide nothing. That spec built two adapters — chat, and a value-taking
`launch_run` — and the second exists precisely so this one has something to call.

ADR-001 D9 names the surface: `launch_run`, `run_status`, `list_runs`, `cancel_run`,
`fetch_evidence`, cluster-internal, **no ingress**, with `mcp-harness` as a **client** of this API
rather than a second copy of the machinery. That last clause is the whole point. An MCP server that
reimplemented dedupe would be the duplicate-idempotency defect wearing a different hat.

Chat is currently the only front door that exists in code. This makes it one of several.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. An HTTP caller holding `repo`, `spec` and `strategy` can start a run, and gets back the run's
   identity.
2. An HTTP caller can list runs and read one run's status.
3. An HTTP caller can cancel a run.
4. **The same request, sent twice, starts one run.** Idempotency is a property of the API, not of
   the chat transport that happened to have event ids first.
5. Every handler is an adapter: it may parse a request and format a response, and it may not
   dedupe, render or launch on its own (`20260828g` §3.1).
6. An unauthenticated request starts nothing.
7. The API is documented precisely enough that `mcp-harness` can be written against the document
   without reading the server.

## 3. Entities · [E — Entities]

### 3.1 The routes

| method | path | D9 name | maps to |
|---|---|---|---|
| `POST` | `/runs` | `launch_run` | `dispatcher.launch_run` |
| `GET` | `/runs` | `list_runs` | `dispatcher.read_runs` |
| `GET` | `/runs/<id>` | `run_status` | `dispatcher.get_run` |
| `DELETE` | `/runs/<id>` | `cancel_run` | delete the Job |
| `GET` | `/runs/<id>/evidence` | `fetch_evidence` | **501, with the reason** |

`fetch_evidence` is routed and deliberately unimplemented. ADR D5: a run's evidence is written to
a gitignored path and dies with the pod. A 404 would say "no such run"; a 501 naming the missing
capability says the truth, and the route exists so the gap is visible rather than forgotten.

### 3.2 The idempotency key

Chat brought its own event ids; HTTP callers have none, and dedupe cannot be a chat privilege.

A `POST /runs` **may** carry an idempotency key. If it does, that key is the event id, and a repeat
of the same key launches nothing and returns the original run. If it does not, the server mints
one, and the caller is responsible for not retrying blindly.

**Rejected: deriving the key from the request body** (repo+spec hashed). It reads as free dedupe
and is a trap: two deliberate runs of the same spec — the normal case after a fix — would collapse
into one, and the second would silently never happen.

### 3.3 Authentication

A shared bearer token, read from the environment.

**When the token is unset the server refuses to start.** Not "runs open", not "warns" — an
endpoint that creates compute must not have a default-open mode, because that mode is what runs in
production the day the secret fails to mount. Fail closed, loudly, at startup.

This is deliberately modest: one token, one role, matching how this lab already scopes bot
identities. It is not user-level authorization, and the API is not exposed to the internet — ADR
D9 says ClusterIP with no ingress, and the bounded namespace (D4) is what limits blast radius.

## 4. Approach · [A — Approach]

The standard library's `http.server`, and nothing else. The repo runs on Pis and the constitution's
anti-novelty rule applies: a framework here buys routing sugar for five routes and costs a
dependency in the always-on component that cliff 2 says must stay light.

Handlers are thin by construction: parse, call one dispatcher function, format JSON. The gate
asserts that structurally, the same way `20260828g` asserted it of the adapters — a handler that
calls `render_job` or `already_seen` is the defect, and prose will not stop it.

## 5. What this spec does NOT settle · [S — Scope]

**The `mcp-harness` server itself.** It is item 4 and a separate deliverable, plausibly a separate
repo (ADR D9). This spec owes it a written contract, not an implementation.

**The Matrix listener.** ADR D1's `/sync` long-poll is still unbuilt; the chat adapter exists but
nothing feeds it. That is its own spec.

**What happens when a launch fails.** Still open, still deliberately: `record_seen` runs after
`launch` regardless of exit status, so a failed launch is deduped away and never retried. The API
makes this *visible* — a run recorded `failed` is readable through `run_status` — but does not
change it. Fixing it means choosing retry semantics, which belongs with the outcome taxonomy
(ADR D6).

**Deployment.** The Deployment, Service, ServiceAccount, Role and ExternalSecret are `pi-cluster`'s
half of the seam (ADR D10). This repo ships the server and its Dockerfile; the cluster runs it.
