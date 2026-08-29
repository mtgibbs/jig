# Writing the first mutant corpus in this repo — three findings

**Date:** 2026-08-29 · **Spec:** `20260829a-executor-image-layer`

`scripts/gate-selftest.sh` shipped 2026-08-28 (PR #40). Before this spec, **no `mutants/`
directory existed anywhere in the repo** — the tool had a spec, a gate and no corpus. Its own
spec's outcome 7 and `AC-END-2` call for `20260828g-dispatch-core` to be migrated with one; that
did not happen. This is the first corpus, and writing it surfaced three things.

---

## 1. `gate-selftest.sh` cannot run on macOS, and misreports why

It bounds each gate run with `timeout "$GATE_TIMEOUT"`. macOS ships neither `timeout` nor
`gtimeout` (GNU coreutils, not installed here). The subshell exits 127 with
`command not found`, `gate_out` holds that instead of the gate's output, and the `FAIL.*$id`
grep finds nothing.

Observed, running the T1 corpus with the real tool:

```
base-entrypoint-run-loop.Dockerfile: WRONG-REASON — gate failed but not for ac4
base-installs-opencode.Dockerfile:   WRONG-REASON — gate failed but not for ac2
base-no-copy.Dockerfile:             WRONG-REASON — gate failed but not for ac1
derived-still-standalone.Dockerfile: WRONG-REASON — gate failed but not for ac3
exec-container-keeps-latest.sh:      WRONG-REASON — gate failed but not for ac6
workflow-third-matrix-row.yml:       WRONG-REASON — gate failed but not for ac5
summary: killed=0 survivor=0 wrong-reason=6 hung=0
```

The same six, run through an equivalent harness without `timeout`: **6 killed, 0 survivors.**

`WRONG-REASON` means "your mutant missed" and sends the author to rewrite mutants that were
already correct. **"The gate ran and failed elsewhere" and "the gate never ran" are two states,
and the tool reports the second as the first** — `specs/amendments.md`, *Name the states a check
must tell apart*, in the tool built to enforce that amendment.

There is a second defect in the same loop: `gate_rc` is assigned inside the install loop but read
in the *verdict* loop, so every mutant is judged against the **last** mutant's exit code. It did
not change the outcome here (all six were non-zero) and it would silently mis-verdict a corpus
where one mutant hung or survived.

**Fix (not in this spec's scope):** a portable bound. `perl -e 'alarm shift; exec @ARGV'` is
present on both platforms and needs no coreutils — `lib/fixtures.sh` uses it as `bounded`. And
save `gate_rc` per mutant.

---

## 2. A mutant's `WHY:` header satisfies the gate's own grep

A mutant declares its defect in `# WHY:` lines. When a gate greps the target's text for a token,
the WHY line *saying that token is absent* matches:

```
# WHY: never mentions the .harness search path      <- the gate's grep for '.harness' matches
```

Two of six doc mutants came back `WRONG-REASON` for exactly this — `ac3` (contrast between
`exec-container.sh` and an in-pod binding, killed by the word `in-pod` in its own WHY) and `ac5`
(`.harness`, same shape). Both read as weak assertions. Both assertions were correct.

This is Trap A with the needle planted by the tooling. It applies to **any** gate that reads a
target's text, which is most of them.

**Worked around** with `content()` / `hasc()` in `lib/fixtures.sh`, which drop
`MUTANT:` / `TARGET:` / `WHY:` lines before matching. **The real fix belongs in
`gate-selftest.sh`**: the header is the tool's metadata, not part of the replacement artifact, so
the tool should strip it when installing the mutant. Then no gate has to know mutants exist.

After the workaround: T6 reports 5 killed, 0 survivors, 0 uncovered.

---

## 3. A corpus written before the implementation cannot mean anything — and leaks the answer

Two independent reasons, both discovered here.

**It is unmeasurable.** A per-task gate has no `pend`: an absent artifact is a `FAIL`. On an
unbuilt tree every assertion fails, so a mutant either "kills" an assertion that was already
failing, or comes back `WRONG-REASON` because a *sibling* artifact it does not target is still
missing. Neither verdict says anything about the assertion's strength. Mutation is a
**post-implementation** measurement.

**It hands the executor the answer.** `gate-selftest.sh` installs a mutant as a *complete
replacement file*. For a behavioural assertion, the only plausible complete file is the finished
implementation with one thing wrong — so shipping the corpus up front puts six near-complete
`run-loop.sh` and `run-task.sh` implementations in the spec directory the loop reads. That is
what `specs/TEMPLATE.md` already forbids: *"Keep the adversary OUT of the repo, or a later loop
run stops being a fair measurement."*

**Where the line falls.** A mutant leaks nothing when the spec already fully determines the
artifact's shape — a Dockerfile, a workflow, a doc. It leaks everything when the artifact is
behaviour.

So: **T1 and T6 ship their corpora with the spec** (structural and documentary targets, validated
above). **T2–T5 ship gates now and their corpora with the task**, written by the author against
what the loop actually produced, which is the first moment the verdict can mean anything.
