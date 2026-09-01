# Spec: 20260831t-dispatch-job-argv

- **Status:** In progress v1.2
- **Owner:** mtgibbs
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Touches:** `scripts/dispatch/dispatcher.py`, `scripts/dispatch/README.md`, `docker/dispatcher.VERSION`
- **Tools:** git, bash, python3
- **MCP:** none

## 1. Why · [R — Requirements]

Issue #117: a dispatched Job can never run. `render_job()` passes the intent as
`REPO`/`SPEC`/`STRATEGY` **environment variables**, but the worker image's entry point takes
it as **positional arguments** — the rendered Job sets no `args` and no `command`, so
`entrypoint.sh`'s `exec run-task.sh "$@"` expands to nothing and every dispatched run dies
in seconds on `run-task: <spec-dir> is required`, before it clones anything. Found live
2026-08-31 while activating the dispatcher in pi-cluster's `harness-fleet` namespace
(pi-cluster #219): `POST /runs` reported `launched`, the Job scheduled, and the worker
exited 64 in 36s.

The defect survived review because the `repo` row reads as correct from either side alone —
an env path *does* exist in `run-task.sh`, it is just spelled `HARNESS_REPO_NAME`, not
`REPO`. The fix is issue #117's option 1: render the intent as argv, keeping `run-task.sh`
as THE single entry point with ONE calling convention for a Job, a tmux send-keys, and a
human at a shell — which that file's own header argues for. Option 2 (teach `run-task.sh`
the env names) was rejected there: it needs a worker-image rebuild *and* gives the entry
point a second calling convention, i.e. it institutionalises the trap that caused this.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. The rendered container carries the intent as
   `args: [<spec>, --repo, <repo>, --strategy, <strategy>]` — exactly the argv
   `run-task.sh` documents.
2. The dead second convention is GONE: no `REPO`/`SPEC`/`STRATEGY` env on the container.
   Nothing in the worker ever read them, and keeping them would preserve the
   reads-as-correct-from-either-side surface that let #117 through.
3. The rendered container has NO `command` key: the image's ENTRYPOINT
   (`tini → entrypoint.sh`) writes the clone credential before the loop starts, and a
   `command` would silently bypass it.
4. The render→parse seam is gated: the gate feeds the rendered argv to the REAL
   `run-task.sh` and asserts it gets PAST the parser (fails later, on a missing
   `HARNESS_DIR`, exit 66 — not exit 64).
5. The historical gates that pinned the env shape — `20260828f` ac4 and `20260830a` T01
   (ac3 completeness probe, `strategy_of`, ac6 exact shape) — are left **byte-for-byte
   untouched**. They are the frozen record of what their specs proved when they shipped,
   not a regression suite; run against today's renderer they fail, and that failure IS
   the record that the shape moved here. The argv era's pin is this spec's own gate.

## 3. Entities · [E — Entities]

The intent dict (`verb`, `repo`, `spec`, `strategy`) from `parse_intent()`. The container
`args` list — Kubernetes appends it to the image ENTRYPOINT, which is the one place a Job
may inject the intent without displacing `entrypoint.sh`. `run-task.sh`'s calling
convention: `<spec-dir>` positional, `--repo`/`--strategy` flags in any position.

## 4. Approach · [A — Approach]

Smallest change at the diagnosed site: the `env` block in `render_job()` becomes an `args`
list; no other key of the rendered Job moves. Dispatcher-image change only — the worker
image, `entrypoint.sh`, and `run-task.sh` are untouched. Rejected: keeping the env vars
alongside args "for observability" (argv is equally visible in the pod spec, and two
conventions is the defect); rejected: `command` instead of `args` (bypasses the
credential-writing entry point); rejected — on Matt's review of v1.0 — amending the two
historical gates that pinned the env shape: an old spec's gate is the evidence of what
that spec proved when it shipped, and rewriting it to track later behavior treats the
evidence corpus as a regression suite and corrupts the record. The old pins stay as
written; the new shape is pinned only here.

## 5. Scope · [S — Structure: boundary]

### In scope
The files under **Touches**, this spec dir.

### Out of scope
`scripts/entrypoint.sh` and `scripts/run-task.sh` (their contract is the fixed point this
spec renders TO — T1 ac5 pins the pass-through untouched), `scripts/dispatch/api.py`
(hands the intent to the same `dispatch()`), issue #116 (the kubectl version pin is a
separate image-build concern), publishing the fixed dispatcher image and bumping
pi-cluster's tag (CI + a pi-cluster PR after merge).

**Amended on review (v1.2):** `docker/dispatcher.VERSION` moved IN scope, 0.1.0 -> 0.1.1.
v1.1 left it out on the reasoning that publishing is CI's job. That was wrong in a way
that would have swallowed this whole fix: `build-images.yml` pushes exactly one tag,
`<image>:${version}`, so an unbumped VERSION means CI overwrites `harness-dispatcher:0.1.0`
in place — and pi-cluster pins that tag with no `imagePullPolicy`, which for a non-`latest`
tag defaults to `IfNotPresent`. Every node that already pulled 0.1.0 would keep the broken
image, `harness-fleet` runs no image automation to notice the digest moved, and the
after-merge step "bump pi-cluster's tag" would have had nothing to bump to. Publishing
stays CI's; naming the version a fix ships under belongs to the spec that makes the fix.

## 6. Prior decisions / facts the implementer must know · [S — Structure]

- `entrypoint.sh` ends `exec "$(dirname "$0")/run-task.sh" "$@"` — a Job's `args` arrive
  as that `"$@"` through the image's `ENTRYPOINT ["/usr/bin/tini", "--", ".../entrypoint.sh"]`.
- `run-task.sh` parses flags in ANY position, `<spec-dir>` positional; empty argv exits 64
  (`<spec-dir> is required`); a present argv with an unreachable `HARNESS_DIR` exits 66 —
  which is what makes a network-free seam test possible.
- `parse_intent("@harness fix myrepo specs/thing")` yields strategy `build-converge` (the
  4-field default) — the amended `20260828f` ac4 asserts that exact argv.
- `20260828f` ac4 and `20260830a` T01 pinned the env-era Job shape. Past specs' gates are
  HISTORY — the record of what was proved at ship time — never a regression suite to keep
  green. This spec moves the shape and does NOT touch them; anyone re-running them today
  reads their failure as "the shape moved after 2026-08-30", and this spec is where.

## 7. Norms · [N — Norms]

House gate style: behavioural through the module's own API, `launch` monkeypatched,
asserted on the rendered DICT never on serialised YAML (`20260830a` T01's header says why).
Past specs' gates are not edited — history is append-only; a superseding spec pins the
new truth in its own gate.

## 8. Safeguards · [S — Safeguards]

- The seam test runs the REAL `run-task.sh` with `HARNESS_DIR` pointed at a nonexistent
  path — it must fail AFTER the parser (66), so the gate never clones, never fetches,
  never needs the network.
- A control asserts empty argv still exits 64 — proving the parser really rejects what the
  old renderer produced, so the seam assertion cannot rot into a tautology.

## 9. Task breakdown · [O — Operations]

- **T1 — the intent rides argv** (`tasks/T01-render-intent-argv`): `render_job()` renders
  `args` in `run-task.sh`'s convention; the env convention is gone; no `command`; the
  rendered argv passes the real parser; the entrypoint pass-through is pinned.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- **T1** — WHEN `dispatch()` launches an intent THEN the rendered container SHALL carry
  `args` of exactly `[<spec>, --repo, <repo>, --strategy, <strategy>]` (ac1); the
  container SHALL carry no env named `REPO`, `SPEC` or `STRATEGY` and no `command` key
  (ac2); WHEN the rendered argv is handed to the real `run-task.sh` with an unreachable
  `HARNESS_DIR` THEN it SHALL exit 66 having passed the parser, never 64 (ac3); WHEN
  `run-task.sh` runs with empty argv THEN it SHALL still exit 64 (ac4 — the control);
  `entrypoint.sh` SHALL still exec `run-task.sh "$@"` (ac5).

## 11. Verification — the gates

Single task, one gate under `tasks/`, driving the real `dispatcher.py` module and the real
`run-task.sh` — no network, no simulators. Red: `evidence/red-before-green.txt` — the T01
gate against the pre-fix renderer (ac1–ac3 fail; the ac4/ac5 controls pass, proving the
parser and the entrypoint bridge were never the broken half). Green:
`evidence/green-after.txt` — the spec-level convergence run after the one-block fix, with
`20260828g`/`20260828h` (call-graph pins that don't assert the shape) still passing.

## 12. Open questions

None. Whether the dispatcher should also PROBE the seam at startup (render a canary Job
and dry-parse it) was considered and dropped: the gate is the cheaper, earlier home for
that assertion.

## 14. Tuning log

- **v1.1 (2026-08-31)** — Corrected on Matt's review: v1.0 amended the two historical
  gates (`20260828f` ac4, `20260830a` T01) to pin the argv shape — rewriting history
  because it read them as regression tests. Reverted byte-for-byte. Past specs' gates are
  the frozen evidence of their own era; a superseding spec carries the new pin itself,
  and an old gate failing against newer code is the record working, not a defect.
- **v1.0 (2026-08-31)** — Authored from issue #117 the day the farm found it. Option 1
  chosen per the issue's own analysis; env removed rather than kept-beside-args so the
  rendered object has exactly one story about how the intent travels.
