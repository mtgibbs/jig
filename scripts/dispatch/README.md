# Dispatcher module contract

The dispatcher turns input from various transports (chat, HTTP, MCP, etc.) into exactly one run, per the spec in `specs/20260828f-harness-dispatch/spec.md`.

## Transport-agnostic core

The module has one shared core (`dispatch`) and several thin adapters around it:

- **Chat adapter**: `handle_event(text, ...)` parses intent from a chat string and calls `dispatch`.
- **Direct adapter**: `launch_run(repo, spec, strategy, event_id, ...)` takes values directly and calls `dispatch`.

**Rule**: an adapter may build an intent and format a result, but may not decide anything. Dedupe, rendering, and launching happen exactly once for every transport inside `dispatch`.

## Single verb

Only one verb is supported: `fix`. Any message that does not match `@<mention> fix <repo> <spec>` yields no intent and launches nothing.

## Dedupe

Dedupe is keyed on the **event id**, not on a sync cursor. The ledger is an append-only file of event ids already actioned; a fresh dispatcher has actioned nothing (missing ledger is not an error).

## No model, no gate, no retry

The dispatcher contains **no model call, no gate invocation, no retry loop**. Every judgment lives in the worker. This is the core design constraint (validate → map → launch → record, and nothing else).

## Bound Job

A rendered Job is bounded from the start:

- `namespace`: the fleet namespace
- `nodeSelector`: `harness-fleet: "true"`
- `activeDeadlineSeconds`: 1800 seconds
- `ttlSecondsAfterFinished`: 3600 seconds
- `image`: taken from `HARNESS_WORKER_IMAGE` env var
- `args`: `<spec> --repo <repo> --strategy <strategy>` — the argv `run-task.sh` parses,
  appended to the worker image's own ENTRYPOINT. Never env, never `command` (#117: env
  was a convention nothing in the worker read; `command` would displace the entrypoint
  that writes the clone credential)

## Environment variables

- `HARNESS_WORKER_IMAGE`: container image for the Job (default: none; required at runtime)
- `HARNESS_KUBECTL`: command to apply the Job (default: `kubectl`)
- `HARNESS_NAMESPACE`: Kubernetes namespace (default: none; required at runtime)

## Validation → mapping → launch → recording

1. **Parse intent**: `parse_intent(text)` returns a dict or `None`.
2. **Check ledger**: `already_seen(ledger_path, event_id)` returns `True` if already actioned.
3. **Render Job**: `render_job(intent, image=image, namespace=namespace, run_id=run_id)` returns a plain dict.
4. **Launch**: `launch(job)` shells out to `kubectl apply -f -`.
5. **Record**: `record_seen(ledger_path, event_id)` appends the event id.
6. **Record run**: `record_run(registry_path, record)` appends one record to the registry (if path supplied).

`handle_event` orchestrates these steps in order; it never raises.

## Run registry

The registry is a separate index from the event ledger:

- Format: one JSON object per line (JSONL).
- Six fields per record: `event_id`, `repo`, `spec`, `strategy`, `job_name`, `status`.
- Status is `launched` (exit code 0) or `failed` (non-zero).
- A missing registry file is not an error; `read_runs` returns `[]`, `record_run` creates the file and parent dirs.
- `read_runs(registry_path)` returns all records as a list of dicts, skipping corrupt lines.
- `get_run(registry_path, event_id)` returns the single record with that event_id, or `None`.
- The registry is descriptive — a corrupt registry should not break idempotency, so all functions tolerate errors.

## Unrecognised messages

Any message that does not parse (wrong number of parts, no mention prefix, verb not in `{"fix"}`) yields `None` intent and launches nothing.

## Malformed input

Parsing never crashes. `None` is returned for malformed input; the caller must handle this case.

## Adapters

### Chat adapter: `handle_event`

Takes a chat string, parses intent, and dispatches. Never calls the Job renderer, launcher, ledger, or registry directly — only parser and `dispatch`.

### Direct adapter: `launch_run`

Takes `repo`, `spec`, `strategy`, `event_id` as separate values, builds intent internally, and dispatches. Never calls the chat parser or builds a chat string. Falls back to `build-converge` if strategy is empty or None.

This function is what HTTP handlers and MCP tools will call. Its existence proves the seam is real — a seam with one caller has not been shown to be a seam.

## Future transports

The HTTP API and its MCP client are separate surfaces that will call `launch_run` (or `dispatch`) rather than reimplement dedupe, rendering, or launching. Serving evidence is not yet possible because a run's evidence currently dies with its pod.

## The HTTP surface

This module is reached over HTTP by `api.py`, the cluster-internal **dispatch-api**. Its client
contract — routes, status codes, auth and idempotency — is in [`docs/dispatch-api.md`](../../docs/dispatch-api.md).
`mcp-harness` and every other orchestrator are clients of that API, not callers of this module.
