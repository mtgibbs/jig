# Red before green — `specs/last-task-strict`

Validated against `6d20b49`, **four ways**: empty tree, a stub of the *correct* fix, a stub of the
*wrong* fix, and a stub per remaining presence guard.

```
$ bash        specs/last-task-strict/verify.sh ; echo $?   → 0   (4 pend, 5 PASS, 0 FAIL)
$ STRICT=1 bash specs/last-task-strict/verify.sh ; echo $? → 1
```

## The gate is behavioural

The claim is about what the loop *does*, so the gate builds a two-task fixture spec with a mock
executor and runs `ralph-build.sh` against it. The fixture is rigged so the two modes give
**opposite** answers on the same tree:

| | T1 (`a.txt` created) | T2 (`b.txt` never created) |
|---|---|---|
| lenient everywhere (today) | ✓ pass | **✓ pass — the bug** |
| STRICT everywhere (wrong fix) | **✗ fail** | ✗ fail |
| per-task strictness (this spec) | ✓ pass | ✗ fail |

"T1 passes **and** T2 fails" is reachable only by the intended fix. Measured, not asserted:

```
STUB — the CORRECT fix (last task only):
  PASS  ac2: T1 still passes under leniency
  PASS  ac1: the LAST task's gate treats pend as failure, while the first task's does not

STUB — the WRONG fix (whole-run STRICT):
  FAIL  ac2: T1 failed. A mid-spec pend must NOT fail: that is whole-run STRICT
  FAIL  ac1: T2 failed but so did T1
```

## Two defects the stub pass found in this gate first

Both would have failed correct work, which is the third and fourth instance of that class today.

**1. `ac6` was a gate that could not fail.** It grepped the *whole* run output for
`strict|lenient`, and the final STRICT block already prints the word "strict" on its own — so it
passed green with nothing built. It now reads only the task's own verdict line.

**2. `ac3` measured the wrong surface.** It asserted the still-red AC appears in the run's output.
It does not: the retry feedback is delivered to the **executor's prompt**, and is never printed.
Against the correct fix it read `FAIL ac3: the run never names ac2` — a correct implementation,
failed by the gate. The mock executor now records every prompt it receives, and `ac3` asserts on
the retry prompt, which is the surface the outcome is actually about. `RALPH_RETRIES` is 1 rather
than 0 so a retry exists at all: a feedback nobody receives is precisely the failure mode.

## Every guard was opened

The lesson from `specs/fleet-run-key`: validating against a stub is **one action per presence
guard**, not one per gate. That gate had four guards and two stubs, and the two unopened ones
failed correct work for three attempts.

| guard | opened by | result |
|---|---|---|
| `_t2_passed` (ac1, ac3) | stub of the T1 change | FAIL→PASS, and the wrong fix fails differently |
| `_verdict` (ac6) | verdict line carrying the mode | pend → PASS |
| `TEMPLATE.md` (ac7) | one line in the template | pend → PASS |

Four of four. No assertion in this gate ships unexecuted.
