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

# Parse mutants: extract MUTANT:, TARGET:, WHY: from comment lines
# Validates that each file has MUTANT: and TARGET: (fatal if missing)
MUTANT_DIR="$TASK_DIR/mutants"
# Parallel arrays, because T3 has to install what T2 parsed. Sorted, not raw find order:
# a corpus that measures interference between mutants depends on WHICH runs first, so the
# order has to be the same on every machine and every filesystem.
M_NAME=(); M_ID=(); M_TARGET=(); M_WHY=()
while IFS= read -r mutant_file; do
  [ -z "$mutant_file" ] && continue
  
  mutant_name="$(basename "$mutant_file")"
  mutant_mutant=""
  mutant_target=""
  mutant_why=""
  
  while IFS= read -r line || [ -n "$line" ]; do
    if echo "$line" | grep -q '^#[[:space:]]*MUTANT:[[:space:]]'; then
      mutant_mutant="$(echo "$line" | sed 's/^#[[:space:]]*MUTANT:[[:space:]]*//')"
    elif echo "$line" | grep -q '^#[[:space:]]*TARGET:[[:space:]]'; then
      mutant_target="$(echo "$line" | sed 's/^#[[:space:]]*TARGET:[[:space:]]*//')"
    elif echo "$line" | grep -q '^#[[:space:]]*WHY:[[:space:]]'; then
      mutant_why="$(echo "$line" | sed 's/^#[[:space:]]*WHY:[[:space:]]*//')"
    fi
  done < "$mutant_file"
  
  if [ -z "$mutant_mutant" ]; then
    echo "error: mutant file missing MUTANT: field: $mutant_name" >&2
    exit 1
  fi
  
  if [ -z "$mutant_target" ]; then
    echo "error: mutant file missing TARGET: field: $mutant_name" >&2
    exit 1
  fi

  M_NAME+=("$mutant_name"); M_ID+=("$mutant_mutant")
  M_TARGET+=("$mutant_target"); M_WHY+=("$mutant_why")
done <<< "$(find "$MUTANT_DIR" -type f 2>/dev/null | sort)"

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

# Carry the upstream baseline across into the fresh repo.
#
# The .git above is discarded on purpose, so mutants cannot reach real history — but a gate is
# entitled to compare behaviour against `origin/main`, and several do: it is how the "an
# unconfigured run is exactly the run it is today" assertions pin their control. Without this the
# workspace has no such ref, those assertions fail for an environmental reason, and every mutant
# aimed at any OTHER assertion comes back WRONG-REASON. A harness that cannot mutation-test the
# strongest assertion pattern in the repo pushes authors toward weaker ones.
#
# Best-effort: a repo with no origin/main simply does not get the ref, and the gate says so
# itself rather than being told a lie here.
git fetch -q "$CWD" 'refs/remotes/origin/main:refs/remotes/origin/main' 2>/dev/null || true

REPO_ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || echo "$CWD")"
TASK_REL="${TASK_DIR#$REPO_ROOT}"
TASK_PATH="$T/worktree$TASK_REL"
if [ ! -f "$TASK_PATH/verify.sh" ]; then
  echo "error: verify.sh not found at: $TASK_PATH" >&2
  exit 1
fi

# ── Install each mutant, run the gate BOUNDED, restore ──────────────────────────────────────
#
# The timeout is not defensive tidiness. A mutant can make the gate hang — that is a finding in
# its own right — and a tool that inherits the hang wedges the whole run while making the gate
# look like it works. Two states, two different reports: a gate that FAILED and a gate that
# never returned.
#
# Restore around every mutant, both before and after, so each is measured against a clean tree.
# Without it the second mutant runs against the first one's damage and the two become
# indistinguishable, which is the one thing this step exists to prevent.
GATE_TIMEOUT="${GATE_SELFTEST_TIMEOUT:-30}"

restore_target() {                      # restore_target <repo-relative-path>
  if [ -e "$CWD/$1" ]; then cp -a "$CWD/$1" "$T/worktree/$1" 2>/dev/null || true
  else rm -f "$T/worktree/$1" 2>/dev/null || true; fi
}

for i in "${!M_NAME[@]}"; do
  name="${M_NAME[$i]}"; tgt="${M_TARGET[$i]}"
  restore_target "$tgt"
  mkdir -p "$(dirname "$T/worktree/$tgt")" 2>/dev/null || true
  cp "$MUTANT_DIR/$name" "$T/worktree/$tgt"

  gate_out="$( cd "$T/worktree" && timeout "$GATE_TIMEOUT" bash "$TASK_PATH/verify.sh" 2>&1 )"
  gate_rc=$?
  restore_target "$tgt"

  printf '%s' "$gate_out" > "$T/gate-$i.out"
done

# ── T4: Analyze verdicts from gate outputs ───────────────────────────────────────────────────
KILLED=0; SURVIVOR=0; WRONG_REASON=0; HUNG=0

for i in "${!M_NAME[@]}"; do
  name="${M_NAME[$i]}"; id="${M_ID[$i]}"; tgt="${M_TARGET[$i]}"; why="${M_WHY[$i]}"
  
  gate_out="$(cat "$T/gate-$i.out")"
  
  if [ "$gate_rc" = 124 ]; then
    echo "$name: HUNG"
    HUNG=$((HUNG + 1))
  elif [ "$gate_rc" = 0 ]; then
    echo "$name: SURVIVOR — gate accepted the mutant (target=$tgt, why=$why)"
    SURVIVOR=$((SURVIVOR + 1))
  else
    # Gate exited non-zero — check if FAIL line contains the mutant's declared id
    if echo "$gate_out" | grep -q "FAIL.*$id"; then
      echo "$name: KILLED"
      KILLED=$((KILLED + 1))
    else
      # Name the assertions that DID fail. "not for ac7" tells the reader the mutant missed and
      # nothing about where it landed instead, which is the one fact needed to fix it — the same
      # gap that makes a gate say "it did not start" and burn three attempts. A mutant that trips
      # a neighbouring assertion is usually a mutant aimed at the wrong code path, and the
      # neighbour's name is what says so.
      echo "$name: WRONG-REASON — gate failed but not for $id (target=$tgt)"
      echo "$gate_out" | grep -E '^\s*FAIL' | sed 's/^/    instead: /' | head -4
      WRONG_REASON=$((WRONG_REASON + 1))
    fi
  fi
done

echo ""
echo "summary: killed=$KILLED survivor=$SURVIVOR wrong-reason=$WRONG_REASON hung=$HUNG"

if [ $SURVIVOR -gt 0 ] || [ $WRONG_REASON -gt 0 ] || [ $HUNG -gt 0 ]; then
  exit 1
fi

# ── T5: Static checks on the gate file itself ────────────────────────────────────────────────

# Extract all assertion IDs from ok/no calls in verify.sh
extract_assertion_ids() {
  python3 - "$1" << 'PY'
import sys
import re

with open(sys.argv[1], 'r') as f:
    content = f.read()

# Match ok("...id...") or no("...id...") patterns
# Look for patterns like ok "ac1: ..." or no "ac2: ..."
ids = set()
for match in re.finditer(r'\b(ok|no)\s+["\']([^"\']+)["\']', content):
    msg = match.group(2)
    # Extract assertion ID (e.g., "ac1" from "ac1: subject carries marker one")
    id_match = re.search(r'\b(ac\d+)\b', msg)
    if id_match:
        ids.add(id_match.group(1))
for id in ids:
    print(id)
PY
}

# Check for pend as a command (not in comments or strings)
check_pend_command() {
  python3 - "$1" << 'PY'
import sys
import re

with open(sys.argv[1], 'r') as f:
    lines = f.readlines()

for i, line in enumerate(lines, 1):
    # Remove comments (everything after # that's not inside a string)
    # Simple approach: find # not inside quotes
    code_part = line
    in_single = False
    in_double = False
    result = []
    for j, ch in enumerate(line):
        if ch == "'" and not in_double:
            in_single = not in_single
        elif ch == '"' and not in_single:
            in_double = not in_double
        elif ch == '#' and not in_single and not in_double:
            break
        result.append(ch)
    code_part = ''.join(result)
    
    # Check if 'pend' appears as a command (word boundary, not in string)
    # Match: pend(, pend ;, then pend, ; pend, || pend, && pend, etc.
    if re.search(r'\bpend\b', code_part):
        print(i)
        break
PY
}

# T5-1: Coverage check — every assertion id in the gate must be declared by at least one mutant
GATE_VERIFY_SH="$TASK_PATH/verify.sh"
GATE_IDS=$(extract_assertion_ids "$GATE_VERIFY_SH")

UNCOVERED=""
for id in $GATE_IDS; do
  found=0
  for mid in "${M_ID[@]}"; do
    if [ "$id" = "$mid" ]; then
      found=1
      break
    fi
  done
  if [ $found -eq 0 ]; then
    UNCOVERED="$UNCOVERED $id"
  fi
done

if [ -n "$UNCOVERED" ]; then
  echo "error: uncovered assertion IDs:$UNCOVERED" >&2
  exit 1
fi

# T5-2: pend ban check — fail if verify.sh contains 'pend' as a command
PEND_LINE=$(check_pend_command "$GATE_VERIFY_SH")
if [ -n "$PEND_LINE" ]; then
  echo "error: task gate contains 'pend' as a command at line $PEND_LINE" >&2
  exit 1
fi

exit 0
