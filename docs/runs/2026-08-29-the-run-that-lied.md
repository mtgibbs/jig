# The runs that lied — a session spent on what a harness says about itself

**Date:** 2026-08-29 · **Executor:** qwen via `oc`/LiteLLM · **Strategy:** `build-converge`
**Host:** `coding-harness-claude` (container; `e061d942c900` before a mid-session restart, `71a0dd75cbd2` after)
**Landed:** `20260829b-resume-bound` (#50) · `20260828o-evidence-egress` (#52)

The session set out to finish one documentation task. It finished it eleven hours later, having
spent almost all of that on a single theme that only became visible once the coordinator was
serving a board: **in six distinct ways, a run's recorded outcome disagreed with what actually
happened.** A false red, a false green, a frozen status, invented rows, a masked verdict, and an
instrument that deleted itself.

None of these are exotic. Every one of them was reachable on an ordinary path, and four of them
had already fired before anyone noticed, because the thing that reports on a run had no way to be
contradicted.

Findings are ordered by what they cost, not by where they were found.

---

## 1. Resume could not evaluate the gates worth skipping (#47, fixed in #50)

`_task_satisfied` bounded each task's gate at a hardcoded `timeout 60`. `20260828o`'s T01 gate
spawns real loops and takes about five minutes. The answer never arrived, the predicate failed
closed, and the task ran.

**The bound was inverted against the cost it guarded.** A cheap gate belongs to a task that would
have converged anyway; resume earns its keep on expensive ones, and that is exactly the set it
could not evaluate. Worse, the same gate runs *unbounded* in `run_gates` a few lines away — one
gate, two bounds, the strict one on the cheaper question.

Observed: re-running `20260828o` with T1–T3 committed and green went to T1 attempt 2, asking the
executor to reproduce `71ebb13` and `e90fef1`. The cost compounds, because every attempt at a
needlessly re-run task drags the cumulative gate behind it.

It was also silent. Both refusal branches returned `1` identically, so a timeout and a failing
gate were indistinguishable and neither was announced — the only symptom being a task running that
should not have. That contradicted the rule `20260828l-run-control` set for the skip path itself:
*announcing is not optional*. The same argument applies to declining to skip, which is the case
that costs an executor invocation.

## 2. The fix introduced a false green, and the false green locked the loop out of fixing it

The replacement predicate dropped main's `|| { return 1 }` guard and returned early only on 124.
Every other non-zero exit fell through to `grep -qE 'PASS'` — and **a failing gate prints a PASS
line for every assertion that did hold**. A red gate therefore read as satisfied and the task was
skipped.

This was flagged as *latent* in #47 and not encoded as an assertion, so it shipped. Naming a state
in prose is not naming it in a check.

Then it defended itself. Re-running the spec to fix the wording, the loop consulted the predicate,
which read its own red gate as green and **skipped the task that fixes it** — never invoking the
executor at all. Any spec whose target is the thing that decides "is this done?" can be locked out
by the very defect it repairs. `RALPH_FORCE_ALL` is the escape hatch, which is a good argument for
the direction in #47 of reading a commit-pinned record instead of re-running a gate.

Not skipping costs time. This costs correctness, in silence.

## 3. A spec targeting `ralph-build.sh` corrupts its own run (#48)

Bash reads a script by byte offset, not into memory. The executor's target *was* `ralph-build.sh`,
so it rewrote the file bash was executing. A net +10 lines above the read offset put the resume
point mid-comment, immediately before the word `last` in *"reusing the last / attempt's number"*,
and bash ran it:

    ralph-build.sh: line 432: last: command not found
    run-loop: phase 'build' exited 2 — stopping (fail-closed)

Line 432 is a comment. The work had already committed and passed its gate. **The run reported
failure after succeeding** — and the fragment executed is arbitrary; here it was a harmless missing
binary, but a comment fragment can parse into something that runs.

## 4. A run where every task is skipped crashes before recording anything (#49)

`attempt` is assigned only by the `for attempt in …` loop inside the task loop. The skip path
`continue`s before entering it. The final-strict-gate STOP path sits *outside* the task loop and
dereferences `$attempt` under `set -u`. Skip every task, fail the convergence gate, and the loop
dies — after capturing the failing assertions, before `hb_write stopped false`. The status file
freezes at `running`, which is `#22` reached by a new road.

This is on the path resume was built to enable: re-run a spec whose tasks are all satisfied,
against a convergence gate that does not pass.

## 5. Gates inherited an environment nobody declared — three times

Each of these changed what a gate measured without changing what it said. Spec'd as
`20260829c-hermetic-gate`.

- **`/tmp` is a `noexec` tmpfs** (docker mounts tmpfs `noexec`; the compose file asks for it
  deliberately). `gate_tmpdir` calls `mktemp -d`, gets a directory it cannot execute from, detects
  it with a probe it already builds — and then gives up. Every gate in the repo is one container
  setting away from unrunnable, and the operator must know a variable that appears in no gate's
  text. The loud failure is the lucky case: a `chmod +x` mock on a noexec mount fails with
  *Permission denied*, quickly and non-zero, which **satisfies** an assertion phrased as "exited
  non-zero" or "finished under 30s".
- **`HARNESS_REPORT_URL` leaked into fixtures.** `T01-push-artifacts` ac1 reads *"with nothing
  configured the run is line-for-line the run it is today"*. Its fixture never unset the variable,
  which is now set in every harness container — so the "unconfigured" run used the **production
  coordinator**. The assertion compared two configured runs, matched on stdout because pushes are
  silent, and passed for a reason nobody chose. The fixtures also put `spec=fx` rows on the live
  board, sharing the eviction path in #46.
- **`RALPH_FORCE_ALL=1` leaked in from the launching shell**, disabling skipping inside every
  fixture. Four of six assertions could not pass whatever the executor wrote, and one passed for
  the wrong reason because "the task runs" is what it asserts. Three attempts were burned. **In the
  transcript this is indistinguishable from a model that cannot follow instructions** — the same
  cost shape as the `.env` filename guard, and the reason a fleet worker would report it as a bad
  model and nothing else.

## 6. An instrument inside the thing being measured is not an instrument (#21)

The fixture's stub executor logged invocations to `execlog.txt` inside the fixture repo. The loop
runs `git clean -fd` between attempts. For a fixture whose task never converges, every attempt's
record was deleted, so *"invoked three times"* and *"never invoked"* were the same observation. It
moved to `$T`, outside anything the loop touches.

## 7. A later task broke an earlier task's gate, and the timeout hid it

T3 added an **unguarded** call to `ralph_log_artifact_push` in `ralph-build.sh`, while every other
cross-file call there is guarded (`command -v hb_write`). T01 ac1 deliberately runs that script
against *main's* `ralph-log.sh` to prove the unconfigured path is unchanged — so the call to a
branch-only function printed `command not found` into the very output being compared.

The gate was 8/8 on 08-28, before T3 existed. Between T3 landing and the end of the session, the
only thing that consulted it was the resume predicate — which timed out at 60s and returned
silently. Cumulative per-task gating exists precisely to catch a later task breaking an earlier
one. **The mechanism worked; it could not be heard over the bound.** #50 did not cause that
failure, it revealed it.

## 8. A 404 still creates a run row (#46)

An authed POST to an unknown coordinator sub-route calls `_touch(key)` before validating the route,
creating an empty row that renders on the board and then returning 404. Found by probing the auth
boundary with a deliberately invalid path, chosen *because* it should have been inert. It also
shares the oldest-first eviction against `COORD_MAX_RUNS`, so a mistyped path can evict a real run.

---

## What the loop produced, and what it did not

Stated because a green gate on a branch reads as the loop having produced all of it.

**The loop, unaided:** `20260828o` T1, T2 and T4; `20260829b`'s bound, its malformed-value
fallback, and threading the task name through `_task_satisfied` so a refusal could name its task —
that last one an inference from the task text rather than an instruction in it. T3 was also the
loop's work, produced on attempt 1 and salvaged by hand after the container restart killed the run
before it could verify or commit; it was re-gated (4/4) rather than trusted.

**Written by hand:** six lines in `_task_satisfied` — the exit-status verdict and the two refusal
messages — after ten attempts across four runs reached 5/7 and stopped. Plus the guard in item 7
and the fixture fixes in items 5 and 6.

**Where the failures actually came from:** of the four runs on `20260829b`, three failed on inputs
rather than on the executor — a non-hermetic gate, a sentence with two readings (*"defaulting to a
value no smaller than…"*, which the executor reasonably applied as a floor on every value), and an
unencoded hazard. The executor produced correct work on three of the four attempts where the
inputs let it.

## What made this findable

The coordinator went live the same day, and the fleet board is what surfaced items 1, 2, 5 and 8.
Two of them were found by a human looking at a row and asking a question the evidence tree could
not have prompted: *"T1 says attempt 2/3 but reports no attempt records"* — which turned out to be
a branch eleven commits behind main, missing the attempt-record channel and the cancel support, so
the Stop button on that run would have done nothing either.

A board is not a nicety for a system whose failure mode is misreporting itself. It is the only
thing in the loop that can be contradicted by a person.
