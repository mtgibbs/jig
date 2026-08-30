# Loop strategies — named bindings, not new machinery

A strategy is one `.env` file: which phases run, and the operator-layer bindings
they need. The loops themselves (`ralph-build.sh`, `ralph-judge.sh`) do not change —
per the judge-loop spec §3, command bindings live at the operator layer, and a
strategy file IS that layer, written down and named.

    scripts/run-loop.sh <strategy> specs/<feature>

Run from a git worktree on a throwaway branch (constitution: worktree rule), same
as invoking the loops by hand.

## The contract

A strategy file may ONLY:
- declare `STRATEGY_DESC`, `STRATEGY_PHASES`, and `STRATEGY_TOOLS` (space-separated, run in order)
- export env knobs the loop scripts already accept

`STRATEGY_TOOLS` is a **declaration**, not new machinery: each name is checked with `command -v`
and an absent one stops the run at preflight with exit 3, before any work starts. It joins the
same accumulation that reports a spec's own missing `Tools`, so a spec miss and a strategy miss
produce ONE message listing both and ONE exit — not two messages and two exit codes for one class
of fault. The message names the missing executable **and** the strategy that declared it, because
"codex not found" on its own sends the reader to the spec header, which is the wrong file. A conf
that declares no tools behaves exactly as it did before the key existed.

Known and accepted: a strategy that declares a tool is usually also the strategy that binds it, so
the executable is named twice — once in `STRATEGY_TOOLS` and once in the binding it exports. OQ4
closed this as acceptable duplication rather than deriving one from the other, because deriving it
would mean parsing the binding.

## Where a strategy is resolved from

Two search paths, first match wins:

1. `$HARNESS_REPO_ROOT/.harness/loops/<name>.conf` — the **worked repo's** own strategies
2. `$SCRIPT_DIR/loops/<name>.conf` — the built-ins that ship with the harness

So a consumer repo can add strategies **and** shadow a built-in of the same name without forking
the harness. `--list` shows both locations and marks which is which, and it does not list a
built-in that a consumer conf shadows — showing both names would tell the reader the opposite of
what will actually run. A name found in neither is an error naming **both** paths that were
searched.

`HARNESS_REPO_ROOT` — the git toplevel of the repo being worked on — is exported **before** the
conf is sourced, so a conf can use it. It cannot use `$ROOT`: `ralph-build.sh` is what exports
`ROOT`, and it has not run yet at that point. That ordering is an acceptance criterion rather than
an implementation detail, because it is the first thing a consumer conf would hit.

A repo with no `.harness/` directory and no `HARNESS_HOME` set is not misconfigured — it is every
repo that exists today, and it resolves the built-ins exactly as it always has.

Sourcing a conf from the worked repo executes shell from that repo. That is not a new hole: the
loop already runs that repo's `verify.sh` and already gives an agent write access to its tree.

It may not define functions, add stopping logic, or invoke anything itself.
New behavior belongs in a loop script, behind its own spec and gate. This keeps
"add a strategy" reviewable at a glance: if a strategy PR touches anything
outside `scripts/loops/`, it is not a strategy PR.

## Current strategies → Loop Library taxonomy

| File | Phases | Library pattern |
|---|---|---|
| `build-converge.conf` | build | Generate-Verify-Refine (deterministic gate, bounded change, fresh context per task) |
| `judge-refine.conf` | judge | Evaluator/Judge (cross-family: Codex judges, qwen executes, gate arbitrates) |
| `build-then-judge.conf` | build judge | the full "basic → evaluator/judge → convergence" modern path |

Comparing strategies on one spec = one worktree per strategy, same spec dir,
diff the branches. The judge phase's `ledger.jsonl` + `report.json` and the
build phase's commit trail are the comparable outputs.

Amendment "Gates must prove they can fail" applies to every strategy: no phase
combination is a substitute for a verify.sh that goes red without the work.
