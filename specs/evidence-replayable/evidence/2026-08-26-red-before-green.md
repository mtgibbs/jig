# Red before green — `specs/evidence-replayable`

Run against `1ea0c6e` with **no task built**, from `~/dev/harness-evidence`.

```
$ bash specs/evidence-replayable/verify.sh   ; echo $?      → 0   (14 pend, 6 PASS, 0 FAIL)
$ STRICT=1 bash specs/evidence-replayable/verify.sh; echo $? → 1
```

Non-STRICT exits 0 on an unbuilt tree **by design**: every check is staged on its own task's
deliverable, so T1 can pass without T7's call sites existing. `STRICT=1` promotes all 14 pends
and the run cannot be declared done on work nobody wrote.

## What the first draft got wrong, and how the gate caught it

The first version reported:

```
FAIL  ac12: loop-doctor reports unparsed=4 on a HEALTHY run — the new artifacts read as format drift
```

Two separate things, and only one of them was the intended finding.

**1. The finding is real and was previously only a prediction.** `loop-doctor.sh:150`'s `case`
ends in `*) unparsed=$((unparsed + 1))`. The four artifacts this spec adds are unrecognised, so
a run in perfect health reports `unparsed=4` — degrading the exact telemetry-drift signal
`loop-doctor` §2.5 exists to provide. Predicted while reading; **measured** here. That is why T6
is in scope rather than a follow-up.

**2. The gate itself was mis-anchored, and it FAILED where it should have PENDed.** `ac12` tests
T6's deliverable. The build loop requires `verify.sh` to exit 0 after *every* task, so a hard FAIL
on T6's work makes T1 unpassable and burns its whole retry budget on work not yet due — the
too-coarse anchoring failure `TEMPLATE.md` §11 measures at 45/0 → 49/6 in `notes-from-hearing`.

Fixed by staging on T6's own narrowest observable. Note what the staging is **not**: the grep for
`prompt\.md` in `loop-doctor.sh` decides only whether the check is *armed*. The verdict is still
the functional `unparsed==0` assertion against a real fixture run. A grep as the check would be
Trap A; a grep as the trigger is staging.

## Positive controls (Trap B)

Both assertions this spec leans on are of the "expect 1 / expect 0" form, which a broken probe
satisfies identically. Each has a control that is *asserted to move the counter*:

| control | proves |
|---|---|
| a bare `git diff` on the fixture **omits** `created.txt` | AC-5's `git add -A -N` requirement is real, and an empty patch would otherwise pass `git apply --check` |
| renaming `T1-attempt1.gate.txt` → `.gate.log` **doubles** `attempts_seen` to 2 | AC-14 is measuring something; the `.txt` extension is load-bearing, not cosmetic |
| setting `RUN_LABEL=s1-run1` makes `run_label` the string | AC-8's `null` is measured, not a field that is always null |

Without the second control, `ac14` ("exactly one artifact matches `T*-attempt*.log`") is green on
a tree where the writers do not exist at all — which is precisely the state it was first run in.

## Fixture-coincidence check

The fixture repo deliberately contains **one tracked modification and one new untracked file**.
A fixture with only tracked edits cannot express the AC-5 failure: every patch shape passes, and
the assertion would be green for the wrong reason (`judge-loop` §3, `fixture-coincidence`).
