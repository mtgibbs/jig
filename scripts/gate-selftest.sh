#!/usr/bin/env bash
# scripts/gate-selftest.sh — run a per-task gate in a hermetic temp copy.
#
# Usage: scripts/gate-selftest.sh <task-dir>
#   task-dir: path to directory containing verify.sh and mutants/ subdir
#
# The tool:
#   1. Validates arguments and required artifacts (4 distinct error messages)
#   2. Creates a hermetic temp copy of the repo
#   3. Runs the gate inside the temp copy
#   4. Cleans up on exit (trap EXIT)
set -uo pipefail

# ARG GUARD — if $1 is missing, exit with distinct message
if [ $# -ne 1 ]; then
  echo "Usage: $0 <task-dir>" >&2
  exit 1
fi

TASK_DIR="$1"

# Normalize TASK_DIR: if not absolute, prepend cwd
if [[ "$TASK_DIR" != /* ]]; then
  TASK_DIR="$(pwd)/$TASK_DIR"
fi

# Check if directory exists
if [ ! -d "$TASK_DIR" ]; then
  echo "error: task directory does not exist: $TASK_DIR" >&2
  exit 1
fi

# Check for verify.sh
if [ ! -f "$TASK_DIR/verify.sh" ]; then
  echo "error: verify.sh not found in: $TASK_DIR" >&2
  exit 1
fi

# Check for mutants/ directory
if [ ! -d "$TASK_DIR/mutants" ]; then
  echo "error: mutants/ directory not found in: $TASK_DIR" >&2
  exit 1
fi

# Create temp directory for hermetic workspace
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# Copy current directory (the repo we're inside) into temp dir
CWD="$(pwd)"
cp -R "$CWD" "$T/worktree"

# Remove .git from copy and re-init a fresh repo
rm -rf "$T/worktree/.git"
cd "$T/worktree"
git init -q .
git config user.email t@t
git config user.name t
git add -A
git commit -qm 'init'

# Run the gate from inside the temp copy
# TASK_DIR is absolute (repo root + relative path), strip repo root prefix
REPO_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")"
TASK_REL="${TASK_DIR#$REPO_ROOT}"
TASK_PATH="$T/worktree$TASK_REL"
if [ -f "$TASK_PATH/verify.sh" ]; then
  bash "$TASK_PATH/verify.sh"
else
  echo "error: verify.sh not found at: $TASK_PATH" >&2
  exit 1
fi

exit 0
