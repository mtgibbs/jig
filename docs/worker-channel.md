# The worker's outbound channel — status reporting and control polling

**Status:** design reference, 2026-08-28. Owner: Matt.

A harness worker loop runs as a container or k8s Job that **cannot receive external signals**. A
loop in a k8s Job has an ephemeral name and ceases to exist when it finishes; a loop in a
container has no published port. So a control cannot be *sent* to a worker — the worker must
**notice** it by polling outbound, exactly as GitHub Actions and GitLab runners discover
cancellation.

## Why nothing can connect INTO a worker

| scenario | what fails if you require inbound |
|---|---|
| container behind NAT | no reachable port |
| k8s Job | name is ephemeral; the pod disappears on completion, taking any evidence tree with it |
| laptop run without infrastructure | no server to dial |

This is not a limitation — it is the design that makes the harness portable enough to run behind
NAT on someone's home network. Requiring inbound would make the harness *un*portable.

Instead, the worker:
- **posts status outbound** (worker → coordinator) as it happens
- **polls control intents outbound** (worker → coordinator) between units of work

Both directions are outbound-initiated, so nothing must ever dial the worker.

## Configuration

Read from the environment. One variable is required, one is optional.

| variable | meaning | default |
|---|---|---|
| `HARNESS_REPORT_URL` | base URL for the worker channel (`{base}/runs/{run_key}/status`, etc.) | **unset** — if empty or absent, the loop behaves exactly as today |
| `HARNESS_REPORT_TOKEN` | bearer token for the channel | **unset** — no authentication when absent |

With `HARNESS_REPORT_URL` unset or empty, the loop posts nothing, polls nothing, and prints
nothing about the channel. This is the **portability guarantee**: `run-loop.sh` must keep running
on a laptop with no infrastructure.

## The run key

The worker reuses the identity it already has: `<host>/<agent>-<pid>`, built by `_ralph_host` in
`ralph-log.sh`. This is the `run_key` used in all endpoint paths.

Do not mint a second identity. Two names for one run are two names that will disagree.

## Endpoints

### `POST {base}/runs/{run_key}/status` — outbound status

Every `hb_write` call (13 times over 7 phases) posts the same record it already writes to the
evidence tree as JSON:

```json
{
  "agent": "<agent>",
  "run_key": "<host>/<agent>-<pid>",
  "spec": "<spec-slug>",
  "phase": "<phase-name>",
  "outcome": "<success|fail|skip>",
  "task": <n>,
  "attempt": <n>,
  "verify_status": "<status>",
  "exec_status": "<status>",
  "start": <timestamp>,
  "end": <timestamp>,
  "bytes": <count>,
  "commit": "<sha>"
}
```

The POST is fire-and-forget and its own failure must be **silent and total**: an unreachable
coordinator, a connection refused, a 500, a timeout — none of them may fail, stall, or alter the
run, and none may print anything that would be mistaken for a loop error.

### `POST {base}/runs/{run_key}/attempts` — outbound attempt metadata

Every `log_meta` call (per attempt) posts the same metadata record as JSON:

```json
{
  "run_key": "<host>/<agent>-<pid>",
  "task": <n>,
  "attempt": <n>,
  "outcome": "<success|fail|skip>",
  "duration_ms": <ms>,
  "exec_status": "<status>",
  "verify_status": "<status>",
  "bytes": <count>,
  "start": <timestamp>,
  "end": <timestamp>
}
```

Reuses the same helper as status. Do not compose a different or reduced record; the point is that
what a reader sees matches what the evidence tree holds.

### `GET {base}/runs/{run_key}/control` — inbound control intent (polled)

Between attempts and between tasks, the loop polls for a control intent:

```json
// Request — no body
GET {base}/runs/{run_key}/control
Authorization: Bearer <token>

// Example response
{
  "action": "cancel" | "pause" | "none" | null
}
```

The loop honours only two actions:

- `cancel` — stop the run cleanly, stamp a terminal phase, and exit non-zero with a distinct status
- `pause` — hold before the next unit of work, keep heartbeating, re-poll on a sleep interval

Every other case means **carry on**: no URL configured, an unreachable coordinator, a timeout, a
non-2xx answer, a body that does not parse, or an action that is absent/unrecognised.

### Why controls are polled at those two moments

They are the points where the loop is between units of work and can act without abandoning
anything in flight. Cancelling mid-executor would strand a half-written tree; the executor is
already bounded by its own watchdog, so the wait is finite.

## Failure discipline

### Fail open on the channel, fail closed on the intent

| scenario | outcome |
|---|---|
| `HARNESS_REPORT_URL` unset or empty | no change — posts nothing, polls nothing |
| coordinator unreachable | carry on, silently |
| timeout, connection refused, 500 | carry on, silently |
| unreadable JSON, missing action, unknown action | carry on, silently |
| action is `cancel` | stop the run cleanly |

A coordinator that is down must never stop a build. An answer that cannot be read must never be
treated as a cancel.

### Bounded calls

Every call has a short timeout. A coordinator that accepts a connection and never answers must not
hold the build.

## Explicit exclusions

| what | where it belongs |
|---|---|
| the coordinator itself | dispatch API spec (receiving routes) |
| streaming transcripts | D5 — built after status records prove the channel |
| inbound `/statusz` endpoint | not needed — a k8s exec probe can read the status file directly |
| retry logic | already shipped (`20260828l`), startup decision, not arriving intent |

## Writing a client

1. **Run key is `<host>/<agent>-<pid>`** — do not assume a different identity.
2. **Status and attempt records match the evidence tree** — the worker does not transform or
   truncate them.
3. **Control intent is read between units of work** — do not expect to interrupt mid-executor.
4. **Cancel is terminal** — stamp a phase before exiting; a cancelled run is not a failed one.

## Norms

1. **Name the states a check must tell apart.** "No intent", "coordinator unreachable" and
   "coordinator said carry on" must all resolve to *carry on* — but a **cancel** must never be
   confused with any of them.
2. **Bound every call**, with an explicit branch for calls that never returned.
3. **Never echo the token.**
4. **Fail open on the channel, fail closed on the intent.**
