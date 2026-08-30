# Spec: a gate measures the work, not the environment it was launched from

- **Status:** Draft v0.1
- **Owner:** mtgibbs
- **Constitution:** `specs/constitution.md` (+ `/CLAUDE.md` Core Mandates)
- **Touches:** `specs/lib/assert.sh`, `specs/20260828o-evidence-egress/lib/fixtures.sh`,
  `specs/20260829a-executor-image-layer/lib/fixtures.sh`,
  `specs/20260829b-resume-bound/lib/fixtures.sh`, `docs/runs/2026-08-29-the-run-that-lied.md`
- **Tools:** git, python3, bash
- **MCP:** none
- **Permissions:** write:specs/lib/**, write:specs/2026*/lib/**, write:docs/**, exec:git, exec:python3

---

## 1. Why · [R — Requirements]

Three times on 2026-08-29 a gate's verdict was decided by ambient environment nobody declared.
Each **changed what the gate measured without changing what it said**
(`docs/runs/2026-08-29-the-run-that-lied.md` §5):

- **`HARNESS_REPORT_URL` leaked into fixtures.** `20260828o` T01's ac1 asserts *"with nothing
  configured the run is line-for-line the run it is today"*. Its fixture never unset the
  variable, which is set in every harness container — so the "unconfigured" run used the
  **production coordinator**. The assertion compared two *configured* runs, matched on stdout
  because pushes are silent, and passed for a reason nobody chose. It also wrote: one pass over
  `20260829a`'s six gates put **eight rows keyed `spec=fx` on the live fleet board**,
  indistinguishable from real runs and sharing harness#46's oldest-first eviction — so fixture
  rows can evict the record of an actual run.
- **`RALPH_FORCE_ALL=1` leaked from the launching shell**, so no fixture could skip anything.
  Four of six assertions could not pass whatever the executor wrote, and one passed for the wrong
  reason because *"the task runs"* is what it asserts. Three attempts were burned. **In the
  transcript this is indistinguishable from a model that cannot follow instructions** — which is
  how a fleet worker would report it, and why it would cost an executor swap rather than a fix.
- **`/tmp` is a `noexec` tmpfs** in the containers (the compose file asks for it deliberately).
  `gate_tmpdir` detects it with a probe it already builds and then gives up, printing a hostname.
  Every gate is one container setting from unrunnable, and the operator must know a variable that
  appears in no gate's text.

The reporting leak was patched **locally, three times**, and the three do not agree on mechanism
or on scope:

| file | mechanism | covers |
|---|---|---|
| `20260828o/lib/fixtures.sh:25` | `_fx_env()` wrapping `env -u`, per invocation | 2 of 5 |
| `20260829a/lib/fixtures.sh` | `unset`, at source time | 5 of 5 |
| `20260829b/lib/fixtures.sh` | `_fx_env()` wrapping `env -u`, per invocation | 5 of 5 |

Two helpers share a name and cover different sets. None protects a gate that does not source that
particular file. Two carry a comment deferring the general fix to a spec that has never existed,
and one of those names a task number in it.

**Every instance closed, the class open.** Three local patches and a forward reference is how a
defect becomes permanent: each closure makes the next occurrence look like a one-off.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. A gate cannot see the harness's own outbound configuration, whatever the shell that launched
   it had set — and it gets that by sourcing `assert.sh`, with no line of its own.
2. A gate cannot inherit the loop's control variables, so a fixture's skipping behaviour is the
   one the gate chose.
3. The two local copies are deleted, and the gates that had them still pass — which is what
   proves the central one covers them.
4. A workspace that cannot execute names the variable and the fix, instead of a hostname.
5. Adding a gate requires knowing none of this.

## 3. Entities · [E — Entities]

**`specs/lib/assert.sh`** — the shared vocabulary, sourced by **37 gates** (31 per-task, 6
monolithic) across seven specs. It is the only file in `specs/lib/`. It already carries `ok`,
`no`, `gate_tmpdir`, `gate_done`, and pulls `bound` in from `scripts/bound.sh`. This spec adds
one function and calls it on load.

**The quarantined set** — the variables a gate must never inherit, and why each is on the list:

| variable | why |
|---|---|
| `HARNESS_REPORT_URL` | a fixture loop posts to the real coordinator |
| `HARNESS_REPORT_TOKEN` | the credential that makes the above succeed |
| `RALPH_FORCE_ALL` | disables skipping inside every fixture |
| `RALPH_FORCE_FROM` | the same, from a task index |
| `RALPH_SATISFIED_TIMEOUT` | gates that set it per case are silently overridden |

**Unset, never a sentinel.** A sentinel URL is still a URL and something eventually POSTs to it.

**`GATE_TMPDIR`** — where a gate's workspace is made. Defaults to `mktemp -d`'s choice; set it
when the default mount cannot execute.

## 4. Approach · [A — Approach]

Put the rule in the file every gate already loads, so the right thing is the default rather than
a thing to remember — the same move `bound` made into `assert.sh` in harness#51. `assert.sh` is
sourced, so the reset runs on load and no gate calls anything.

Then **delete both local copies**. That is not tidying: while they exist, the central reset is
unproven — the two gates that most need it would pass on their own patches. Removing them makes
those gates the migration's own test.

**Two places, because one is not enough.** `assert.sh` covers the 31 per-task gates that source
it. It covers **none** of the 24 monolithic gates — `20260801a` through `20260828j` predate
`20260828i-per-task-gates` and define `ok`/`no`/`pend` inline, sourcing nothing. Several of them
drive the real loop (`20260827a` runs `run-loop.sh`; `20260828e` runs `ralph-build.sh`), so they
are exactly the gates that can post to a coordinator. Found by this spec's own T2 gate, which was
written to catch an orphan and found twenty-four.

So the reset also goes at the **invocation boundary**: `ralph-build.sh`'s `run_gates` clears the
set before it invokes any gate, whatever that gate sources. The two placements cover different
populations — `assert.sh` catches a gate run by hand or by `gate-selftest`, `run_gates` catches
every gate the loop runs — and neither is redundant. `20260829b/verify.sh` is the one monolithic
gate already covered, because it `exec`s its own task gate rather than reimplementing it.

**Rejected: adding a source line to all 24.** It is 24 edits that must not change one verdict,
and it reinstates the rule-you-must-remember for gate number 25. The boundary reset needs no
cooperation from a gate at all.

**Rejected: a `gate_env` function each gate calls.** It is the shape the repo already has, twice,
under two names, and it protects exactly the gates whose author remembered. A rule that has to be
invoked is a rule with an adoption problem, which is the problem.

**Rejected: scrubbing the whole environment.** A gate needs `PATH`, `HOME`, `GIT_*`, `TMPDIR`.
An allowlist would break gates for reasons unrelated to this spec and would need a new exception
every time a gate legitimately reads something. The quarantined set is small, named, and each
entry has an incident behind it.

**`gate_tmpdir` gains a location and a voice, not a workaround.** It honours `GATE_TMPDIR`, and
when the probe fails it says which variable to set and what to set it to. It cannot mount
anything, and it should not try.

## 5. Scope · [S — Structure: boundary]

### In scope
- `specs/lib/assert.sh` — `gate_env_reset`, run on load; `gate_tmpdir` relocatable and legible
- `scripts/ralph-build.sh` — `run_gates` clears the set before invoking a gate, covering the 24
  monolithic gates that source nothing (§4)
- the **three** local copies, deleted — `20260828o`, `20260829a`, `20260829b`
- the stale `20260829a-hermetic-gate` citations, corrected to this spec's id

### Out of scope
- **The compose file's `noexec` tmpfs.** It is deliberate and stays. This spec makes a gate
  survive it and say so; it does not relax a container's hardening.
- Any gate's assertions. Deleting a local reset must not change one verdict, and a spec whose
  gates move is a spec that broke something.
- The loop's env handling **outside gate invocation**. `run_gates` is in scope precisely because
  it is the boundary a gate crosses; nothing else in `scripts/` changes, and the executor's own
  environment is not this spec's business.
- The uncovered third case's *cause*: nothing here stops a container mounting `/tmp` noexec.

## 6. Prior decisions / facts the implementer must know · [S — Structure: system fit & deps]

- **`assert.sh` is sourced, never executed** — its own header says it must not `exit` at the top
  level and must not run anything on load. `unset` is not "running something": it neither exits
  nor produces output. Keep that property; a reset that prints breaks every gate's output
  comparison.
- **37 gates source it.** `20260828k` (8 tasks), `20260829a` (6), `20260828m` (5), `20260828n`
  (4), `20260828o` (4), `20260828l` (3), `20260829b` (1), plus 6 monolithic gates.
- **The three local copies, verbatim**, so the central one is a superset and not a rewrite:
  - `20260829a/lib/fixtures.sh:25` — `unset HARNESS_REPORT_URL HARNESS_REPORT_TOKEN
    RALPH_FORCE_ALL RALPH_FORCE_FROM RALPH_SATISFIED_TIMEOUT`
  - `20260829b/lib/fixtures.sh` — `_fx_env()` wrapping `env -u` over the same five, applied per
    loop invocation
  - `20260828o/lib/fixtures.sh:25` — a DIFFERENT `_fx_env()`, same name as `20260829b`'s, wrapping
    `env -u` over only `HARNESS_REPORT_URL` and `HARNESS_REPORT_TOKEN`. Two helpers, one name,
    two coverage sets: the strongest argument in this spec that the class was never closed.
- **`gate_tmpdir` currently exits 2** on a failed probe — neither pass nor fail — printing only
  `environment: <hostname>`. Callers treat 2 as "the gate could not run". Preserve the exit code;
  only the message and the location change.
- **`20260829b`'s `_fx_env` also serves a second purpose**: that gate SETS `RALPH_SATISFIED_TIMEOUT`
  per invocation, so an ambient value would override the case under test. A central `unset` at
  source time covers it, because the gate sets it after sourcing.
- **Three stale citations name `20260829a-hermetic-gate`**, which collides with
  `executor-image-layer`. They are in `docs/runs/2026-08-29-the-run-that-lied.md:88`,
  `20260829a/lib/fixtures.sh:22` and `20260829b/lib/fixtures.sh:15`. The last two disappear with
  their local copies; the doc's is edited.

## 7. Norms · [N — Norms]

- **Silent on load.** No echo, no `set -x`, no exit. A gate's stdout is compared in other specs'
  assertions.
- **Name the incident in the code.** Each entry in the quarantined set carries the failure it
  came from, in one line, where the list lives — not in this spec only.
- **The message tells the reader what to do.** `gate_tmpdir`'s failure names `GATE_TMPDIR` and a
  path that would work. "environment: <hostname>" is a fact about the machine, not an instruction.
- **Portability holds** (`README.md`'s portability rules): bash 3.2, no GNU-only flags. This
  code runs on the laptop that authors gates and in the container that runs them.

## 8. Safeguards · [S — Safeguards]

- **No fixture may reach a real endpoint.** The quarantined set is the mechanism; T1's assertion
  is that a stub server receives nothing, with a positive control proving the stub can receive.
- **No verdict may change.** Every gate in the repo returns the same exit code before and after.
  A spec that makes gates hermetic by making them fail has done the opposite of its job.
- **`unset`, never a sentinel.** A sentinel URL is still a URL.
- **The reset must not be defeatable by ordering.** It runs on load, so anything a gate sets
  afterwards is the gate's own choice and survives; anything the launching shell set does not.
- **Exit 2 stays exit 2.** A workspace fault is neither a pass nor a failure, and a gate that
  turns it into a FAIL puts an environment problem into the run's evidence as a defect.

## 9. Task breakdown · [O — Operations]

1. **T1** — `gate_env_reset` in `assert.sh`, run on load, with the incident behind each variable.
2. **T2** — delete both local copies; those specs' gates keep their verdicts.
3. **T3** — `gate_tmpdir` honours `GATE_TMPDIR` and fails with an instruction.
4. **T4** — it cannot be forgotten: a new gate inherits it, and no local copy comes back.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

**T1 — the reset**

- **AC-1** When a gate sources `assert.sh`, the system shall unset `HARNESS_REPORT_URL`,
  `HARNESS_REPORT_TOKEN`, `RALPH_FORCE_ALL`, `RALPH_FORCE_FROM` and `RALPH_SATISFIED_TIMEOUT`.
- **AC-2** While a gate runs, a fixture loop it spawns shall reach no endpoint the launching
  shell configured, even when `HARNESS_REPORT_URL` pointed at a reachable server.
- **AC-3** Sourcing `assert.sh` shall produce no output and shall not exit.
- **AC-4** Where a gate sets one of the quarantined variables **after** sourcing, that value
  shall survive — the reset bounds the launching shell, not the gate.
- **AC-4b** When `run_gates` invokes a gate, the quarantined set shall be clear in that gate's
  environment whether or not the gate sources `assert.sh`. Twenty-four gates source nothing.

**T2 — the migration**

- **AC-5** `20260829a/lib/fixtures.sh` and `20260829b/lib/fixtures.sh` shall carry no local
  unset or `env -u` of the quarantined set.
- **AC-6** Every gate in those two specs shall return the exit code it returned before.
- **AC-6b** No gate shall be left uncovered by both placements — a gate that neither sources
  `assert.sh` nor is invoked through `run_gates` is one this spec did not reach.
- **AC-7** With `RALPH_FORCE_ALL=1` in the environment, `20260829b`'s gate shall still observe a
  satisfied task being skipped.

**T3 — the workspace**

- **AC-8** Where `GATE_TMPDIR` is set, `gate_tmpdir` shall create the workspace under it.
- **AC-9** When the workspace cannot execute, the failure message shall name `GATE_TMPDIR` and
  show a path that would work, and shall exit 2.
- **AC-10** `gate_tmpdir` shall keep exporting `PYTHONDONTWRITEBYTECODE` and
  `PYTHONPYCACHEPREFIX`, and shall keep exiting 2 rather than 1 on a workspace fault.

**T4 — durability**

- **AC-11** A gate that sources `assert.sh` and nothing else shall be hermetic, with no call of
  its own.
- **AC-12** No file under `specs/` shall re-implement the quarantined set locally.
- **AC-13** The quarantined set shall appear in exactly one place, and each entry shall carry
  the incident it came from.

## 11. Verification (the harness)

Per-task gates under `tasks/T<NN>-<slug>/verify.sh`. Ids are **two-digit** — `gate-selftest`
matches `FAIL.*<id>` as a substring, so past nine assertions `ac1` aliases `ac10`
(`specs/20260829a-executor-image-layer/evidence/`).

**AC-2 is the one that decides whether this spec is real, and it is an absence assertion.**
Every instance in §1 passed by observing nothing and calling it clean. So: a local stub HTTP
server, `HARNESS_REPORT_URL` pointed at it, a fixture loop run through a gate, and the assertion
that the stub's log is empty — **with a positive control that POSTs to the same stub directly and
proves the log can fill.** Without the control, "nothing arrived" and "my stub never worked" are
the same reading, which is the defect this spec exists to remove, committed by its own gate.

**AC-6 needs a before/after, not a snapshot.** "Those gates pass" is not the claim; "those gates
return what they returned" is. The gate records each spec's exit code with the local copies
restored, then with them removed, and compares — a spec whose gates were already red must stay
red for the same reason.

**T3 cannot mount a filesystem.** AC-8 is behavioural (set `GATE_TMPDIR`, assert `T` lands under
it). AC-9 asserts the *message*, by calling the diagnostic path directly rather than by
simulating `noexec` — stated plainly, because a check that claims to prove more than it does is
the thing being fixed. A real `noexec` run belongs in the container, not in a portable gate.

**Mutants** per task dir. The ones that matter: a reset that lists four of the five variables; a
reset placed inside a function nothing calls; a `gate_tmpdir` that honours `GATE_TMPDIR` but
still prints the hostname on failure; a stub-server probe with no positive control.

## 11b. Loop execution

`scripts/run-loop.sh build-converge specs/20260829c-hermetic-gate` from a worktree on a
throwaway branch. Four tasks, one per iteration, fresh context.

## 12. Open questions

- **OQ1 — does the quarantined set need an escape hatch?** A future gate might legitimately want
  to exercise the reporting path end to end. Today none does, and an opt-out is a way back to the
  present state. Left absent deliberately; add it when a gate needs it and can say why.
- **OQ2 — should CI run one gate under a real `noexec` mount?** It is the only way to test the
  case AC-9 only describes. It needs a Linux runner and a privileged mount, and it belongs with
  the image smoke job in `20260829a`, not here.

## Two-way sync rule

Logic change → spec first. Refactor → code, then sync back. A taste correction made in review
goes into §7 or it recurs next iteration.
