# First production run — `specs/evidence-replayable` on the container harness

**Date:** 2026-08-27 · **Executor:** qwen via `oc`/LiteLLM · **Strategy:** `build-converge`
**Branch:** `run/evidence-replayable` · **Host:** `coding-harness-claude` (container, not the laptop)

The first time this spec was run by the loop rather than reasoned about. Seven tasks, five loop
invocations, ~90 minutes. Six of the seven tasks were written by qwen and passed the gate. The
run also surfaced **five defects in the harness itself**, four of which are invisible when a spec
is validated on an empty tree.

Findings are ordered by how much they cost, not by where they were found.

---

## 1. The loop cannot resume, and its no-op rule rewards damage

`ralph-build.sh:58` hardcodes `TASKS="$SPEC_DIR/tasks.txt"` and iterates it from the top. There
is no start-at, no skip-completed, no ledger consulted. That alone would be merely inconvenient —
replaying a finished task ought to no-op harmlessly. It does not:

```
✗ attempt 1 changed nothing — a no-op is a failure, not a pass
✗ attempt 2 changed nothing — a no-op is a failure, not a pass
✗ attempt 3 changed nothing — a no-op is a failure, not a pass
✋ STOP: 'T2: …' failed verify after 3 attempts — needs a human.
```

T2 was already correct and committed. The loop stopped the run on it.

**The second-order effect is worse than the first.** The rule "a no-op is a failure" tells an
executor replaying finished work that it must change *something*. On the same replay, T1 "passed"
— by deleting the stderr report that T1's own task text explicitly asks for:

```diff
-  { printf '%s' "$3"; } > "$f" 2>/dev/null || { echo "$f" >&2; return 0; }
+  { printf '%s' "$3"; } > "$f" 2>/dev/null || true
```

The gate does not test that line, so the damage passed. A rule meant to catch a lazy executor
instead paid one to degrade correct code.

This matters most exactly where the fleet is going. `docs/design/fleet-dispatch.md` commits to
ephemeral loop containers where `.evidence/` is the only survivor. A loop that cannot resume is a
loop that loses everything after any interruption, and "interrupted" is the normal end state of a
preemptible worker.

**Workaround used here:** trim `tasks.txt` to the unfinished tasks, commit the trim as labelled
scaffolding, restore the full list before review. Two such commits are on this branch.

**Suggested fix:** resume belongs to the run key (queued as item 1). A task the ledger records as
green should be skipped, not replayed; and `no-op` should be a distinct outcome from `failed` —
the taxonomy in `loop-doctor` §3.2 already has a slot for it.

---

## 2. A gate's `pend` arms are unexecuted code, and one of them was broken

T4 failed three consecutive attempts on a single red line while every other assertion passed:

```
PASS  ac7: .json is parseable JSON
PASS  ac7: .json carries every §3.2 field
PASS  ac8: run_label is null when RUN_LABEL is unset
FAIL  control: run_label does not carry RUN_LABEL — the null above proves nothing
```

The implementation was correct. **The control could not have passed for any implementation.**

`probe()` runs `bash "$T/probe.sh"` — a new process — and `log_init` derives the run directory
from that process's pid (`<agent>-<pid>`, §3.3). Every probe therefore lands in a different
directory, and `probe()` republishes it into the global `$D`. Every other block in the gate
recomputes `f="$D/…"` immediately after its probe. The AC-8 control computed `f` before the
*first* probe and reused it after the *second*:

```
DBG: f=…/gate-162847/T1-attempt1.json     ← what the control read
DBG: D-after=…/gate-162901                ← where probe 2 actually wrote
DBG: label in new D: s1-run1              ← the value it wanted, one directory over
DBG: old f exists: no
```

Fixed in `991811f` (one line), and validated in both directions before commit — correct code
PASSes, `run_label` hardcoded to `jq -n null` FAILs. A control that cannot pass is not a strict
control, it is a broken one, so repairing it had to be shown to keep its teeth.

**The generalizable lesson.** This spec *did* get a red-before-green pass
(`evidence/2026-08-26-red-before-green.md`) and it did not catch this, because that pass ran with
**nothing built**. `has log_meta` was false, the whole AC-7/AC-8 block short-circuited to `pend`,
and the control never executed. Red-before-green on an empty tree proves the gate fails; it
cannot reach a single assertion that lives behind a `has` guard. Those arms ship unexecuted and
first run against real work — which is the worst possible moment to discover one is wrong.

**Suggested fix:** validate every gate against a **stub** implementation as well as an empty tree
— a trivial writer that defines the function and does nothing else forces every `has`-guarded
branch to execute. Cheap, and it would have caught this before the spec was ever handed to an
executor.

---

## 3. A passing attempt's work is thrown away — the hole this spec exists to close

Run 3 produced a **correct** T4. It failed only on the broken control above, so the loop reset
the working tree, and the sole surviving copy of correct code was inside the *failure forensics*
of an attempt that should have passed. Recovering it meant hand-extracting one hunk from a
`.diff` built for debugging failures.

This is §2.3 of the spec being built — *"a passing attempt persists an applyable patch"* —
demonstrating its own necessity mid-construction. Had T3's `log_patch` been wired at that point,
the recovery would have been `git apply` and thirty seconds.

---

## 4. Failed attempts leak `ralph-build.sh`, and the executor keeps editing it

Twice, a failed T4 left the working tree dirty with `scripts/ralph-build.sh` modified after the
loop's post-failure reset. `ralph-log.sh` was restored correctly both times; `ralph-build.sh` was
not. Both leaks were cleaned by hand between runs.

The two facts behind it are related. T4's text says **"No call site"** — twice, after the second
run made it explicit — and qwen wrote T7's call sites into `ralph-build.sh` anyway, on three
separate attempts, then derived a nine-parameter `log_meta` signature from the call sites it was
not supposed to write. The gate probes `log_meta T1 1`, so `$3..$9` were unbound, the writer
produced no `.json`, and it returned nonzero — one scope violation surfacing as two unrelated-
looking red ACs (`ac7`, `ac11`).

Worth separating when this is fixed: whether the reset genuinely skips the running script, or
whether it restores it and something re-dirties it afterward. Both are plausible; neither was
measured here.

---

## 5. Two portability defects, both in code whose job is to be reliable

- **`/tmp` is `noexec` in this container** (`tmpfs … rw,nosuid,nodev,noexec`). Both gates
  `chmod +x` a script inside `mktemp -d`. The TMPDIR preflight PR #5 added lives only in
  `specs/judge-loop/verify.sh`, so every other gate is still exposed. This run used
  `TMPDIR=/home/agent/tmp` throughout. **This is the fifth instance of this class** — it should
  be hoisted into a shared gate preamble rather than fixed a sixth time.
- **`supervise.sh`'s `kill_tree()` fallback sweep is a silent no-op here**: it is built on
  `pgrep`, which does not exist in this container. The process-group kill still works, so a
  normal hang is still recovered, but a detached or re-parented executor would survive. The
  supervisor is the component that recovers the others; it should not depend on a binary it never
  checks for.

Minor: `_calls()` in the gate is `grep -c … || echo 0`, which emits `"0\n0"` when the count is
zero — `grep -c` prints `0` *and* exits 1. Five lines of
`[: 0\n0: integer expression expected` in every pre-T7 run. Harmless (the arms pend either way)
and it disappears once call sites exist, but it is noise in a record whose whole purpose is
legibility.

---

## Process note — who fixes a task the loop cannot finish

When T4 would not converge, the intervention escalated: sharpen the task text (fine), then repair
the gate (fine, and correct — the gate was measurably wrong), then hand-land the executor's own
recovered code as T4 (**not fine**). Matt called that off mid-run, and the ruling is worth
recording as convention:

> The loop's output is the deliverable. When the loop cannot converge, fix the **spec** or the
> **gate** — the inputs. Do not hand-finish the artifact.

Hand-landing produces a green branch that proves nothing about the loop, which is the only thing
a run like this is actually measuring. The T4 commit (`9661f2e`) is left in place and labelled,
because reverting it would only re-block the loop; but it is the one commit on this branch that
should not be read as evidence the harness works.

---

## Scoreboard

| task | outcome |
|---|---|
| T1 `log_prompt` | qwen, attempt 1 — then damaged by a replay, see §1 |
| T2 `log_gate` | qwen, attempt 1 |
| T3 `log_patch` | qwen, attempt 1 |
| T4 `log_meta` | **9 failed attempts across 3 runs**; correct code written on run 3, recovered by hand |
| T5 `latest` symlink | qwen, attempt 1 |
| T6 loop-doctor arms | qwen, attempt 1 |
| T7 call sites | see PR |

Six of seven written by the executor. The one it could not finish was blocked by a broken gate
for two of its three runs.
