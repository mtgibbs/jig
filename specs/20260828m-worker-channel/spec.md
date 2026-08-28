# Spec: the worker's outbound channel — report status, notice controls

Tools: python3 bash git
MCP: none
Permissions: read, write, bash

## 1. Why · [R — Requirements]

There is no way to watch work as it happens, and no way to stop a run once it starts.

Both are the same missing piece, and it is **not instrumentation**. `hb_write` already emits a
well-formed status record at thirteen call sites across seven phases — task index, attempt, phase,
verify result, commit, timestamps. It is a build-agent status reporter with the wire protocol
missing: its last line writes a file, and that is the only thing hardwired.

### The constraint that decides the design

**Nothing can connect into a worker.** A loop in a container has no published port and an opaque
name; a loop in a k8s Job has an ephemeral name and then *ceases to exist*, taking its evidence
tree with it. So a status endpoint inside the worker is unreachable by anything that wants to watch
it, and a control cannot be *sent* to a worker at all.

This is not a quirk of one deployment. It is how the systems this resembles already work:

| | how status gets out | how cancellation gets in |
|---|---|---|
| GitHub Actions runner | polls outbound, streams logs outbound | **notices it while polling** |
| GitLab runner | `PATCH`es the job trace outward | **notices it while polling** |
| Jenkins | agent-initiated (JNLP/websocket) is the modern default | same |

In none of them does anything dial the agent. When you watch a job progress, you are watching the
**coordinator**. That inversion is exactly what makes a runner portable enough to sit behind NAT on
someone's home network — and requiring inbound is what would make ours *un*portable.

So: **the worker pushes status out and polls intents in, both outbound-initiated.** One channel,
two directions.

### And it collapses D5

ADR-001 **D5** — evidence must leave the pod — is unbuilt, which is why `/runs/<id>/evidence`
answers 501. Framed as *"retrieve evidence from a pod that has finished"* it is hard. Actions does
not do that: it **streams as it produces**, so a run that dies mid-flight has already delivered
everything up to the moment it died. That is strictly better than a post-hoc export, which loses
exactly the runs most worth reading — the ones that crashed.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. With `HARNESS_REPORT_URL` unset the loop behaves **exactly** as today: writes its files, posts
   nothing, polls nothing. This is the portability bar — `run-loop.sh` must still run on a laptop
   with no infrastructure.
2. When it is set, every status the loop already writes is also POSTed, keyed by the run's existing
   run key.
3. Each attempt record is POSTed as it is written.
4. The loop polls for a control intent between attempts and between tasks, and honours `cancel`
   and `pause`.
5. **No failure of the channel can fail, stall or alter a run.** An unreachable coordinator, a
   timeout, a 500, malformed JSON — every one of them means "no intent, carry on".
6. The bearer token never appears in any log line, transcript or evidence file.

## 3. Entities · [E — Entities]

### 3.1 Identity

The worker already has one: `<host>/<agent>-<pid>`, built by `_ralph_host` and used as the evidence
path and the `run_key` field. Reuse it. Minting a second identity for reporting would create two
names for one run and guarantee they disagree.

### 3.2 The two directions

| direction | when | endpoint |
|---|---|---|
| status out | every `hb_write` | `POST {base}/runs/{run_key}/status` |
| attempt out | every `log_meta` | `POST {base}/runs/{run_key}/attempts` |
| intent in | between attempts, between tasks | `GET {base}/runs/{run_key}/control` |

### 3.3 Why controls are polled at *those* two moments

They are the points where the loop is between units of work and can act without abandoning
anything in flight. Cancelling mid-executor would strand a half-written tree; the executor is
already bounded by its own watchdog, so the wait is finite.

### 3.4 Best-effort is a hard requirement, not a nicety

Reporting is observability. A run that fails because a dashboard was down is worse than no
dashboard at all — and this loop already holds that line for its file writers, whose helpers are
documented as best-effort and never able to fail a run. The channel adopts the same discipline,
with one addition: **bounded**. A coordinator that accepts a connection and never answers must not
hold the loop, so every call has a timeout and a timeout means "carry on".

## 4. Approach · [A — Approach]

One helper for posting, one for polling, both in `ralph-status.sh` beside the record they carry.
`curl` if present, else `python3` — the loop container has both, and a laptop has at least one.
Configuration is environment variables, like every other knob.

Nothing changes about when a status is written or what it contains. The sink gains a second
destination; the record is untouched.

## 5. Scope · [S — Structure: boundary]

### In scope
- The config, the post helper, status and attempt reporting, the control poll, `cancel`, `pause`, docs.

### Out of scope
- **The coordinator itself.** The dispatch API grows the receiving routes in its own spec; this one
  is verified against a stub, which is stronger anyway — it pins the contract without waiting on
  the other half.
- **Streaming transcripts.** §1 argues that is how D5 should be built; it is a bigger change to the
  writers and belongs after the small records prove the channel.
- **A local `/statusz`.** A k8s exec probe can read the status file directly, so an inbound HTTP
  surface earns nothing here and would be the one part of the design that needs the network to
  cooperate.
- Retry — already shipped (`20260828l`), and it is a startup decision rather than an arriving intent.

## 6. Prior decisions / facts the implementer must know · [S]

| fact | source | consequence |
|---|---|---|
| `hb_write` is called 13 times over 7 phases | `ralph-build.sh` | the reporting point already exists; do not add new ones |
| `hb_write` must never fail a run | `ralph-status.sh` header | the POST is fire-and-forget, and its own failure is silent |
| a redirect's target failure is reported before `2>/dev/null` applies | fixed in `20260828e` | do not assume a redirect silences anything |
| the run key is `<host>/<agent>-<pid>` | `ralph-log.sh` `_ralph_host` | reuse it; do not mint a second identity |
| the executor is bounded by `RALPH_EXEC_TIMEOUT` | `ralph-build.sh` | polling between attempts has a finite worst-case wait |
| a function whose last construct is a loop returns that loop's status | observed twice | write `return 0` explicitly |

## 7. Norms · [N — Norms]

1. **Name the states a check must tell apart.** "No intent", "the coordinator is unreachable" and
   "the coordinator said carry on" must all resolve to *carry on* — but a **cancel** must never be
   confused with any of them, so the intent is honoured only when it is explicitly and validly read.
2. Bound every call, with an explicit branch for the call that never returned.
3. Never echo the credential.
4. Fail open on the channel, fail closed on the intent: an unreadable answer is not a cancel.

## 8. Safeguards · [S — Safeguards]

- The channel is off unless configured, and its absence is not an error.
- A cancel stamps a terminal phase before exiting, so the run does not freeze mid-record — the
  half of `harness#22` a worker *can* fix for itself.
- Pause holds without spinning: it re-polls on an interval and keeps heartbeating, so a paused run
  is visibly paused rather than indistinguishable from a hung one.

## 9. Task breakdown · [O — Operations]

Five tasks. See `tasks.txt`.

## 10. Acceptance criteria (EARS) · [O]

Per-task criteria live in `tasks/T<NN>-*/verify.sh`; the spec-level gate holds end state only.

- **AC-END-1** With no coordinator configured, a run shall be byte-for-byte the run it is today.
- **AC-END-2** With a coordinator that never answers, a run shall complete unchanged.
