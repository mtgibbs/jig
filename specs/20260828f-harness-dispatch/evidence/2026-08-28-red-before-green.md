# Red before green — `specs/20260828f-harness-dispatch`

Baseline: 7 pend, 0 FAIL, `STRICT` rc 1. Final: 11 PASS, `STRICT` rc 0.

## Adversarial by design

For a dispatcher the dangerous failure is not *"it did not launch"* — it is *"it launched
something it should not have"*. So most assertions check the launcher was **not** called, through
a mock `kubectl` on `PATH` that records argv and stdin.

A negative assertion is worthless if the mock is broken, so each is paired with a **positive
control** asserting the mock records a call when one is genuinely made. Without it, "did not
launch" passes just as well when nothing works at all.

## Validated four ways before the executor saw it

| stub | result |
|---|---|
| **correct** implementation | all 11 assertions PASS — so they are mutually satisfiable |
| `parse_intent` accepts any verb | **`ac2` FAILS** — an unrecognised message reached the launcher |
| dedupe disabled | **`ac3` FAILS** — the same event launched 3 times |
| `nodeSelector` dropped, then `activeDeadlineSeconds` dropped | **`ac4` FAILS** on each |

The mutual-satisfiability check is there because `ac3` and `ac10` in
`specs/20260828d-image-ci` contradicted each other and cost three attempts on correct work.

## Three defects in this gate

**1. A missing bound pended instead of failing.** Found by mutation: dropping `nodeSelector` gave
a `pend`, so a Job free to schedule onto the 1 GB Pi 3 beside Pi-hole could have passed a mid-spec
task. `render_job` returning an object means it is *built*; an object omitting a safety bound is
**wrong, not unbuilt**.

**2. The control depended on later tasks.** It calls `render_job` and `launch` — T3 and T4's work —
so during T1 it raised, recorded nothing, and reported every negative assertion vacuous. T1 failed
three attempts on a correct parser.

This was the **third occurrence in one night** of keying an assertion on a task that does not own
it, after `ac7` in `20260828b-index-nested-runs` and `ac2` in `20260828e-record-fields`. Twice the
instance was fixed and the rule written down; it recurred anyway. The fix is now **structural**: a
`HAVE` probe listing which functions exist, and a `have()` helper each AC calls for its own
dependencies. Verified on the exact failing scenario — a T1-only module gives `ac1` PASS,
everything else pend, zero FAIL.

The pattern is specific: this defect only appears in gates over **staged** work, where later tasks
add the machinery earlier assertions want to exercise. That is every multi-task spec, which is why
remembering the rule was not enough.

**3. `restartPolicy` was never asserted — and the Job was invalid without it.** The gate checked
namespace, node selector, deadline, TTL and `backoffLimit`, and missed the field that makes a Job
*acceptable to the API server at all*. Every assertion passed while the prototype's central
artefact would have been rejected on apply.

Found by rendering a Job with the real module and reading the output, not by trusting the verdict.
Third time tonight that reading a generated artefact caught what a green gate did not, after the
hardcoded image tag in `build-images.yml` and the dead call site in `ralph-build.sh`.

## One design gap, logged rather than fixed

`handle_event` calls `record_seen` after `launch` **regardless of the launch's exit status**. A
failed launch is therefore recorded as seen, so a replay of that event is deduped away and the run
silently never happens — fail-silent, in a design whose ADR (D6) is explicitly fail-loud.

Fixing it means choosing retry semantics — retry, report, or dead-letter — which is a design
decision rather than a bug fix, so it is written down here rather than guessed at.
