# The coordinator

The receiving half of the worker channel. Workers push their status, their attempt records and
their evidence; this holds them and serves a board with Stop / Pause / Resume.

## It runs anywhere, and that is the point

There is no cluster in the dependency list. A single stdlib Python file and one HTML file:

    python3 scripts/dispatch/coordinator.py          # http://localhost:8877
    docker compose -f docker/compose.yaml up         # same thing, containerised

Then point a loop at it:

    HARNESS_REPORT_URL=http://127.0.0.1:8877 bash scripts/run-loop.sh build-converge specs/<spec>

That is the whole setup. **Measured, not assumed:** with no token, no state path and no
configuration of any kind, the service starts, `/api/runs` answers 200 without an `Authorization`
header, and the board renders.

The same holds in the other direction, and the per-task gates assert it on every run: with
`HARNESS_REPORT_URL` unset the loop is *line-for-line the run it is today* — it writes its files,
posts nothing, and prints nothing about it. An unconfigured channel is not a degraded mode.

**A different worker agent is one variable.** `RALPH_EXEC_CMD` is the executor binding; the loop
invokes whatever it names. qwen via opencode is the default here, and Codex or anything else is a
different value, not a fork.

## Configuration

| variable | default | meaning |
|---|---|---|
| `COORD_PORT` | `8877` | listen port |
| `HARNESS_REPORT_TOKEN` | unset | shared bearer token. **Unset means open** — right on loopback, wrong anywhere else |
| `COORD_STATE_PATH` | unset | JSON snapshot so a restart keeps the run record |
| `COORD_MAX_RUNS` | `200` | oldest-first eviction |
| `COORD_MAX_ARTIFACT_BYTES` | `1048576` | per-POST cap; a larger body gets 413 |

## Routes

| route | auth | who calls it |
|---|---|---|
| `POST /runs/{key}/status` | token | the loop's heartbeat |
| `POST /runs/{key}/attempts` | token | each attempt record as it is written |
| `POST /runs/{key}/attempts/{task}/{n}/artifacts/{kind}` | token | prompt, patch, diff, gate, meta, log |
| `GET /runs/{key}/control` | none | the worker, polling for an intent |
| `POST /runs/{key}/control` | none | the board's Stop / Pause / Resume |
| `GET /api/runs` | none | the board |
| `GET /` | none | the board |

`{key}` is `<host>/<agent>-<pid>` — the identity the loop already has. It is never minted here:
two names for one run are two names that will disagree.

## Where the auth boundary sits

**Writes of run data need the token.** They are the record, and anyone who can forge them can make
the board lie about what happened.

**Reads and control do not**, and that second one is a real relaxation taken knowingly. The Stop
button lives in a browser, and a browser cannot present a bearer header from a plain link —
requiring one would mean the control surface could never work from the page built to house it. The
worst a control write does is stop or pause a build that can be started again. In the homelab that
surface answers only to a name Pi-hole resolves; on a laptop it is loopback. Anywhere else, put
something in front of it.

## Why the worker pushes

Nothing can connect *into* a worker: a container publishes no ports, and a Kubernetes Job's name
is gone moments after it exits. A run that died is exactly the run whose evidence matters most,
and there is nothing left to fetch from. So the worker pushes as it goes, and control flows the
same way — an intent is parked here and collected on the worker's next poll, the way a CI runner
discovers cancellation rather than being told.

## What it deliberately does not do

It does not build, launch, or schedule anything — `scripts/dispatch/api.py` owns that and stays
cluster-internal with no ingress (ADR-001 D9). It does not keep artifacts forever: runs are
evicted oldest-first, and the state snapshot excludes artifact bytes, because they are the bulk
and the worker can send them again. A coordinator that keeps everything is a log server nobody
configured.
