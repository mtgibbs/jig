# AGENTS.md — operating brief for an executor working ON Jig

You are a **focused coding executor** working one spec at a time inside the **Jig** repo —
the machinery that runs SDD loops for other repositories. Your context window is small: **rely on
the spec you are handed, not on loading the whole repo.**

This brief is for work on Jig *itself*. When Jig runs a loop in a consumer repo,
that repo supplies its own `AGENTS.md`.

## Non-negotiables

- **You have exactly the tools in your tool list — no improvised access.** Never hand-roll
  HTTP/JSON-RPC to reach a service, and never dig up a credential yourself. If a task needs a
  tool you do not have: **stop and say which tool is missing.**
- **Silence is failure.** Empty output from a silenced command (`curl -s`, `2>/dev/null`) means
  the call FAILED until proven otherwise. Check the exit code.
- **The gate decides done, never you.** `verify.sh` is the only voice that can say a task is
  complete. Do not edit a gate to make your work pass — that is the one unrecoverable move here.
- **Never commit.** The loop owns the index and the commit. Do not run `git add`, `git commit`,
  or `git stash`.

## Portability — this is Jig's most common defect

Jig is **authored on macOS and runs on Linux containers.** Both must work.

- **bash 3.2 is the floor.** No associative arrays, no `mapfile`, no `${x^^}`, no `readarray`.
  An empty array expanded under `set -u` is an error on 3.2 — that exact bug killed a retry guard.
- **`stat -f X || stat -c Y` IS BROKEN.** On Linux `stat -f` means *filesystem status*: it exits
  **0** and prints a block of filesystem info, so the `||` never fires and your variable fills
  with garbage. Put **GNU first** (`stat -c … || stat -f …`), and prefer `wc -c` for file size —
  POSIX, identical everywhere, no branch to get wrong.
- **No `timeout(1)`.** Stock macOS does not ship it. Use the `run_bounded` pattern already in
  `ralph-build.sh` / `ralph-judge.sh`.
- Watch for other BSD/GNU splits: `sed -i`, `date -v` vs `date -d`, `readlink -f`.

## Never interpolate into a foreign language

An unquoted heredoc means the **shell** expands the body before the other language sees it.

```bash
python3 - <<PY      # WRONG: shell expands $vars, $(cmd), and backticks INSIDE the Python
python3 - <<'PY'    # RIGHT: quoted delimiter, pass values via the environment or argv
```

This is not theoretical. A backtick inside a *comment* in a Python heredoc executed as a command
(`cost: command not found`), and a shell `null` reached Python as an undefined name. The same
defect class posted six live credentials to a chat room on 2026-08-02 when a message body
containing `$(export)` was expanded.

## Best-effort helpers stay best-effort

`ralph-log.sh`, `ralph-status.sh`, `ralph-bus.sh`, `loop-metrics.sh` are sourced or invoked around
the loop. A full disk, a missing `$HOME`, or a read-only mount must **never** fail the loop they
report on. Every write guarded; every call `|| true`. Equally: a helper that silently does nothing
is a helper nobody notices is broken — say so on stderr once, then continue.

## Evidence rules

- `null` and `0` are **different values**. `0` says measured-and-it-was-zero; `null` says not
  measurable from what was available. Never collapse one into the other.
- Every classification **cites the literal marker it matched**. A verdict that cannot cite is
  `unknown`, never a guess.
- The spec slug is a **directory level**, never part of an artefact's leaf name.

## Gates

Read `specs/TEMPLATE.md` §11 before writing one. Three verdicts: `PASS` · `FAIL` (the artifact
exists and is wrong) · `pend` (it does not exist yet); `STRICT=1` promotes every pend. Presence-
gate on the **artifact**, never on a task number, so each check arms itself as its target appears.

`specs/amendments.md` — **"Gates must prove they can fail"**: a check must be shown to go RED
without the change it verifies. A check that has never failed proves presence, not correctness.
And a check that fails for the *wrong reason* is worse than one that never fails, because it
teaches the reader to discount it.
