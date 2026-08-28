# Spec: one dispatch core, many transports

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor qwen)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, python3
- **MCP:** none
- **Touches:** `scripts/dispatch/dispatcher.py`, `scripts/dispatch/README.md`.
  **No change** to `ralph-build.sh`, `run-loop.sh`, `ralph-log.sh`, `ralph-status.sh`, or any
  other spec.

---

## 1. Why · [R — Requirements]

`20260828f-harness-dispatch` built the dispatcher's core logic and proved it against a mock
cluster. It has one entry point, `handle_event(text, event_id, ...)`, and that entry point takes a
**chat string**.

ADR-001 D9 specifies an HTTP API — `launch_run(repo, spec, strategy)`, `run_status`, `list_runs`,
`cancel_run`, `fetch_evidence` — whose MCP client is a separate `mcp-harness` server. Chat is
therefore **one transport among several**, not the interface.

Today an HTTP `launch_run` cannot reuse the existing code. It would have to either duplicate the
dedupe → render → launch → record sequence, or synthesise a fake `@harness fix <repo> <spec>`
string and feed it back through the chat parser. The first gives us **two copies of the
idempotency logic**, which ADR D1 names as the correctness mechanism; the second makes an internal
API's behaviour depend on chat grammar. Both are wrong, and they are wrong in a way that only
shows up once a second transport exists.

The defect is structural: the shared middle is welded inside a transport-specific function. This
spec cuts it out.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A transport-agnostic core takes an **already-parsed intent** plus an event id, and performs
   dedupe → render → launch → record. It never sees a chat string.
2. The chat path produces identical behaviour to today, and reaches it **through** that core —
   there is exactly one copy of the sequence.
3. A caller holding `repo`, `spec` and `strategy` as separate values can dispatch a run without
   constructing chat text and without touching the chat parser.
4. Every run the core launches is recorded in a **run registry** naming event id, repo, spec,
   strategy, Job name and coarse status (ADR D8).
5. The registry is an index, **not a history database** — it holds the fields above and nothing
   that would need backing up, migrating or reconciling (ADR D8, cliff 2).
6. The core still contains **no model call, no gate invocation, no retry loop** (ADR D3). The
   thinness property survives the refactor.

## 3. Entities · [E — Entities]

### 3.1 The dispatch core

```
parse_intent(text)          transport-specific   chat  →  intent | None
dispatch(intent, event_id)  SHARED               intent →  result
handle_event(text, ...)     transport adapter    chat  →  parse_intent, then dispatch
launch_run(repo, spec, ...) transport adapter    values →  intent, then dispatch
```

The rule that makes this worth doing: **an adapter may build an intent and may format a result. It
may not decide anything.** Dedupe, rendering and launching happen once, in the middle, for every
transport. A second adapter that re-implements any of those three is the defect this spec exists
to prevent.

### 3.2 The run registry

One record per launched run: event id, repo, spec, strategy, Job name, coarse status.

It answers "what runs exist and what became of them" for the read endpoints, and nothing else.
Liveness is read from the Job object; durable history is the `run_summary` in the PR and the
`loop-doctor` corpus (ADR D8). A registry that owns history is a registry that must be backed up
and migrated, and cliff 2 says the always-on component is exactly where that weight must not land.

**It is separate from the event ledger.** The ledger answers one question — has this event id been
actioned — and is the correctness mechanism for dedupe. The registry is descriptive. Collapsing
them would make dedupe depend on a richer structure than it needs, and a corrupt registry would
then silently break idempotency.

## 4. Approach · [A — Approach]

Pure extraction plus one new store. The sequence inside `dispatch()` is the sequence
`handle_event` performs today, moved without alteration, and `handle_event` becomes a two-line
adapter over it. `launch_run` is a second adapter proving the seam is real — a seam with one
caller has not been shown to be a seam.

**Rejected: making `dispatch` take an optional text argument.** That preserves the weld under a
new name and lets a future transport slip a string through.

**Rejected: the HTTP server in this spec.** The server is a surface over this core and needs its
own gate; the follow-up spec owns it. What this spec must guarantee is that when the server
arrives, it has something to call.

## 5. What this spec does NOT settle · [S — Scope]

**`fetch_evidence`.** ADR D5 says a run's evidence is written to a gitignored path that dies with
the pod, and that carrying it off the machine is unbuilt. An endpoint serving evidence that does
not survive its run would be a promise the system cannot keep.

**What happens when a launch fails.** Today `record_seen` runs after `launch` regardless of exit
status, so a failed launch is deduped away and silently never runs. That is a real defect and it
is deliberately **not** fixed here: fixing it means choosing retry semantics, and the retry
question belongs with the outcome taxonomy (ADR D6), not with a refactor. This spec must not make
it worse — the core keeps today's behaviour, and the follow-up decides.

**Which image the Job runs.** Unchanged from `20260828f-harness-dispatch` §5.
