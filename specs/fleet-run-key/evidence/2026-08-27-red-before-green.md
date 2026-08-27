# Red before green — `specs/fleet-run-key`

Validated against `05ee8d7` on the container harness, **two ways**: an empty tree, and a stub.

```
$ bash        specs/fleet-run-key/verify.sh ; echo $?   → 0   (12 pend, 6 PASS, 0 FAIL)
$ STRICT=1 bash specs/fleet-run-key/verify.sh ; echo $? → 1
```

Non-STRICT exits 0 on an unbuilt tree by design; `STRICT=1` promotes all 12 pends so the run
cannot be declared done on work nobody wrote.

## Why the empty tree is not enough

`specs/evidence-replayable` had a red-before-green pass and still shipped an AC-8 control that
**could not pass for any implementation**; it failed correct work three times before anyone
noticed (`specs/evidence-replayable/evidence/2026-08-27-ac8-control-stale-path.md`). The reason
is structural: on an empty tree every presence-guarded branch short-circuits to `pend`, so the
assertions *inside* those branches never execute. They ship unrun and first execute against real
work — the worst possible moment to discover one is wrong.

So this gate was also run against a **stub**: a `run-key.sh` that exists and is executable, and a
`run_key` string in `ralph-log.sh`, with nothing actually implemented. That opens every guard and
forces the assertions to run.

| tree | `ac1` | `ac2` | `ac3` | `ac10` |
|---|---|---|---|---|
| empty | pend | pend | pend | pend |
| **stub, wrong** (exits 1, prints nothing) | **FAIL** | **FAIL** | **FAIL** | **FAIL** |
| **stub, correct** | **PASS** | **PASS** | **PASS** | n/a |

Every guarded assertion is now known to execute, to fail on wrong work, and to pass on right
work. That is the property the empty-tree pass cannot establish.

## Two defects the stub pass found in this gate

Both would have burned executor attempts on correct code.

**1. `ac3` was unsatisfiable.** It asserted the resolver still works with `PATH=/nonexistent` —
which also removes `tr`, `hostname` and every other external command, so no implementation could
have passed. An assertion that cannot pass is a broken control, not a strict one. It now points
`PATH` at a directory containing a **failing `hostname`**, which is the real condition being
described.

**2. The gate littered the worktree.** The scope check used `python3 -m py_compile` on
`loop-index.py`, which writes `scripts/__pycache__/`. A read-only gate that creates files in the
tree it measures will trip the next run's scope check and be blamed on the executor. It now
compiles in memory. After a full run, `git status` is clean apart from the spec itself.

## One defect it found in the harness, before any task ran

`probe()` originally passed the host via a conditional assignment prefix,
`${2:+RALPH_HOST_ID="$2"} bash probe.sh`. Bash recognises assignments **before** expanding words,
so that word is parsed as the *command*, not as an assignment: the probe never ran and the gate
reported `log_init produced no run directory` — a harness failure that was really a gate bug. It
uses `env` now.
