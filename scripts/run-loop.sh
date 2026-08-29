#!/usr/bin/env bash
# run-loop.sh — run a named loop strategy against a spec.
#
#   scripts/run-loop.sh <strategy> specs/<feature>
#   scripts/run-loop.sh --list
#
# A strategy is scripts/loops/<name>.conf: STRATEGY_PHASES plus operator-layer
# bindings (see scripts/loops/README.md for the contract). This script only
# sequences existing loops — it adds no stopping logic and no cleverness.
# Fail-closed: any phase's nonzero exit stops the run with that exit code.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOOPS_DIR="$SCRIPT_DIR/loops"

if [ "${1:-}" = "--list" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
  HARNESS_DIR="$ROOT/.harness/loops"
  declare -A SEEN
  LIST_OUT=""

  for dir in "$HARNESS_DIR" "$LOOPS_DIR"; do
    [ -d "$dir" ] || continue
    loc="$(basename "$(dirname "$dir")")"
    for f in "$dir"/*.conf; do
      [ -f "$f" ] || continue
      name="$(basename "$f" .conf)"
      [ -n "${SEEN[$name]:-}" ] && continue
      SEEN[$name]=1
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

# Preflight: validate tools and MCP declared in spec
if [ -f "$SPEC_DIR/spec.md" ]; then
  FIELD="$SCRIPT_DIR/spec-field.sh"
  
  # Collect all missing tools
  misses=""
  if bash "$FIELD" "$SPEC_DIR/spec.md" --list >/dev/null 2>&1; then
    tools_out="$(bash "$FIELD" "$SPEC_DIR/spec.md" Tools 2>/dev/null || true)"
    if [ -n "$tools_out" ]; then
      while IFS= read -r tool || [ -n "$tool" ]; do
        tool="$(echo "$tool" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        [ -z "$tool" ] && continue
        if [ "$tool" != "none" ]; then
          if ! command -v "$tool" >/dev/null 2>&1; then
            misses="$misses $tool"
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
        if [ -n "${RALPH_EXEC_CMD:-}" ]; then
          cfg_name="$(basename "$RALPH_EXEC_CMD" .sh).json"
          if [ ! -f "$cfg_name" ]; then
            misses="$misses $cfg_name"
          fi
        else
          misses="$misses exec-qwen.json"
        fi
      fi
    done <<< "$mcp_out"
  fi
  
  if [ -n "$misses" ]; then
    echo "run-loop: missing tools/config$misses declared in $SPEC_DIR/spec.md — container needs attention, not another retry" >&2
    exit 3
  fi
fi

# shellcheck source=/dev/null
. "$ENV_FILE"
: "${STRATEGY_PHASES:?$ENV_FILE must set STRATEGY_PHASES}"

echo "strategy: $STRATEGY — ${STRATEGY_DESC:-}"
echo "spec:     $SPEC_DIR   branch: $branch"
echo "permissions: recorded, not verified"

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
