# MUTANT: ac19
# TARGET: scripts/run-loop.sh
# WHY: defaults the board on, so every run gets one without asking. Friendlier, and it makes
# WHY: the unconfigured path the configured one for everybody — every run now reports somewhere,
# WHY: which is precisely the thing an operator did not opt into.
#!/usr/bin/env bash
# run-loop.sh — run a named loop strategy against a spec.
#
#   scripts/run-loop.sh <strategy> specs/<feature>
#   scripts/run-loop.sh --board <strategy> specs/<feature>   # + the local board
#   scripts/run-loop.sh --list
#
# A strategy is scripts/loops/<name>.conf: STRATEGY_PHASES plus operator-layer
# bindings (see scripts/loops/README.md for the contract). This script only
# sequences existing loops — it adds no stopping logic and no cleverness.
# Fail-closed: any phase's nonzero exit stops the run with that exit code.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOPS_DIR="$SCRIPT_DIR/loops"

# --board: bring the local board up and report this run to it (20260831s). Parsed as a LEADING
# flag and shifted away, so everything below — including --list and the two positional
# arguments — sees exactly the argv it always saw.
#
# OPT-IN, deliberately. With HARNESS_REPORT_URL unset the loop is line-for-line the run it is
# today, and that is a contract two specs' gates assert (20260828m, 20260828o). A run-loop that
# started a board by default would make the unconfigured path the configured one for everybody.
BOARD=1
if [ "${1:-}" = "--board" ]; then
  BOARD=1
  shift
fi

if [ "${1:-}" = "--list" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  HARNESS_DIR="$ROOT/.harness/loops"
  # A space-delimited string probed with `case`, NOT `declare -A`: macOS ships bash 3.2,
  # where associative arrays are a hard error and --list died before listing anything
  # (issue #106). Same idiom, same reason, as agent-bus-bootstrap.
  SEEN=" "
  LIST_OUT=""

  for dir in "$HARNESS_DIR" "$LOOPS_DIR"; do
    [ -d "$dir" ] || continue
    loc="$(basename "$(dirname "$dir")")"
    for f in "$dir"/*.conf; do
      [ -f "$f" ] || continue
      name="$(basename "$f" .conf)"
      case "$SEEN" in *" $name "*) continue ;; esac
      SEEN="$SEEN$name "
      desc="$(sed -n 's/^STRATEGY_DESC="\(.*\)"$/\1/p' "$f" | head -1)"
      LIST_OUT="$LIST_OUT$loc:$name:$desc
"
    done
  done

  if [ -z "$LIST_OUT" ]; then
    echo "No strategies found in $HARNESS_DIR or $LOOPS_DIR"
    exit 0
  fi

  echo "$LIST_OUT" | while IFS=: read -r loc name desc; do
    [ -z "$name" ] && continue
    if [ "$loc" = ".harness" ]; then
      printf '  %-20s [%s] %s\n' "$name" "consumer" "$desc"
    else
      printf '  %-20s [%s] %s\n' "$name" "built-in" "$desc"
    fi
  done
  exit 0
fi

STRATEGY="${1:?usage: run-loop.sh <strategy> <spec-dir>  (or --list)}"
SPEC_DIR="${2:?usage: run-loop.sh <strategy> <spec-dir>}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HARNESS_DIR="$ROOT/.harness/loops"

if [ -d "$HARNESS_DIR" ] && [ -f "$HARNESS_DIR/$STRATEGY.conf" ]; then
  ENV_FILE="$HARNESS_DIR/$STRATEGY.conf"
  export HARNESS_REPO_ROOT="$ROOT"
elif [ -f "$LOOPS_DIR/$STRATEGY.conf" ]; then
  ENV_FILE="$LOOPS_DIR/$STRATEGY.conf"
else
  echo "run-loop: unknown strategy '$STRATEGY' (searched $HARNESS_DIR and $LOOPS_DIR) — try --list" >&2
  exit 1
fi

# Preflight, all fatal: known strategy, real spec, and never on main —
# the constitution's worktree rule applies to strategies same as hand runs.
[ -f "$ENV_FILE" ] || { echo "run-loop: unknown strategy '$STRATEGY' — try --list" >&2; exit 1; }
[ -f "$SPEC_DIR/spec.md" ] && [ -f "$SPEC_DIR/verify.sh" ] \
  || { echo "run-loop: $SPEC_DIR needs spec.md + verify.sh" >&2; exit 1; }
branch="$(git branch --show-current 2>/dev/null || true)"
[ -n "$branch" ] && [ "$branch" != "main" ] \
  || { echo "run-loop: refuse to run on '$branch' — use a worktree on a throwaway branch" >&2; exit 1; }

# shellcheck source=/dev/null
. "$ENV_FILE"
: "${STRATEGY_PHASES:?$ENV_FILE must set STRATEGY_PHASES}"

# Required environment, declared per strategy: STRATEGY_ENV_REQUIRED="VAR1 VAR2".
# Executor bindings take credentials from the environment BY CONTRACT (20260825c —
# acquisition is the operator's job), so a forgotten export must fail HERE, named,
# before any phase — not twenty minutes in as a mid-run auth abort (notes-from-hearing
# run 1, 2026-08-31). Names only; values are never read into output.
_env_missing=""
for _v in ${STRATEGY_ENV_REQUIRED:-}; do
  eval "_val=\${$_v:-}"
  [ -n "$_val" ] || _env_missing="$_env_missing $_v"
done
if [ -n "$_env_missing" ]; then
  echo "run-loop: strategy '$STRATEGY' requires environment not set:$_env_missing — export it and relaunch (the executor binding reads it; this script never does)" >&2
  exit 3
fi

# Preflight: validate tools and MCP declared in spec and strategy
FIELD="$SCRIPT_DIR/spec-field.sh"
misses=""
misses_strategy=""

# Collect spec-declared tools
if [ -f "$SPEC_DIR/spec.md" ]; then
  if bash "$FIELD" "$SPEC_DIR/spec.md" --list >/dev/null 2>&1; then
    tools_out="$(bash "$FIELD" "$SPEC_DIR/spec.md" Tools 2>/dev/null || true)"
    if [ -n "$tools_out" ]; then
      while IFS= read -r tool || [ -n "$tool" ]; do
        tool="$(echo "$tool" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$tool" ] && continue
        if [ "$tool" != "none" ]; then
          if ! command -v "$tool" >/dev/null 2>&1; then
            misses="$misses $tool"
            misses_strategy="$misses_strategy (spec)"
          fi
        fi
      done <<< "$tools_out"
    fi
  fi
  
  # Check MCP config file if declared
  mcp_out="$(bash "$FIELD" "$SPEC_DIR/spec.md" MCP 2>/dev/null || true)"
  if [ -n "$mcp_out" ]; then
    while IFS= read -r mcp || [ -n "$mcp" ]; do
      mcp="$(echo "$mcp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -z "$mcp" ] && continue
      if [ "$mcp" != "none" ]; then
        # ONE derivation, both cases. An unset RALPH_EXEC_CMD means ralph-build.sh will apply
        # its own default binding, so the fallback derives the config name from that same
        # default rather than restating a filename — a second literal is a second thing to miss
        # at the next rename, and 20260827a AC-11 exists precisely because the first version of
        # this hardcoded one. The name follows the binding's basename, so a codex or container
        # binding resolves its own config and not somebody else's.
        cfg_name="$(basename "${RALPH_EXEC_CMD:-$SCRIPT_DIR/exec-opencode.sh}" .sh).json"
        if [ ! -f "$cfg_name" ]; then
          misses="$misses $cfg_name"
          misses_strategy="$misses_strategy (spec)"
        fi
      fi
    done <<< "$mcp_out"
  fi
fi

# Collect strategy-declared tools
if [ -n "${STRATEGY_TOOLS:-}" ]; then
  for tool in $STRATEGY_TOOLS; do
    tool="$(echo "$tool" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$tool" ] && continue
    if [ "$tool" != "none" ]; then
      if ! command -v "$tool" >/dev/null 2>&1; then
        misses="$misses $tool"
        misses_strategy="$misses_strategy ($STRATEGY)"
      fi
    fi
  done
fi

if [ -n "$misses" ]; then
  echo "run-loop: missing tools/config$misses$misses_strategy declared in $SPEC_DIR/spec.md and/or $ENV_FILE — container needs attention, not another retry" >&2
  exit 3
fi

echo "strategy: $STRATEGY — ${STRATEGY_DESC:-}"
echo "spec:     $SPEC_DIR   branch: $branch"
echo "permissions: recorded, not verified"

# The board goes up BEFORE the first phase, and its URL is printed where the run's other
# facts are — an operator watching a loop should not have to work out where to point a
# browser. A board that cannot start is fatal: it was asked for explicitly.
if [ "$BOARD" = 1 ]; then
  bash "$SCRIPT_DIR/jig-board.sh" start \
    || { echo "run-loop: --board was requested and the board did not start" >&2; exit 3; }
  HARNESS_REPORT_URL="$(bash "$SCRIPT_DIR/jig-board.sh" url)"
  export HARNESS_REPORT_URL
  echo "board:    $HARNESS_REPORT_URL"
fi

for phase in $STRATEGY_PHASES; do
  echo
  echo "── phase: $phase ─────────────────────────────"
  case "$phase" in
    build)
      [ -f "$SPEC_DIR/tasks.txt" ] || { echo "run-loop: build phase needs $SPEC_DIR/tasks.txt" >&2; exit 1; }
      bash "${BUILD_CMD:-$SCRIPT_DIR/ralph-build.sh}" "$SPEC_DIR" ;;
    judge)
      bash "$SCRIPT_DIR/ralph-judge.sh" "$SPEC_DIR" ;;
    *)
      echo "run-loop: unknown phase '$phase' in $ENV_FILE — phases are: build judge" >&2
      exit 1 ;;
  esac
  rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "run-loop: phase '$phase' exited $rc — stopping (fail-closed)" >&2
    exit "$rc"
  fi
done

echo
echo "run-loop: all phases complete ($STRATEGY_PHASES)"
