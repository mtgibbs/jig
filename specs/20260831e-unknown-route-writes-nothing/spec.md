# Spec: a POST that will 404 writes nothing to the board

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #46
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** python3, curl
- **MCP:** none
- **Permissions:** write:scripts/dispatch/coordinator.py

---

## 1. Why · [R — Requirements]

Issue #46: `do_POST` calls `_touch(key)` before validating the sub-route, so any authed
POST to `/runs/<host>/<agent>/<anything>` creates an empty run row — `phase: "?"`, every
field blank — and only then 404s. Worse than the ghost row: `_touch` is where
oldest-first eviction against `COORD_MAX_RUNS` happens, so a mistyped or forged path can
evict a REAL run's record to make room for a row that was never a run. The board's job is
to be the thing you trust about what happened; a route that 404s must not change what it
says.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. An authed POST to an unknown sub-route returns 404 and leaves `/api/runs`
   byte-identical to what it was before the call.
2. Every known route (`status`, `attempts`, `attempts/<t>/<a>/artifacts/<name>`,
   `control`) behaves exactly as before.

## 3. Entities · [E — Entities]

The four known `rest` shapes after `/runs/<host>/<agent-pid>/`: `["status"]`,
`["attempts"]`, `["control"]`, and the 5-part `["attempts", <task>, <attempt>,
"artifacts", <name>]`.

## 4. Approach · [A — Approach]

Move the route check ahead of the lock: a `known` predicate over `rest` mirroring the
existing dispatch arms, 404 before `_touch` for anything else. The inner `else` 404
stays as an unreachable safety net — deleting it would couple the predicate and the
dispatch invisibly.

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/dispatch/coordinator.py`, `do_POST` only.

### Out of scope
The control-route auth relaxation (deliberate, documented in the handler); GET routes;
eviction policy itself.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- The auth boundary is deliberate and asymmetric: run-data writes need the token,
  `control` does not (the Stop button is a browser link). The fix must not disturb it.
- `_save()` is never reached on the 404 path today — the ghost row is memory-only. The
  fix removes the memory write too, not just the snapshot.

## 7. Norms · [N — Norms]

Comment states the one thing the code can't: why validation precedes `_touch`
(eviction, not just the ghost row). House density.

## 8. Safeguards · [S — Safeguards]

- The 401 path for unauthed writes must be unchanged (checked by ac3).
- Known routes must keep working (ac2 is the positive control that the ac1 probe can
  actually see a created row).

## 9. Task breakdown · [O — Operations]

- T1: add the `known`-route predicate ahead of the lock in `do_POST`; 404 unknown
  sub-routes before `_touch`.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- If an authed POST names an unknown sub-route, the coordinator shall return 404 and
  `/api/runs` shall be byte-identical before and after. (ac1)
- When an authed POST names a known route (`status`), the coordinator shall return 200
  and the run shall appear on the board — the positive control proving ac1's probe can
  detect a created row. (ac2)
- If a POST to a run-data route lacks the token, the coordinator shall return 401 and
  create no row (the auth boundary is undisturbed). (ac3)
- `coordinator.py` shall compile (`py_compile`). (ac4)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. The gate boots the REAL coordinator on
an ephemeral port with a test token and probes it with curl; the server is killed on
exit.

## 12. Open questions

None.

## 14. Tuning log

- (none yet)
