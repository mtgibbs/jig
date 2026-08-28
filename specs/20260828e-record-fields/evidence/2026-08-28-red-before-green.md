# Red before green — `specs/20260828e-record-fields`

Behavioural: the gate drives the real `ralph-build.sh` with a mock executor scripted to pass,
no-op, be stillborn, and be gate-rejected in turn, then reads the records that came out.
Asserting on the script's source would pass on a comment.

Baseline: 6 pend, 0 FAIL, `STRICT` rc 1. Final: 10 PASS, `STRICT` rc 0.

## Two problems in the harness that the issue did not name

`harness#15` reported three empty fields. Specifying it surfaced a second: **one of the four
declared outcomes was unreachable.** The no-op branch called `hb_write` and `continue`d without
calling `log_meta` at all, so a no-op attempt left no record and `noop` could never appear.

A third emerged once the gate could assert it: the exhausted-attempts stop **overwrote** the
record an attempt had already written — a no-op recorded `noop`, then was immediately replaced
with `failed`, because that stop reuses the last attempt's number. It is a *task*-level event
written as an *attempt*-level record. The spec's §3.1 mapped it as an attempt ending; that was
wrong, and the gate caught **the spec** rather than the code.

## Six defects in this gate, and what each teaches

| # | defect | class |
|---|---|---|
| 1 | `ac3` accepted `started=0/ended=0` — an unset clock records 0, and `0 >= 0` is ordered | **gate that cannot fail** |
| 2 | `ac6` matched the word `stillborn`, which already appeared in the detector as prose | **gate that cannot fail** |
| 3 | `ac2`/`ac5` reported FAIL where the value was merely absent | unbuilt ≠ wrong |
| 4 | `ac2` keyed on T3's artefact while evaluated during T2 | **wrong task keyed** |
| 5 | no AC covered a gate-rejected attempt at all | **incomplete set** |
| 6 | the `pass` mode COMMITS `a.txt`, so deleting it left a staged deletion and the no-op branch never fired | **test isolation** |

Defect 4 is the one worth dwelling on: it is the *same* defect as `ac7` in
`specs/20260828b-index-nested-runs`, written up four hours earlier as "a pend must key on the
artefact of the task that SATISFIES it". Writing the rule down did not prevent applying it wrong.

Defect 5 is what let a dead call site through. `pass`, `noop` and `stillborn` each have their own
ending, so a gate covering only those three stays green while `failed` is unrecordable — which is
exactly what happened: an implementation guarded the exhausted-attempts site on the **end
timestamp**, which is always set, so the site never fired and the `failed` case was silently lost.
`ac7` exists because of that.

Defect 6 produced the most misleading symptom of the night — a no-op attempt recording `failed`,
which reads as a bug in `ralph-build.sh`. It was the fixture. Fixing it then broke `ac7`, because
a stray `BASE=""` initialiser sat *after* the real assignment and silently disabled every reset:
declare-then-assign in the wrong order.

## T2, T3 and T5 were written by hand

Nine attempts across this spec's back half. The executor emitted `LOG_OUTCOME="passed"` three
times on consecutive lines, and rewrote the exhausted-attempts site into a form that could never
execute. Per the standing rule — past a few rounds of sharpening, fix it yourself and **say so** —
those `ralph-build.sh` changes are mine. **T1 and T4 are the loop's.**

Recorded so a green gate on a five-task spec is not read as the executor having produced all of it.

## One more cost, and it was my error

I dropped T2 and T3 from the task list believing the executor had already done them — having seen
that work by applying a **failed attempt's patch**. The loop's post-failure reset had discarded it.
`LOG_OUTCOME` appeared zero times in the tree while I reasoned as though it appeared five.

**An attempt's patch is evidence of what the executor produced, not of what the repository
contains.** That distinction is the entire point of `specs/20260826a-evidence-replayable`, and I
got it wrong while extending it.
