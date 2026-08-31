# Spec: the dispatcher refuses a strategy nobody configured — no silent substitution

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #79
- **Owner:** Matt (decision 2026-08-31; spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** python3, curl
- **MCP:** none
- **Permissions:** write:scripts/dispatch/dispatcher.py, write:scripts/dispatch/api.py, write:docs/executors.md

---

## 1. Why · [R — Requirements]

Issue #79: `worker_image()` falls back to the deployment's default image, so a request
naming a strategy nobody configured produces a Job that LOOKS entirely correct — right
`STRATEGY` env, right per-strategy secret — running an image that cannot execute it.
It is caught later, at real cost: pod scheduled, credential written to disk, repo
cloned, then `run-loop.sh`'s tool preflight exits 3. Matt's framing is the requirement:
**we want explicit usage — firing a random strategy is as bad as looping with no goal.**

## 2. Decision (OQ1 resolved) · [A — Approach]

**Option B — the allowlist.** `HARNESS_STRATEGIES` (whitespace-separated) names what
the deployment permits; anything unlisted is refused before anything is rendered,
launched, or recorded. Unset means no enforcement — today's behavior, which is what
keeps the issue's four incidental gate fixtures untouched (its own decision rule:
"decide it on this number, not on taste"). Permission and image-binding stay separate
concepts: one image legitimately serves several strategies, and Option A would have
conflated "has an image" with "may run". A deployment that wants enforcement sets the
variable; the k8s manifests should always set it.

- **OQ2:** `parse_intent()`'s `build-converge` default survives — the allowlist still
  gates it, so an enforcing deployment must list `build-converge` for the default path
  to dispatch. Explicit usage is preserved where it matters: in the deployment.
- **OQ3:** a refusal reaches the CALLER (result dict + HTTP status); the coordinator
  board is worker-pushed and a refusal has no worker. Out of scope here.

## 3. Outcomes (Definition of Done) · [O — Outcomes]

1. With `HARNESS_STRATEGIES` set, a dispatch naming an unlisted strategy launches
   nothing, renders nothing, and records nothing (neither ledger nor registry).
2. The refusal is distinguishable from a duplicate in the result dict (`refused` key).
3. A refusal must not poison the ledger: fixing the config and retrying the SAME
   event id launches.
4. The API answers a refused request with 422 and a body naming the strategy and
   `HARNESS_STRATEGIES`; a duplicate still answers 200, a launch 202.
5. With the variable unset, or with the strategy listed, behavior is byte-identical
   to today (the rendered Job dict compares equal).
6. `docs/executors.md` states that an enforcing deployment lists its strategies.

## 6. Facts the implementer must know · [S — Structure]

- The refusal belongs in `dispatch()` at the point strategy is resolved — before
  `render_job`, before `launch`, and above all BEFORE `record_seen()` (a refusal that
  wrote the ledger would dedupe the operator's post-fix retry into silence — the
  failure this spec exists to remove, made permanent).
- `worker_image`/`worker_secret` stay untouched — they are maps, not policy; the
  allowlist is the policy seam, and it lives where the one strategy value is read.
- api.py's `status_code = 202 if launched else 200` keeps its duplicate meaning; the
  refusal branches BEFORE it.

## 8. Safeguards · [S — Safeguards]

Gate pins the retry-after-configure path (AC-3) — the only check that catches a
refusal which poisoned its own ledger — and dict-compares the configured path's Job
against the unset path's (no silent render drift).

## 9. Task breakdown · [O — Operations]

- T1: `allowed_strategies()` + refusal in `dispatch()`; 422 branch in api.py;
  docs/executors.md paragraph.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- While `HARNESS_STRATEGIES` excludes a strategy, a dispatch naming it shall not
  invoke the runner. (ac1)
- The refusal's result shall carry `refused` and `launched: False` — distinguishable
  from a duplicate, which carries neither reason nor a launch. (ac2)
- The refused event id shall be absent from the ledger, such that the identical
  retry after configuration launches. (ac3)
- `POST /runs` naming an unlisted strategy shall answer 422 with a body naming the
  strategy and `HARNESS_STRATEGIES`; a configured launch shall still answer 202. (ac4)
- The Job rendered with the strategy listed shall equal the Job rendered with the
  variable unset (dict equality). (ac5)
- With `HARNESS_STRATEGIES` unset, an arbitrary strategy shall dispatch as today —
  the legacy no-enforcement control. (ac6)
- `docs/executors.md` shall mention `HARNESS_STRATEGIES`. (ac7)
- Both files shall compile (`py_compile`). (ac8)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. Behavioral through the module's
API with `dispatcher.launch` monkeypatched to a recorder (the 20260830a T01 shape);
the API check boots the real api.py with a no-op fake kubectl. The dispatch-core
gate is the regression control.

## 12. Open questions

None — OQ1/OQ2/OQ3 resolved in §2.

## 14. Tuning log

- (none yet)
