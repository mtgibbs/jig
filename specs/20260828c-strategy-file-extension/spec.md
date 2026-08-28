# Spec: a strategy file stops looking like a secrets file

- **Status:** Draft v0.1
- **Owner:** Matt (design by Claude; executor qwen)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** git, sed
- **MCP:** none
- **Permissions:** write:scripts/**, write:docs/**, exec:git
- **Touches:** `scripts/loops/*.env` → `*.conf` (5 files), `scripts/run-loop.sh` (3 resolution
  sites + its header comment), `scripts/loops/README.md`, the remaining references in `docs/` and
  `scripts/`, and the hard path references in two other specs' gates (§6). **No change** to
  `ralph-build.sh`, `ralph-judge.sh`, `ralph-log.sh`, or `ralph-status.sh`.

---

## 1. Why · [R — Requirements]

The harness's least secret configuration carries the one extension every agent tool treats as
secret-bearing. A strategy file holds `STRATEGY_DESC`, `STRATEGY_PHASES` and `RALPH_EXEC_CMD` —
and nothing else, ever.

Measured on 2026-08-28 with a controlled fixture: three **byte-identical** files, three
extensions, one prompt, no `--auto`.

```
! permission requested: read (sub/thing.env); auto-rejecting
✗ Read sub/thing.env failed
→ Read sub/thing.txt        ← read fine
→ Read sub/thing.conf       ← read fine
```

The trigger is the **extension**. Content is irrelevant, and the tool is not wrong to guard
`.env` — that guard is correct default behaviour almost everywhere. We chose a filename that
collides with a near-universal safety convention.

**It cannot be worked around from the task text.** Three different instruction shapes were tried
while building `20260828a-exec-container`, including one naming no sibling file at all. All
failed, because the executor explores the directory it is writing into: it read
`scripts/loops/README.md`, then a sibling `.env`, then produced nothing. Any task that creates a
file under `scripts/loops/` hits this.

The loop then scores the empty result as `changed nothing — a no-op is a failure` and burns every
attempt, so **a permission surprise is indistinguishable from a lazy executor**. That cost nine
attempts across three runs before the transcripts explained it. In an ephemeral fleet worker it
would read as a bad model and nothing else.

`--auto` is the current mitigation and is deliberately blunt (`docs/design/fleet-dispatch.md`
item 8). This removes the cause instead, for every tool rather than one.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. Every strategy file is named `<name>.conf`; none is `.env`.
2. `run-loop.sh --list` still names every strategy exactly as it does today.
3. `run-loop.sh <strategy> <spec>` still resolves each strategy, and an unknown one still fails
   with the same "unknown strategy" error.
4. No tracked file still refers to a strategy as `<name>.env`.
5. Strategy files remain sourceable shell — `bash -n` clean, sourced with `.` as today.
6. Nothing outside the touched files changes.

## 3. Entities · [E — Entities]

### 3.1 The five strategy files

`build-codex`, `build-container`, `build-converge`, `build-then-judge`, `judge-refine` — plus
`scripts/loops/README.md`, which documents the contract and is **not** a strategy.

### 3.2 The three resolution sites in `run-loop.sh`

| line | today | why it matters |
|---|---|---|
| 17 | `for f in "$LOOPS_DIR"/*.env` | `--list` enumerates strategies |
| 19 | `name="$(basename "$f" .env)"` | strips the extension for display |
| 28 | `ENV_FILE="$LOOPS_DIR/$STRATEGY.env"` | resolves the named strategy |

The header comment at line 7 states the contract in prose and is part of it.

### 3.3 Why `.conf`

Verified unblocked by the fixture above. It is honest about what these are — configuration that
`run-loop.sh` happens to source — and, unlike `.sh`, it carries no implication that the file is an
executable wanting a shebang and a `+x` bit. The cost is losing shell syntax highlighting on four
assignment lines, which is a fair trade for never colliding with a secret-file convention again.

## 4. Approach · [A — Approach]

**The rename and the code change are ONE task, deliberately.** Either half alone leaves
`run-loop.sh` unable to find its own strategies: rename first and the next invocation resolves
`<name>.conf` against files still called `.env`; change the code first and it resolves `.conf`
against nothing. The loop cannot be restarted from that state, which is exactly the state a failed
attempt leaves behind.

**Rejected: accepting both extensions during a transition.** There is nothing to transition — five
files in one repo, changed in one commit. A dual-path resolver would outlive the migration and
become the thing that keeps `.env` alive.

**Rejected: `.env.sh`** — and this one is measured, not assumed. A second fixture ran seven
candidate extensions through the same probe:

```
→ Read sub/cand.sh          → Read sub/cand.bash      → Read sub/cand.conf
→ Read sub/cand.strategy    → Read sub/cand.loop      → Read sub/cand.ini
! permission requested: read (sub/cand.env.sh); auto-rejecting     ← BLOCKED
```

So the guard matches `env` as a **dotted component anywhere in the name**, not merely the trailing
extension. Any name containing `.env.` is out, which rules out the whole family of
compromise names. `.conf` is confirmed clear in both fixtures.

## 5. The check that outlives the rename · [A — Approach]

Renaming five files fixes today. The gate also asserts that **no** file under `scripts/loops/`
carries an extension from a secret-bearing set (`env`, `envrc`, `pem`, `key`, `secret`,
`credentials`), so the next person adding a strategy cannot reintroduce the class by accident.
That assertion is worth more than the rename itself.


## 6. Two other gates name these files by path · [S — Scope]

A rename is not a local change when other gates address the renamed thing by path:

| gate | line | reference | what the rename alone does |
|---|---|---|---|
| `specs/20260828a-exec-container/verify.sh` | 24 | `STRAT=".../build-container.env"` | **goes red** — loud |
| `specs/20260825c-executor-binding/verify.sh` | 102 | `cat … build-codex.env 2>/dev/null \| wc -l` | **stays green, measuring less** — silent |

Both are updated here, and the second is the instructive one. Measured:

```
with build-codex.conf present (4 files):  348 lines
if the 4th is missing (silent drop):      333 lines
threshold: < 424 — BOTH pass
```

`AC-7` asserts the executor layer is smaller than the two loops it replaced. With its fourth
input renamed away, `cat` fails into `2>/dev/null`, the count simply drops, and the assertion
gets **easier** to satisfy. Nothing errors. The gate keeps reporting `AC-7:executor-layer-shrank`
while silently measuring three files instead of four. This is the **second** instance
today of a rename breaking a path-keyed guard: the date-prefix rename
(`20260827a-spec-manifest`'s `_PREDATING` list) silently turned a guard into a no-op that always
passes, which was worse — nothing errored, the gate simply got easier.

This is the **second** measured instance of a path change silently weakening a guard, after
`20260827a-spec-manifest`'s `_PREDATING` list became a no-op during the date-prefix rename, and
it is the same shape each time: a check addresses something by path, the path moves, and the
check degrades into a tautology rather than a failure.

The general rule: **a rename either breaks a path-keyed guard loudly or disarms it silently, and
the silent case is the dangerous one.** After any rename the question is not "does everything
still pass" but "does everything that passed before still have teeth". `2>/dev/null` on a path
that feeds a measurement is the specific smell — it converts a missing input into a smaller
number instead of an error.
