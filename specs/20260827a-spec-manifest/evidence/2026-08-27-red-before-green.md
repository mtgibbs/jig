# Red before green — and green proven reachable — for `specs/20260827a-spec-manifest`

Run against `8fa87e3` with **no task built**, from `~/dev/harness-manifest`.

```
$ bash specs/20260827a-spec-manifest/verify.sh   ; echo $?      → 0   (14 pend · 5 PASS · 0 FAIL)
$ STRICT=1 bash specs/20260827a-spec-manifest/verify.sh; echo $? → 1
```

## Both directions, because red-before-green is only half the proof

A gate that cannot go red is decoration. A gate that cannot go **green** is worse: the loop
grinds every retry against an impossible target and stops for a human having burned the budget
on a defect in the gate. So each stage was validated by building a throwaway reference
implementation, running the gate, and then deleting it.

| stage | reference built | result |
|---|---|---|
| T1 `spec-field.sh` | ~20-line awk/sed reader | **7 of 7 T1 checks PASS** |
| T3 `run-loop.sh` preflight | ~18 lines inserted before the strategy source | **ac6, ac7, ac8, ac9, ac11, ac12, ac13 + both controls PASS** |

`scripts/run-loop.sh` was restored from a pre-edit copy and `scripts/spec-field.sh` deleted;
`git status` shows only `specs/20260827a-spec-manifest/` untracked.

## Three defects the reachability probe found — in the gate, not the work

**1. The probe was inert.** The first draft ran `run-loop.sh` with `LOOPS_DIR="$T/loops"` and a
scratch `gateprobe.env`. But `LOOPS_DIR` is **hardcoded at `run-loop.sh:14`** and is not read from
the environment, so the scratch strategy never loaded. Every behavioural check would have run
against an unknown-strategy exit and passed while measuring nothing — `TEMPLATE.md` §11
**Trap A-prime**, a scope that was written and was inert.

Fixed by using the real `build-converge` strategy and omitting `tasks.txt` from the fixtures, so
a clean preflight stops at the build phase's own missing-tasks check (`run-loop.sh:54`, exit 1)
without ever starting an executor. The gate now asserts that discrimination **before** trusting
any comparison:

```
PASS  control: the probe reaches the build phase on a clean preflight (rc=1, no executor run)
```

**2. `ac10` had a pend arm and no assertion.** `AC-10` (a declared `MCP:` requires the executor's
config) was pended when the preflight was absent and **never checked when it was present** — so
T3 could omit the MCP check entirely and the gate would report green. A check-shaped hole reads
exactly like a check.

The assertion added for it cannot hardcode `opencode.json`, because `AC-11` forbids the
*preflight* from doing so. It therefore **learns the filename from the error message** — which
`AC-10` requires the preflight to print anyway — then creates that file and asserts the rejection
lifts. Binding-agnostic, and it makes the naming requirement load-bearing rather than cosmetic.

**3. A gate message executed a command.** The message

```bash
no "... — `while read` drops it ..."
```

used backticks inside a **double-quoted** string, so the shell ran `while read` as a command
substitution and the rendered output read `— drops it`. Harmless here; the same defect class
posted six live credentials to a chat room on 2026-08-02. `AGENTS.md` names it, and it still
happened while writing a gate for a spec that cites `AGENTS.md`.

## Controls that must be asserted to move (Trap B)

| control | proves |
|---|---|
| `Tools: sh` (certainly present) does **not** exit 3 | ac6 discriminates; a preflight that rejects everything also produces exit 3 |
| an undeclared fixture reaches the build phase (rc=1) | the probe can tell "preflight passed" from "preflight rejected" at all |
| creating the named config lifts the ac10 rejection | ac10 checks the *config*, not merely the presence of an `MCP:` key |
| `--list` output contains both `Tools` and `Permissions` | the reader enumerates rather than matching one hardcoded key |
| the reader's last value carries a trailing newline | a `while`-read consumer keeps it — and T3's preflight is exactly such a consumer |

That last one was **found by the reference implementation failing it.** The throwaway reader
ended with `printf '%s'`, dropping the final newline; a preflight looping over its output would
have silently skipped the last declared tool. The check exists because the probe produced the bug.

## The self-referential fixture

`AC-3`/`AC-14` require that a declaration inside a fenced code block below the first `---` is
prose, not a declaration. **This spec's own `spec.md` is a live instance:** its header declares
`Tools: git, sed`, and its §3.1 shows `Tools: git, jq, swift` inside a fence. The gate reads the
real file and asserts `jq` and `swift` are absent from the result, so a whole-file parser fails
its own spec. A fixture built for the purpose exists too — the live one alone would evaporate
the first time §3.1 was edited.
