# The gate was mutation-tested before the spec was opened

**Date:** 2026-08-28 · applying `20260828i`'s rule by hand, since the tooling for it is still in flight.

## Method

1. Ran the gate at **baseline** (nothing built): 11 pends, `VERIFY: PASS`. A gate that fails before
   work starts fails the first task for reasons that have nothing to do with it.
2. Wrote a **reference implementation** of `server.py` and installed it, so every presence guard
   opened. A guard left unopened is an assertion that has never run, and it first runs against the
   executor's work.
3. **Mutated each assertion** — one broken implementation per assertion, each required to make its
   own assertion fail.

The reference implementation is deliberately **not committed**. It would be the answer key sitting
next to the exam: the executor reads this directory, and `20260828g`/`20260828h` both showed it
reads whatever is there. The mutation *results* are evidence; the implementation is a spoiler.

## What step 2 caught

`ac8` failed against a **correct** server:

```
FAIL  ac8: fewer POST bodies than launch_run calls — the server retried or dropped one
```

`grep -c` counts matching **lines**, and the recorded bodies are a single line of JSON, so it
counted 1 and could never reach 3. That assertion would have failed correct work on every run.
Fixed to `grep -o … | wc -l`.

## What step 3 caught

| assertion | mutant | result |
|---|---|---|
| ac1 | starts with no token | killed |
| ac2 | `initialize` omits `protocolVersion` | killed |
| ac3 | `cancel_run` listed | killed |
| ac4 | `idempotency_key` optional with a default | killed |
| ac5 | a read tool uses POST | killed |
| ac6 | 401 reported as a missing run | **survived → mutant was wrong → killed on v2** |
| ac7 | 501 flattened onto the 404 wording | killed |
| ac8 | server regenerates the caller's key | killed |
| ac9 | token echoed in an error | killed |
| ac10 | imports `dispatcher` | killed |
| ac11 | doc drops the 501 distinction | killed |

**11/11 killed, each for its own declared reason.**

The ac6 survivor is the interesting one, and it is why "the gate must fail" and "the gate must fail
*for that assertion's reason*" have to be two separate requirements. My first mutant patched the
401 branch in `list_runs`; ac6 exercises `run_status`, which has its own branch. The mutant never
ran the code the assertion tests. It looked like a weak assertion and was actually a mutant that
missed — and a corpus that scored it as "assertion cannot detect this" would have sent me rewriting
a correct check. Repointed at all three 401 branches, ac6 kills it.
