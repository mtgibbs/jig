# MUTANT: ac20
# TARGET: docs/coordinator.md
# WHY: leaves the runbook describing the hand-started coordinator. The commands it lists all
# WHY: work, so nothing looks stale — and the operator surface built to remove that friction is
# WHY: documented nowhere a person would look.
# The coordinator

The receiving half of the worker channel. Workers push their status, their attempt records and
their evidence; this holds them and serves a board with Stop / Pause / Resume.

## It runs anywhere, and that is the point

There is no cluster in the dependency list. A single stdlib Python file and one HTML file:

    python3 scripts/dispatch/coordinator.py start                       # http://127.0.0.1:8877
    python3 scripts/dispatch/coordinator.py          # the same thing, by hand
    docker compose -f docker/compose.yaml up         # the same thing, containerised

Then point a loop at it — or let `HARNESS_REPORT_URL=...` do both at once:

    bash scripts/run-loop.sh HARNESS_REPORT_URL=... build-converge specs/<spec>
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

## The local board (`python3 scripts/dispatch/coordinator.py`)

The laptop path, needing python3 and nothing else — no Docker, and no remembering which port
you started it on.

| command | what it does |
|---|---|
| `python3 scripts/dispatch/coordinator.py start` | starts the coordinator in the background and prints the URL. Idempotent: a board already running here, or already serving that port from another worktree, is reported rather than duplicated |
| `python3 scripts/dispatch/coordinator.py status` | running (and where) or stopped. Exit 0 running, 3 stopped |
| `python3 scripts/dispatch/coordinator.py stop` | stops the board it started. Exit 0 either way |
| `python3 scripts/dispatch/coordinator.py url` | prints the URL and nothing else, for scripting |

The port is `COORD_PORT` (default `8877`) — the same variable `coordinator.py` reads. State
lives in `.jig/` at the repo root (gitignored): `board.pid`, `board.log`, and the run snapshot
`coord-state.json`, so a restart keeps the runs it has seen.

**`run-loop.sh`** does the whole thing in one command: it starts the board if it is
down, exports `HARNESS_REPORT_URL` for the phases, and prints the URL before the first phase.

    bash scripts/run-loop.sh HARNESS_REPORT_URL=... build-converge specs/<spec>

It is **opt-in and stays that way.** Without the flag, `run-loop.sh` starts no process and
leaves `HARNESS_REPORT_URL` exactly as it found it — an unconfigured channel is not a degraded
mode, and making the board the default would quietly make every run a reporting run.

## What the board shows about a gate's mutants

Select a task, then an attempt: its `selftest` artifact opens on its own. That is the record of
what the task's mutant corpus did when the gate first went green (`20260831u`) — the verdict
counts, then one row per mutant, **survivors first**, each naming the assertion it was built to
break, the file it replaced, and the WHY its author wrote.

Anything that was **not** killed also carries its install-time diff: the actual difference
between the real file and the mutant that replaced it. That is how a mutant was formed, and
once the worker is gone it exists nowhere else — which is the reason the verdicts are pushed
*before* a survivor STOPs the run, not after.

A killed mutant's diff is deliberately not shipped. It is reconstructible from the corpus file
committed beside the gate, and it is the only field large enough to matter.

## Configuration

| variable | default | meaning |
|---|---|---|
| `COORD_PORT` | `8877` | listen port |
| `HARNESS_REPORT_TOKEN` | unset | shared bearer token. **Unset means open** — right on loopback, wrong anywhere else |
| `COORD_STATE_PATH` | unset | JSON snapshot so a restart keeps the run record |
| `COORD_MAX_RUNS` | `200` | oldest-first eviction |
| `HARNESS_ARTIFACT_MAX_BYTES` | `1048576` | per-artifact cap; a larger body gets truncated with a visible marker |
| `COORD_MAX_ARTIFACT_BYTES` | `1048576` | per-POST cap; a larger body gets 413 |

## Routes

| route | auth | who calls it |
|---|---|---|
| `POST /runs/{key}/status` | token | the loop's heartbeat |
| `POST /runs/{key}/attempts` | token | each attempt record as it is written |
| `POST /runs/{key}/attempts/{task}/{n}/artifacts/{kind}` | token | prompt, patch, diff, gate, meta, log |
| | | **prompt**: executor's original instructions |
| | | **patch**: applyable change from a passing attempt |
| | | **diff**: diagnostic bundle (verify output, tracked diff, untracked files) from a failing attempt |
| | | **gate**: per-assertion verdicts |
| | | **meta**: run and executor metadata |
| | | **log**: executor's stdout+stderr transcript |
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

## What the evidence channel deliberately does not do

It does not store, index, retain, or serve artifacts — that is the coordinator's responsibility.
It does not retry failed pushes; an unreachable coordinator simply loses that artifact. It does
not guarantee order; a late `gate` may arrive after `log` if the network interleaves them. It
does not deduplicate; the same artifact sent twice is stored twice. It does not replay; once an
artifact leaves, it cannot be re-sent. It ends at the POST.
