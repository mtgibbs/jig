# Red before green — `specs/20260828b-index-nested-runs`

Validated against `676059d`, four ways: empty tree, a stub per presence guard, controls for the
two layouts that must keep working, and — the one that mattered — the **real tool's actual
output**.

```
$ bash        …/verify.sh ; echo $?   → 0   (6 pend, 7 PASS, 0 FAIL)
$ STRICT=1 bash …/verify.sh ; echo $? → 1
```

## The gate was written against real output, not an assumed schema

The first draft expected `loop-index.py --jsonl` to emit one row per run with a `pid` field. It
emits one row per **task**, with a `runs` array. Every assertion in that draft would have failed
every correct implementation.

It was caught by running the real tool over the fixture before writing a single assertion — the
rule that came out of `specs/20260828a-exec-container`, where a check fired on the string `curl`
because the stub was mine rather than the repo's. Here the fixture reproduces the bug exactly:

```
runs: [ pid 2002 (scoped), pid 3003 (flat) ]      attempts_observed: 2
```

1001, the nested run, is simply absent. Three runs on disk, two seen.

## The blast radius was four deep

`20260827b-fleet-run-key` added one directory level. Four readers and writers had the old depth
baked in, and **only the first was visible at the start**:

| # | defect | how it surfaced |
|---|---|---|
| 1 | `loop-index.py` enumerates nothing | `evidence-spec-nesting` AC-4/8/9, two merges later |
| 2 | that gate's own `-mindepth 2 -maxdepth 2` | reading it, once it was the accused |
| 3 | empty spec directories never pruned | its AC-6, only after 1 and 2 were fixed |
| 4 | the reap **moved** from depth 2 to depth 3, so legacy-layout runs are never collected | its AC-6 again, only after 3 was fixed |

Each was invisible until the one before it was repaired: a gate reports its first failure and the
ones behind it wait their turn. Declaring victory when the original symptom clears would have left
two of the four in place.

Defect 4 is the sharpest, because this spec's own T1 text warns against exactly it — *"a change
that sees the new layout by ceasing to see an old one has moved the blindness rather than cured
it"* — and that is precisely what the earlier fix did to the reap.

## Identifying a run by structure, not by name

The reap has to collect a run at either depth without deleting a **host** directory, which also
sits at the shallower one. It cannot tell them apart by name: `<agent>-<pid>` is indistinguishable
from a Kubernetes pod name like `harness-run-7`, which is why the host level is excluded by
position everywhere else in the harness.

By structure it is exact — a run directory holds files and no subdirectories; a host directory
holds run directories. Verified against the detector's own two cases, which pull in opposite
directions:

| case | requirement | result |
|---|---|---|
| AC-5: aged **spec** dir, fresh runs inside | runs survive | PASS |
| AC-6: aged legacy run in a dead spec | reaped, then pruned | PASS |

and by a control in this gate: a **fresh** run under an **aged host** survives, because a
directory's mtime tracks its newest child and reaping the host wholesale would take live runs
with it.

## Every guard opened

Four guards, four stubs, and the stubs were representative — the reap stub was tested against the
detector's fixtures rather than against one I invented. With all three tasks stubbed: 13 PASS,
0 FAIL, `evidence-spec-nesting` back to 15 PASS / 0 FAIL.

One defect the stub pass found in this gate first: importing `loop-index.py` to exercise
`harness_roots` directly wrote `scripts/__pycache__/` into the worktree. A gate that litters the
tree it measures trips the next run's scope check. `PYTHONDONTWRITEBYTECODE=1` now.
