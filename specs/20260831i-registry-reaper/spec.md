# Spec: the registry reaper — a run recorded as running that is not running

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #22
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** python3, curl
- **MCP:** none
- **Permissions:** write:scripts/dispatch/dispatcher.py, write:scripts/dispatch/api.py

---

## 1. Why · [R — Requirements]

Issue #22: a loop killed mid-attempt (OOM, eviction, a dead wrapper shell) leaves its
registry record `launched` forever, and nothing distinguishes it from a run still going.
ADR-001 D6 already names the rule — *a run that exits still tagged started crashed
before classifying itself, and is therefore failed* — and D8 makes the Job object the
liveness source of truth. No mechanism applies the rule today; the dispatcher would read
`running` forever. The issue weighed three candidates and chose the reaper, because it
reads liveness from the Job instead of inventing a second signal.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. `reap_runs(registry_path, namespace)` reconciles every record whose effective status
   is `launched` against its Job (`HARNESS_KUBECTL` seam): Job absent → superseding
   record `failed` (`reaped: job absent`); Job failed → `failed`; Job succeeded →
   `succeeded`; Job active or status indeterminate → untouched.
2. Superseding records are APPENDED — the registry stays append-only — and reads honor
   last-wins: `get_run` returns the newest record for an event_id.
3. Records already settled (`failed`, `succeeded`) are never re-queried.
4. A broken kubectl marks nothing: no signal is not a verdict.
5. `POST /reap` on api.py runs a pass and returns `{checked, reaped}`; authed like every
   other write.

## 3. Entities · [E — Entities]

Registry: append-only JSONL, one record per line, `event_id` the identity, `status` in
`launched|failed|succeeded`; a superseding record repeats the identity fields and adds
`reason` (`reaped: …`). The Job: `kubectl get job <job_name> -n <ns> -o json`,
`.status.active/succeeded/failed`.

## 4. Approach · [A — Approach]

Same seams the code already has: `HARNESS_KUBECTL` (the DELETE route's pattern),
`record_run` for the append, `read_runs` folded last-wins inside the reaper. `get_run`
changes from first-match to last-match — a superseded record returned to a caller is a
lie. The dispatch-core gate's ac5 scenario has no duplicates, so its pins are
undisturbed.

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/dispatch/dispatcher.py` (`reap_runs`, `get_run` last-wins), `scripts/dispatch/api.py`
(`POST /reap`).

### Out of scope
Scheduling the reaper (a cluster CronJob or the operator's curl — not this repo's call);
the coordinator's board (worker-pushed, a different store); `read_runs`'s list shape.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- The registry file may be unwritable/missing; every registry helper tolerates that
  without raising — the reaper must too (its callers include an HTTP route).
- `subprocess.run(..., capture_output=True, timeout=30)` is the DELETE route's exact
  kubectl shape; keep it.
- An indeterminate Job status (just created, no counters yet) is left for the next
  pass, not guessed at.

## 7. Norms · [N — Norms]

Docstrings in the module's existing voice; the reaper's docstring cites D6/D8 and the
no-signal-is-not-a-verdict rule.

## 8. Safeguards · [S — Safeguards]

- Append-only: the reaper must never rewrite or truncate the registry (ac-checked by
  asserting prior lines survive byte-identical).
- Fail-safe: kubectl errors/timeouts leave the registry untouched (ac5).

## 9. Task breakdown · [O — Operations]

- T1: `reap_runs` + last-wins `get_run` in dispatcher.py; `POST /reap` in api.py.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- If a `launched` record's Job is absent, a reap shall append a superseding `failed`
  record with reason `reaped: job absent`, and `get_run` shall return it. (ac1)
- While a Job is active, a reap shall leave its record untouched. (ac2)
- When a Job reports failed / succeeded, a reap shall append the matching terminal
  record. (ac3)
- Settled records shall not be re-queried (the kubectl call log shows only unsettled
  job names). (ac4)
- If kubectl fails, the reap shall append nothing. (ac5)
- `POST /reap` shall 401 without the token and, with it, run a pass, return
  `{checked, reaped}`, and the registry shall show the reaped record. (ac6)
- Prior registry lines shall survive a reap byte-identical (append-only). (ac7)
- Both files shall compile (`py_compile`). (ac8)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. A fake kubectl script answers by job
name (absent/active/failed/succeeded) and logs every invocation; the api test boots the
real api.py on an ephemeral port. The dispatch-core gate is the regression control.

## 12. Open questions

None. (Scheduling deliberately out of scope — the mechanism lands here, the cadence is
a deployment decision.)

## 14. Tuning log

- (none yet)
