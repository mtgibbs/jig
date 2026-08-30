# What the gates found while being written

**Date:** 2026-08-29 · **Spec:** `20260829c-hermetic-gate`

Four findings, none of which came from reading. Each arrived as a gate returning a verdict its
author did not expect, and two of them changed the design.

---

## 1. There are three local copies, not two — and two share a name

The spec was drafted against `20260829a` and `20260829b`. T4's ac02 found a third:
`20260828o-evidence-egress/lib/fixtures.sh:25`.

| file | mechanism | covers |
|---|---|---|
| `20260828o` | `_fx_env()` wrapping `env -u`, per invocation | **2** of 5 |
| `20260829a` | `unset`, at source time | 5 of 5 |
| `20260829b` | `_fx_env()` wrapping `env -u`, per invocation | 5 of 5 |

**Two different helpers called `_fx_env`, covering different sets.** A reader who finds one has no
way to know the other exists or which is authoritative. This is the strongest evidence in the
spec that the class was never closed: three sites, three variants, each closed locally, each
making the next look like a one-off.

## 2. `assert.sh` alone reaches barely half the gates — the design changed

T2's ac03 was written to catch a gate orphaned by the migration. It found **24 monolithic gates**
that source `assert.sh` at all — `20260801a` through `20260828j` predate
`20260828i-per-task-gates` and define `ok`/`no`/`pend` inline.

Several of them drive the real loop (`20260827a` runs `run-loop.sh`, `20260828e` runs
`ralph-build.sh`), which makes them **exactly** the gates that can post to a coordinator. The
original design — "put it in the file every gate sources" — covered 31 of 55.

So the reset went to two places: `assert.sh` for gates run by hand or by `gate-selftest`, and
`run_gates` for every gate the loop invokes, whatever it sources. Neither is redundant, and the
boundary placement needs no cooperation from a gate at all.

## 3. Two assertions that measured the wrong thing, both caught by their own mutants

**ac05 checked presence where the feature is position.** It grepped `run_gates`' region for the
reset construct. The mutant put the reset at the *end* of `run_gates`, after the gate had already
run with everything inherited — and ac05 passed. *"The reset is in this function"* and *"the gate
ran without those variables"* are two claims and only the second is the feature.

**ac02 read the spec's own constant instead of the code.** It compared the historical local sets
against `$QUARANTINED` in this spec's `lib/fixtures.sh` — so it passed however `assert.sh` was
actually written, and a mutant that narrowed the real set survived. A check that reads the
author's declaration measures intent, which is never the thing in doubt.

Both were found by mutants aimed at them. Neither is visible by reading the assertion.

## 4. Three self-matches in one session

A check whose own source contains the string it searches for:

| where | what it matched |
|---|---|
| `20260829a` T6 doc gate | a mutant's `WHY:` line saying the token was absent |
| `20260829a` T1 ac11 | its own `grep 'exec-qwen\.sh'` pattern |
| this spec, T4 ac02 | its own `grep '(unset\|env -u).*HARNESS_REPORT_URL'` pattern |

The instrument inside the thing being measured, three times, in gates written by someone who had
just documented the first one. Excluding `BASH_SOURCE[0]` is the fix, and it needs the path
resolved absolutely — comparing it raw matches only under `gate-selftest`, which invokes gates by
absolute path, and flags the gate on every run by hand.

---

## The stub server, and a DNS lookup nothing needs

`lib/stub.py` subclasses `HTTPServer` to skip `socket.getfqdn()` in `server_bind`. On this machine
that call blocks longer than the gate's readiness wait, so the port line was never printed and the
gate reported *"the stub never came up"* — while the server was fine. A readiness timeout would
have hidden it as slowness rather than naming it, and a gate that is merely slow on one machine
is a gate that gets dropped from the loop.

## Final state

```
T01-reset       5 mutants   killed=5  survivor=0  wrong-reason=0
T02-migration   3 mutants   killed=3  survivor=0  wrong-reason=0
T03-workspace   3 mutants   killed=3  survivor=0  wrong-reason=0
T04-durability  3 mutants   killed=3  survivor=0  wrong-reason=0
```

All four gates red on the unbuilt tree. T01 proven green against a six-line reference
implementation of `gate_env_reset`.
