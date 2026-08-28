# Dispatcher module contract

The dispatcher turns a chat message into exactly one run, per the spec in `specs/20260828f-harness-dispatch/spec.md`.

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
- `env`: `REPO`, `SPEC`, `STRATEGY` (strategy is always `build-converge`)

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

`handle_event` orchestrates these steps in order; it never raises.

## Unrecognised messages

Any message that does not parse (wrong number of parts, no mention prefix, verb not in `{"fix"}`) yields `None` intent and launches nothing.

## Malformed input

Parsing never crashes. `None` is returned for malformed input; the caller must handle this case.
