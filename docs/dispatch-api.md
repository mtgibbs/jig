# The dispatch API

The HTTP surface over the dispatch core. It is the **only** programmatic front door to the fleet:
chat, `mcp-harness`, and any future orchestrator are all clients of this, not peers of it.

Per ADR-001 D9 it is **cluster-internal** — no ingress, no public route. `mcp-harness` is a
separate server that is a *client* of this API; it is not this API with an MCP hat on.

## The seam it sits on

`api.py` is an **adapter**. It may build an intent and format a result; it may not decide anything.
Every decision — whether an event was already seen, what Job to render, whether to launch — lives
in `dispatcher.py` and is reached by calling it. Nothing under the seam is reimplemented here, and
a route that needed new decision logic would be a signal that the logic belongs in the core.

## Configuration

Read from the environment at startup. All are required except the namespace.

| variable | meaning |
|---|---|
| `HARNESS_API_TOKEN` | shared bearer token. **No default.** |
| `HARNESS_LEDGER_PATH` | event-id ledger — the idempotency record |
| `HARNESS_REGISTRY_PATH` | run registry |
| `HARNESS_WORKER_IMAGE` | image the Job runs |
| `HARNESS_NAMESPACE` | defaults to `harness-fleet` |
| `HARNESS_KUBECTL` | command used to reach the cluster, defaults to `kubectl` |

**`serve()` refuses to start when `HARNESS_API_TOKEN` is unset or empty**, exits non-zero, and names
the variable. There is deliberately no default-open mode: an endpoint that creates compute must not
have one, because that mode is what runs in production the day the secret fails to mount.

## Authentication

Every request carries `Authorization: Bearer <HARNESS_API_TOKEN>`. A request without it, or with the
wrong token, gets **401** and reaches no dispatcher function at all — the check runs before routing,
so an unauthenticated caller cannot launch, read, or cancel anything. All responses are JSON.

## Routes

### `POST /runs` — start a run

```json
{"repo": "mtgibbs/harness", "spec": "20260828h-dispatch-api",
 "strategy": "build-converge", "idempotency_key": "<event-id>"}
```

All four fields are required; an incomplete body gets **400** and launches nothing.

**Idempotency is the correctness mechanism, not a convenience.** `idempotency_key` becomes the
event id in the ledger. Replaying a request with a key already recorded returns success and starts
**no second run** — which is what makes an at-least-once transport (a Matrix `/sync`, a webhook
redelivery) safe to point at this endpoint. Send the upstream event's own id; do not mint a fresh
one per attempt, or a retry becomes a duplicate run.

### `GET /runs` — list runs

`200` with the runs under a named key: `{"runs": [...]}`.

### `GET /runs/<id>` — read one run

`200` with the run's record, or **404** if the id is unknown.

### `DELETE /runs/<id>` — cancel a run

Looks the run up first. An unknown id gets **404** and **runs no command at all** — the ordering is
a security property: an adapter that will shell out to `kubectl` for an id the registry never
recorded is a way to delete arbitrary Jobs in the namespace. A known id deletes the Job named
`run-<id>` in `HARNESS_NAMESPACE` and reports whether the deletion succeeded. A missing `kubectl`
is reported in the body, not raised.

### `GET /runs/<id>/evidence` — declared, not built

Always **501**, naming the gap. Never 404: the run exists, and 404 would tell the caller it does
not, leaving a client unable to distinguish "wrong run" from "this service cannot answer that yet".
Evidence does not leave the pod at all today — that is ADR-001 **D5**, still unbuilt — so the gap
is in this service and the status code says so. When D5 lands, this route changes and no client
that already handles 501 has to be rewritten.

## Status codes

| code | when |
|---|---|
| 200 | the request was served |
| 400 | `POST /runs` body was incomplete — nothing launched |
| 401 | missing or wrong bearer token — no dispatcher function was reached |
| 404 | no such run |
| 501 | the route exists and the capability does not (evidence) |

## Writing a client

1. Set `Authorization: Bearer …` on every request; expect 401 to mean the token, not the route.
2. Send the upstream event's own id as `idempotency_key` and treat a replay as success.
3. Treat 501 as "not yet", distinct from 404 "not there" — do not collapse them.
4. Do not reach past this API to `dispatcher.py`. The seam is the contract.
