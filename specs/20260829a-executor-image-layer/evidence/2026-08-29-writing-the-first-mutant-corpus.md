# Writing the first mutant corpus in this repo — three findings

**Date:** 2026-08-29 · **Spec:** `20260829a-executor-image-layer`
**Sibling:** `docs/runs/2026-08-29-the-run-that-lied.md` (#53) catalogues six ways a run's recorded
outcome disagreed with what happened. These three are the same theme one level out — the tool that
*measures* a gate, rather than the loop that reports a run. Its finding 1 and finding 1 below are
the same defect class from opposite ends: there, a bound set too tight to evaluate the gates worth
skipping; here, a bound that did not exist on the machine and was reported as the mutant's fault.

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


---

## 4. Two more, from folding the review amendments in (2026-08-29, later)

**A gate id that is a prefix of another id is a false kill.** `gate-selftest.sh` kills a mutant by
grepping the gate's output for `FAIL.*<id>` — a SUBSTRING match. T1 grew past nine assertions, so
a mutant declaring `ac1` would have been reported KILLED whenever `ac10` failed, and the author
told an assertion was strong when it was never exercised. T1's ids are two-digit now. **The hazard
is in the tool, not in this gate**: every corpus in this repo that reaches ten assertions inherits
it, and none has yet.

**A check can be correct and still unaffordable.** ac10 ("a node-less image says the codesheet is
off") went through three forms:

| form | verdict on an unbuilt tree | why it was wrong |
|---|---|---|
| `grep -qE 'else\|echo\|>&2'` over the guard's region | **PASS** | matched `echo "codesheet: injected …"` — the SUCCESS branch. Trap A, needle already in the haystack. |
| behavioural: run the loop twice with node off `PATH`, one run against a patched control | FAIL, correct | **41s per gate run**, over gate-selftest's 30s bound — every mutant in the corpus came back HUNG |
| parse the guard's own `if/else/fi` and require the ELSE to mention node or the sheet | FAIL, correct, **0s** | — |

The middle one is the interesting failure. It was the *most* rigorous version and it made the
corpus unrunnable, which in this repo means it would quietly stop being run — the same end state
as the false green, reached from the opposite direction. A check has to be affordable by the
tooling that is supposed to keep exercising it.

Final state: T1 **11 killed / 0 survivors / 0 wrong-reason**, T6 **5 / 0 / 0**, no uncovered ids.
