# The AC-8 positive control asserted against a file no probe ever wrote

Found during the first production run of this spec, on the container harness. T4 failed three
attempts in a row with a single red line while every other AC-7/AC-8 check passed:

```
PASS  ac7: .json is parseable JSON
PASS  ac7: .json carries every §3.2 field
PASS  ac8: run_label is null when RUN_LABEL is unset
FAIL  control: run_label does not carry RUN_LABEL — the null above proves nothing
```

The executor's implementation was correct. The control could not pass for **any**
implementation.

## Measured, not inferred

`probe()` runs `bash "$T/probe.sh"` — a **new process** — and `log_init` derives the run
directory from that process's pid (`<agent>-<pid>`, §3.3). So every probe lands in a different
directory, and `probe()` republishes it into the global `$D`. Every other block in this gate
recomputes `f="$D/…"` immediately *after* its probe. The AC-8 control did not: it computed `f`
before the first probe and reused it after the second.

An instrumented copy of the gate, against the executor's own attempt-3 code:

```
DBG: f=…/ev/evidence-replayable/gate-162847/T1-attempt1.json     ← what the control read
DBG: D-before=…/gate-162847
DBG: D-after=…/gate-162901                                        ← where probe 2 actually wrote
DBG: json in new D: …/gate-162901/T1-attempt1.json
DBG: label in new D: s1-run1                                      ← the value the control wanted
DBG: old f exists: no
```

The record carried `s1-run1` the whole time, one directory over.

## The fix, validated in both directions

One line — recompute `f` from `$D` after the second probe. A control that cannot pass is not a
strict control, it is a broken one, so the repair was checked against a deliberate mutation as
well as against correct code:

| implementation | control |
|---|---|
| reads `RUN_LABEL`, falls back to JSON null | **PASS** |
| `run_label` hardcoded to `jq -n null` | **FAIL** — "the null above proves nothing" |

Red before green, in that order, both measured on this container.

## Why it survived the spec's own red-before-green pass

The original evidence run was made with **no task built**. `has log_meta` was false, so the AC-8
block short-circuited to `pend` and the control never executed. A `pend` arm proves nothing about
the code inside it — the branch had never run until an executor got far enough to reach it, and
the first thing it did when it ran was fail a correct implementation.
