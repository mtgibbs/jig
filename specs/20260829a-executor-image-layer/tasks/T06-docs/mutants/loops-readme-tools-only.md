# MUTANT: ac5
# TARGET: scripts/loops/README.md
# WHY: documents STRATEGY_TOOLS but never mentions the .harness search path. A strategy author
# WHY: reading only this file learns the new key and still believes a strategy can only live in
# WHY: the harness repo — which is the half of T2 that makes a consumer repo possible.
# Loop strategies — named bindings, not new machinery

A strategy is one `.conf` file: which phases run, and the operator-layer bindings they need.

    scripts/run-loop.sh <strategy> specs/<feature>

## The contract

A strategy file may ONLY:
- declare `STRATEGY_DESC` and `STRATEGY_PHASES` (space-separated, run in order)
- declare `STRATEGY_TOOLS` — executables the binding needs on PATH, preflighted with `command -v`
- export env knobs the loop scripts already accept

It may not define functions, add stopping logic, or invoke anything itself.

`STRATEGY_TOOLS` duplicates a fact the `exec-*.sh` already contains. That is accepted: inferring
it would mean parsing shell to find the executable a script invokes, which is worse.
