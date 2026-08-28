# Red before green — `specs/20260828c-strategy-file-extension`

Validated against `e31c548`. Non-STRICT rc 0 (6 pend), STRICT rc 1.

## The cause, isolated with a controlled fixture

Three **byte-identical** files, three extensions, one prompt, no `--auto`:

```
! permission requested: read (sub/thing.env); auto-rejecting
✗ Read sub/thing.env failed
→ Read sub/thing.txt        ← read fine
→ Read sub/thing.conf       ← read fine
```

Content is irrelevant; the **name** is the trigger. A second fixture ran seven candidates:

```
→ cand.sh   → cand.bash   → cand.conf   → cand.strategy   → cand.loop   → cand.ini
! permission requested: read (cand.env.sh); auto-rejecting          ← BLOCKED
```

So the guard matches `env` as a **dotted component anywhere in the name**, not just the trailing
extension. `.conf` is clear in both fixtures. This also kills the compromise names — anything
containing `.env.` is out.

**One correction to an earlier claim.** It was reported during
`20260828a-exec-container` that a refused tool call is *terminal* for this executor. It is not:
in both fixtures the session continued and read the remaining files. What happened in that spec's
T3 is that the model hit the refusal and then produced nothing useful — it lost the thread rather
than the harness aborting it. The effect on the loop is identical (`changed nothing`, three
attempts burned) but the mechanism is different, and the earlier claim was over-read from a
truncated transcript.

## Every guard opened, and the whole change stubbed

With the full change applied as a stub — five files renamed, three resolution sites and the header
comment updated, references rewritten — all eleven assertions pass. Reverted, six pend.

`ac2` and `ac3` pass on the **unbuilt** tree by design: they are regression guards, not new work.
They exist to fail if the rename breaks `--list` or resolution, and their control (an unknown
strategy must still report `unknown strategy`) is what makes the pair meaningful.

## The finding worth keeping: a rename disarmed a guard silently

Two other specs' gates reference these files by path. Applying the rename **without** updating
them:

| gate | result |
|---|---|
| `20260828a-exec-container` | **RED** — loud, would be noticed |
| `20260825c-executor-binding` | **GREEN**, measuring less — silent |

`AC-7` in `executor-binding` asserts the executor layer is smaller than the two loops it replaced:

```
now=$(cat ralph-build.sh exec-qwen.sh exec-codex.sh scripts/loops/build-codex.env 2>/dev/null | wc -l)
[ "$now" -gt 0 ] && [ "$now" -lt 424 ]
```

Measured:

```
with build-codex.conf present (4 files):  348
if the 4th is missing (silent drop):      333
threshold < 424 — BOTH pass
```

`cat` fails into `2>/dev/null`, the count drops, and the assertion gets **easier**. The gate keeps
printing `AC-7:executor-layer-shrank` while silently measuring three files instead of four.

This is the **second** measured path-change-disarms-a-guard instance, after
`20260827a-spec-manifest`'s `_PREDATING` list became a no-op during the date-prefix rename. The
smell is specific and greppable: **`2>/dev/null` on a path that feeds a measurement** turns a
missing input into a smaller number rather than an error.

After a rename the question is not "does everything still pass" but "does everything that passed
before still have teeth".


## A gate defect the run exposed: a truncated work list

`ac4` originally piped its file list through `head -4`, for readable output. That list is not
output — it reaches the executor through the retry feedback, and **the working tree is reset
between attempts**, so every attempt starts from all nine broken files and is then told about at
most four of whatever it happened to miss.

Measured, from the two failing attempts:

```
attempt 1 named: executor-binding/spec.md, executor-binding/tasks.txt, exec-container/evidence…
attempt 2 named: scripts/exec-codex.sh, exec-container/evidence…, exec-container/…
```

Different subsets, out of nine. The executor was never once shown the whole job, and no amount of
extra attempts would fix that: nothing accumulates between them except the previous attempt's
`FAIL` lines and `ralph-retry.sh`'s regression list. More attempts are independent re-rolls, not a
ratchet.

T2 passed on attempt 3 anyway, by covering more ground in one pass. The `head` is removed so the
next task of this shape gets the full list.
