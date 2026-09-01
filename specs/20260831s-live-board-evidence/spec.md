# Spec: 20260831s-live-board-evidence

- **Status:** Draft v0.1
- **Owner:** mtgibbs
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Touches:** `scripts/ralph-log.sh`, `scripts/ralph-build.sh`, `scripts/dispatch/coordinator.py`,
  `scripts/dispatch/board.html`, `scripts/jig-board.sh` (new), `scripts/run-loop.sh`,
  `docs/coordinator.md`, `.gitignore`
- **Tools:** git, bash, python3, curl
- **MCP:** none
- **Permissions:** write:scripts/**, write:docs/**, exec:git, exec:python3, net:127.0.0.1
  <!-- recorded, not verified -->

---

## 1. Why · [R — Requirements]

`20260831u` shipped: the loop now runs each task's mutant corpus the moment that task's gate
first goes green, and `SELFTEST_EVID` appends the verdict rows to the worked repo's
`.evidence/`. Those rows never leave the worker. The coordinator does not know a selftest
happened, the board shows nothing about it, and the only place a survivor's install-time diff
can be read is a file on the machine that produced it — which for a dispatched Job is a
container that is gone moments after it exits.

The board cannot show it even in principle, because the coordinator **stores artifacts and
serves none of them**. `coordinator.py`'s `/api/artifact` route is a stub that answers
`400 {"error": "key required"}` for every request, including well-formed ones; `board.html`
renders artifact names as inert pills captioned "evidence egress not built yet". Every prompt,
patch, diff, gate transcript and meta record a worker has ever pushed is sitting in memory
behind a route that cannot return it.

And the board is awkward to reach from the machine most runs actually happen on. Running one
locally means remembering two things at once — start `coordinator.py`, then export
`HARNESS_REPORT_URL` at the right value — and the docker-compose "laptop mode" needs Docker,
which the dependency list (`a clone, a shell, and a model endpoint`) does not.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A run that reports to a coordinator ships its per-task selftest verdicts as an artifact, over
   the channel it already uses for prompts and patches. A run that reports nowhere is
   byte-identical to the run it is today.
2. The coordinator serves a stored artifact's bytes back to a reader that names it, and refuses
   — without mutating the board — when it cannot.
3. The board shows, for a selected attempt, what its gate's mutants did: the verdict counts,
   survivors first, each mutant's assertion id, target and WHY, and for anything that was not
   killed, the install-time diff that shows how the mutant was formed.
4. `scripts/jig-board.sh start` brings the board up on a laptop with python3 and nothing else,
   and `scripts/run-loop.sh --board <strategy> <spec>` wires a run to it in one command.
5. Without `--board`, `run-loop.sh` starts nothing and sets nothing.

## 3. Entities · [E — Entities]

### The selftest row (exists — `scripts/gate-selftest.sh`, `20260830f`)

Appended to `$SELFTEST_EVID/selftest-<spec-slug>.jsonl`, one JSON object per line. Two shapes:

```
{"ts","run_id","spec","task","mutant","assertion","target","why","verdict","gate_rc","diff"}
{"run_complete":true,"run_id","spec","task","killed","survivor","wrong_reason","hung"}
```

`verdict` ∈ `KILLED` · `SURVIVOR` · `WRONG-REASON` · `HUNG`. `diff` is the unified diff between
the real target file and the mutant's replacement — **this is the field that shows how a mutant
was formed**, and the only one that is large.

### The compacted selftest artifact (new — this spec)

The same JSONL, one line per input line, with exactly one transformation: **`diff` is dropped
from every `KILLED` row, and clipped on every other row.** A killed mutant's diff is
reconstructible from the corpus file that is committed beside the gate; a survivor's is the
thing a reader needs and cannot get anywhere else. Field names, order and verdict vocabulary
are unchanged — the artifact is readable by anything that already reads the evidence store.

- Clip budget: `SELFTEST_ARTIFACT_DIFF_LINES`, default `40`. A clipped diff ends with the
  literal line `--- diff clipped at N lines ---` inside the JSON string value.
- Artifact kind: `selftest`. Artifact key, per the existing route: `<task-slug>/<attempt>/selftest`.

### The artifact read route (new — this spec)

```
GET /api/artifact?key=<run-key>&name=<task>/<attempt>/<kind>
```

`run-key` is `<host>/<agent>-<pid>` and contains a slash; it is URL-encoded as a query value,
never a path segment. Answers `200 text/plain; charset=utf-8` with the stored bytes verbatim.

### The local board service (new — this spec)

`scripts/jig-board.sh <start|stop|status|url>`. State under `.jig/` at the repo root
(gitignored): `board.pid`, `board.log`, `coord-state.json`. Port is `COORD_PORT` (default
`8877`) — the variable `coordinator.py` already reads. **No new port variable is invented.**

## 4. Approach · [A — Approach]

Four changes, each mirroring machinery that already exists:

1. **The push** mirrors `ralph_log_artifact_push` in `scripts/ralph-log.sh` — same transport,
   same fire-and-forget contract, same `HARNESS_REPORT_URL`-unset early return. It is a new
   *kind*, not a new route: `coordinator.py` already accepts any kind at
   `/runs/{key}/attempts/{task}/{n}/artifacts/{kind}`, so the receiving side needs no change at
   all for T1.
2. **The read** fills in the stub at `coordinator.py:196` next to `/api/runs`, under the same
   auth posture (reads are open; the boundary is on writes) and the same `_json` helpers.
3. **The panel** is another `detail()` section in `board.html`, built from the same
   `r.artifacts` list the attempt cards already render, fetched with the same `fetch`+`poll`
   idiom.
4. **The service** is a pidfile wrapper of the form `docs/coordinator.md` already documents by
   hand, plus one flag on `run-loop.sh` parsed before its existing `--list` branch.

**Rejected: a `/runs/{key}/selftest` route.** A run-level route would need coordinator state,
snapshot handling and eviction of its own, and would key selftest evidence differently from the
gate transcript produced in the same second by the same task. The selftest happens at a known
attempt of a known task; the artifact channel is already keyed exactly that way.

**Rejected: pushing the rows uncompacted.** `HARNESS_ARTIFACT_MAX_BYTES` defaults to 8192 and
the truncator clips at a byte offset, which cuts a JSON line in half. Compaction is what keeps
the normal case (everything killed) small enough that no truncation happens at all.

**Rejected: serving `.evidence/mutant-ledger.html` from the board.** That file is repo history
across every spec; the board is live runs. Owner's call, 2026-08-31: this run's rows only.

## 5. Scope · [S — Structure: boundary]

### In scope

- `scripts/ralph-log.sh` — one new push function.
- `scripts/ralph-build.sh` — one call, inside the existing first-green selftest block.
- `scripts/dispatch/coordinator.py` — the `/api/artifact` GET route.
- `scripts/dispatch/board.html` — the mutant panel and the artifact viewer.
- `scripts/jig-board.sh` — new.
- `scripts/run-loop.sh` — the `--board` flag.
- `docs/coordinator.md`, `.gitignore`.

### Out of scope

- `scripts/gate-selftest.sh` and its row shape — `20260830f` owns it; this spec reads it.
- `scripts/mutant-ledger.py` and `.evidence/mutant-ledger.{md,html}` — unchanged, still the
  repo-wide historical view.
- `scripts/selftest-sweep.sh` — unchanged.
- `scripts/dispatch/api.py` — the dispatch API stays cluster-internal with no ingress
  (ADR-001 D9); nothing here touches it.
- The pi-cluster manifests. The deployed coordinator picks this up as an image bump; no
  manifest change is part of this spec.
- The `ralph-*` → `jig-*` runtime rename (issue #81). This spec renames nothing; it only
  *names* its one new file under the ratified identity.

## 6. Prior decisions / facts the implementer must know · [S — Structure: system fit & deps]

- **The selftest already runs and already records.** `scripts/ralph-build.sh` lines ~605–630:
  inside the `if out="$(run_gates ...)"` success branch, after `log_gate`/`log_patch`, the loop
  resolves `_st_dir="$(dirname "$_st_gate")/mutants"` and, when that corpus exists, runs
  `SELFTEST_EVID="${SELFTEST_EVID:-$ROOT/.evidence}" bash gate-selftest.sh "$(dirname "$_st_gate")"`.
  The push belongs immediately after that invocation, before the `_st_rc` refusal branch — a
  run that STOPs on a survivor is exactly the run whose evidence must have left the worker.
- **The evidence file to read is `$SELFTEST_EVID/selftest-<spec-slug>.jsonl`**, and it is
  **append-only across tasks and runs**: `.evidence/selftest-20260829c-hermetic-gate.jsonl`
  holds rows for `T01-reset` and `T02-migration` and several `run_id`s. The push must select
  the rows for the current `run_id`, not send the file.
- **The artifact route accepts any kind.** `coordinator.py` `do_POST`, the `known` tuple:
  `len(rest) == 5 and rest[0] == "attempts" and rest[3] == "artifacts"` — `rest[4]` is
  unconstrained and stored at `r["artifacts"]["%s/%s/%s" % (rest[1], rest[2], rest[4])]`.
- **`/api/artifact` is a stub, and the route above it is dead.** Lines ~192–197:
  `if len(parts) == 4 and parts[0] == "artifact":` looks up a run, discards it, and returns
  `404 {"error": "use /api/artifact"}`; the next branch answers `400 {"error": "key required"}`
  unconditionally. Replace both with one working route.
- **Reads must not mutate the board (harness#46).** `_touch()` creates a run row *and* runs
  oldest-first eviction, so a lookup for a key that does not exist must never call it — a 404
  that evicts a real run's record to make room for a ghost is the exact bug that comment
  guards against. Use `RUNS.get`.
- **Artifact bytes are worker-supplied and never trusted as markup.** They are served
  `text/plain`, and the board inserts them with `textContent`, never `innerHTML`. `board.html`
  builds its DOM from template literals today; every field this spec adds comes from a
  worker-controlled JSON string (`why`, `target`, `mutant`, `diff`) and must not join that
  path unescaped.
- **The unset channel is not a degraded mode.** `docs/coordinator.md`: with
  `HARNESS_REPORT_URL` unset the loop is *line-for-line the run it is today* — it writes its
  files, posts nothing, and prints nothing about it. `specs/lib/assert.sh` `unset`s
  `HARNESS_REPORT_URL` and `HARNESS_REPORT_TOKEN` on load precisely because a fixture loop that
  inherited them once pushed eight `spec=fx` rows onto the live fleet board.
- **`run-loop.sh` refuses `main`** and refuses an unknown strategy before any phase; `--list`
  is handled as `$1` before anything else. A new flag has to be parsed without disturbing
  either, and on **bash 3.2** — no arrays, no `declare -A`, no `${var,,}`.
- **`bound`, never `timeout`** (`scripts/bound.sh`). macOS ships no `timeout`, and reaching for
  it is what made `gate-selftest.sh` exit 127 and report every mutant as WRONG-REASON.
- **The panel is delimited, and its ordering is a readable literal.** Two shapes are pinned
  here because they are what makes T3's gate able to fail honestly, not because the code needs
  them otherwise:
  - The panel's JS is bracketed by the comment markers `MUTANT PANEL BEGIN` and
    `MUTANT PANEL END`. Every T3 assertion is scoped to that region; without a delimiter, a
    grep of `board.html` for `SURVIVOR` or `textContent` matches prose and unrelated code
    (Trap A), and the gate becomes a coin that lands heads.
  - Row order comes from a literal rank map, `const VRANK = {SURVIVOR:0, 'WRONG-REASON':1,
    HUNG:2, KILLED:3}`, and the rows are `.sort()`ed through it. "Survivors first" stated as a
    comparator expression is unverifiable by a static gate; stated as a rank map, the gate
    extracts both numbers and compares them, so a map that ranks `KILLED:0` fails.
- **Port `8877` and `COORD_PORT` already exist** (`coordinator.py`, `docker/compose.yaml`,
  `docs/coordinator.md`, the pi-cluster ingress backend). Do not invent a second name for it.

## 7. Norms · [N — Norms]

- **Naming.** The one new file is `scripts/jig-board.sh` — the ratified product identity, and a
  new file carries no compat burden (issue #81's shims are for the `ralph-*` surface that
  pi-cluster and notes-from-hearing address by name; nothing addresses this). Its env var is
  the existing `COORD_PORT`. New shell function follows the file's convention:
  `ralph_log_selftest_push`, beside `ralph_log_artifact_push`.
- **Observability.** The push is silent on success and silent on failure, like every other push
  in `ralph-log.sh`. `jig-board.sh` prints the URL and nothing else on success; it is the one
  new surface a human reads, so its `status` output names the port and the pidfile.
- **Error handling.** Every push path is fire-and-forget: `|| true`, `--connect-timeout 2
  --max-time 3`, no output. `jig-board.sh` is fail-loud instead — an operator asking for a
  board and not getting one must be told, with the log path.
- **House style.** The board's existing visual language is already established: `.pill.ok` /
  `.pill.no` / `.pill.run`, `.dot`, `--ok`/`--bad`/`--wait` tokens, `.grid` stat tiles, the
  `.mono` class for identifiers. The mutant panel uses those, and adds no new palette. A
  SURVIVOR is `--bad`; a KILLED is `--ok`; WRONG-REASON and HUNG are `--wait`. Do not invent a
  fourth colour for the fourth verdict.
- **Portability.** Authored on macOS, runs in Linux containers. bash 3.2 floor, `pwd -P` before
  any path prefix arithmetic, GNU-before-BSD in any `stat` fallback.

## 8. Safeguards · [S — Safeguards]

1. **An unset `HARNESS_REPORT_URL` changes nothing.** No push, no output, no new file, no
   change in exit code or timing. → ac2.
2. **A failed push never fails the run.** Unreachable, refused, 500 or hung, the loop exits
   with the code it would have had. → ac5.
3. **A read never mutates the board.** No `_touch`, no eviction, no new run row, on any GET.
   → ac8.
4. **Worker bytes never become markup.** Served `text/plain`; rendered with `textContent`. A
   `why` field containing `<img onerror=...>` renders as characters. → ac10, ac14.
5. **The artifact is bounded.** Compaction plus the existing `HARNESS_ARTIFACT_MAX_BYTES` cap;
   a clipped diff says so in the value. → ac4.
6. **No flag, no service.** `run-loop.sh` without `--board` starts no process and exports no
   variable. → ac19.
7. **The dispatch API is not touched.** It stays cluster-internal with no ingress.

## 9. Task breakdown · [O — Operations]

- **T1 — the push.** `ralph_log_selftest_push` in `scripts/ralph-log.sh`, called from the
  first-green selftest block in `scripts/ralph-build.sh`.
- **T2 — the read.** `GET /api/artifact` in `scripts/dispatch/coordinator.py`.
- **T3 — the panel.** The mutant panel and artifact viewer in `scripts/dispatch/board.html`.
  Depends on T2 for its data.
- **T4 — the service.** `scripts/jig-board.sh`, `run-loop.sh --board`, `docs/coordinator.md`,
  `.gitignore`.

T1 and T2 are independent of each other. T3 follows T2. T4 is independent of all three.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

### T1 — selftest artifact

- **ac1** When a task's first-green selftest completes and `HARNESS_REPORT_URL` is set, the
  loop shall POST the compacted rows for that run to
  `/runs/<key>/attempts/<task>/<attempt>/artifacts/selftest`.
- **ac2** If `HARNESS_REPORT_URL` is unset, then the loop shall push nothing and print nothing
  about the push.
- **ac3** The compacted artifact shall carry one line per selftest row of the current `run_id`,
  each keeping `verdict`, `mutant`, `assertion`, `target` and `why`, and shall keep that run's
  `run_complete` summary line.
- **ac4** The compacted artifact shall carry no `diff` on a `KILLED` row, and on any other
  verdict shall carry a `diff` clipped to `SELFTEST_ARTIFACT_DIFF_LINES` (default 40) lines
  ending `--- diff clipped at N lines ---` when it was clipped.
- **ac5** If the coordinator is unreachable or errors, then the run shall continue and exit with
  the code it would have had.

### T2 — artifact read

- **ac6** When `GET /api/artifact?key=K&name=N` names a stored artifact, the coordinator shall
  answer `200` with that artifact's bytes verbatim.
- **ac7** If `key` or `name` is missing, then it shall answer `400` naming the missing parameter.
- **ac8** If the run or the artifact is unknown, then it shall answer `404` and the set of runs
  the board reports shall be unchanged.
- **ac9** An artifact read shall succeed with no `Authorization` header even when
  `HARNESS_REPORT_TOKEN` is set, matching `/api/runs`.
- **ac10** An artifact response shall carry `Content-Type: text/plain; charset=utf-8`.

### T3 — board mutant panel

- **ac11** Where a selected attempt has a `selftest` artifact, the board shall render a mutant
  panel showing the killed / survivor / wrong-reason / hung counts.
- **ac12** The panel shall order rows survivors first.
- **ac13** Each row shall show its assertion id, its target and its WHY, and a row carrying a
  diff shall render that diff.
- **ac14** The panel shall insert every worker-supplied field with `textContent`, never
  `innerHTML`.
- **ac15** If a line of the artifact does not parse as JSON, then the panel shall skip it and
  still render every line that does.

### T4 — local board service

- **ac16** When `scripts/jig-board.sh start` is run, it shall start the coordinator in the
  background, write `.jig/board.pid`, and print the board URL.
- **ac17** `status` shall report the running state and the URL, `stop` shall stop a running
  board, and both shall be idempotent — a second `start` shall not start a second process and a
  `stop` with nothing running shall exit 0.
- **ac18** When `run-loop.sh --board <strategy> <spec>` is run, it shall ensure the board is up,
  export `HARNESS_REPORT_URL` for the phases, and print the URL before the first phase.
- **ac19** If `--board` is absent, then `run-loop.sh` shall start no board process and shall
  leave `HARNESS_REPORT_URL` exactly as it found it.
- **ac20** `docs/coordinator.md` shall document `jig-board.sh` and the `--board` flag.

## 11. Verification (the harness) — SHIP A `verify.sh`

Per-task gates under `tasks/T<NN>-<slug>/verify.sh`, each with its `mutants/` corpus; the
spec-level `verify.sh` runs them in order and owns no checks of its own.

**How each task's gate avoids the traps** (`specs/TEMPLATE.md` §11):

- **T1** drives the *real* `ralph-build.sh` on a git fixture — the shape
  `20260831u/T01-preflight-selftest/verify.sh` already uses — against a stub HTTP sink written
  in python3 that records what it received. ac2 is an **absence** assertion, so it ships its
  positive control: the same fixture with `HARNESS_REPORT_URL` set must produce a request, or
  the "no request" result proves nothing (Trap B).
- **T2** starts the real `coordinator.py` on an ephemeral port, POSTs an artifact, and reads it
  back. ac8's "board unchanged" is measured by comparing `/api/runs` before and after the
  404 — not by grepping the source for `RUNS.get` (Trap A: the source already contains it).
- **T3** is a static gate over `board.html`. Every check is scoped to the panel's own region of
  the file, and comments are stripped first, because the words `selftest`, `SURVIVOR` and
  `textContent` all appear in prose in this repo (Trap A). ac14 asserts the **absence** of
  `innerHTML` within the panel region and ships its positive control: the probe must find the
  `innerHTML` that legitimately exists elsewhere in the file, or it is not looking anywhere.
- **T4** runs `jig-board.sh` for real on an ephemeral port and drives `run-loop.sh` in a git
  fixture with a stub strategy. ac19 is an absence assertion with a positive control: the same
  fixture *with* `--board` must show the export, or "not exported" is free.

## 11b. Loop execution (handing to a local model)

Four tasks, one per iteration, fresh context each, via `scripts/run-loop.sh build-converge
specs/20260831s-live-board-evidence` from a worktree on a throwaway branch. T3 is the one task
whose deliverable is visual; its gate is static and cannot see "this looks dumb", so the
rendered panel needs a human eye before the PR merges — stated here rather than pretended away.

## 12. Open questions

- **OQ1** — RESOLVED (owner, 2026-08-31): the board shows **this run's rows only**. The
  repo-wide ledger stays `mutant-ledger.py`'s artifact.
- **OQ2** — RESOLVED (owner, 2026-08-31): the local board is **opt-in**. `--board` and
  `jig-board.sh`; the default run path is untouched.
- **OQ3** — Open, deferred: the deployed coordinator in pi-cluster picks the read route up as an
  image bump, and its board is reachable on the LAN with reads unauthenticated. Serving artifact
  *bodies* there widens what an unauthenticated LAN reader can see from "run metadata" to
  "prompts, patches and transcripts". That is a real change in exposure, it is the owner's call,
  and it is not this spec's to make — the manifests are out of scope (§5) and the local board is
  loopback. Flagged for the image-bump PR in pi-cluster, not resolved here.
