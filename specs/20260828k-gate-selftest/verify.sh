#!/usr/bin/env bash
# Convergence gate for 20260828k. Runs ONLY at the end (ralph-build.sh adds it after the task
# gates when a spec carries tasks/), so it holds end-state and integration assertions and
# nothing that belongs to a single task. No `pend`: by the time this runs, everything is built.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
ST="$ROOT/scripts/gate-selftest.sh"
G="$ROOT/specs/20260828g-dispatch-core"

# AC-END-1 — the tool leaves the tree byte-identical. Asserted here and not in a task gate
# because it is a property of the finished tool over REAL corpora, not of one task's change.
if [ ! -x "$ST" ]; then
  no "end-1: gate-selftest.sh does not exist"
else
  before="$(git -C "$ROOT" status --porcelain | sort)"
  for d in "$G"/tasks/T0[1-5]-*; do
    [ -d "$d/mutants" ] || continue
    ( cd "$ROOT" && timeout 300 bash "$ST" "${d#"$ROOT"/}" ) >/dev/null 2>&1
  done
  after="$(git -C "$ROOT" status --porcelain | sort)"
  if [ "$before" = "$after" ]; then
    ok "end-1: a full self-test run leaves the working tree byte-identical"
  else
    no "end-1: the tree changed across a self-test run: $(diff <(printf '%s' "$before") <(printf '%s' "$after") | head -5 | tr '\n' ' ')"
  fi
fi

# AC-END-2 — the reference corpus is clean, end to end.
bad=""
for d in "$G"/tasks/T0[1-5]-*; do
  if [ ! -d "$d/mutants" ]; then bad="$bad $(basename "$d"):no-corpus"; continue; fi
  out="$( cd "$ROOT" && timeout 300 bash "$ST" "${d#"$ROOT"/}" 2>&1 )"; rc=$?
  [ "$rc" = 0 ] || bad="$bad $(basename "$d"):$(printf '%s' "$out" | grep -iE 'surviv|wrong|uncovered|pend' | head -1 | cut -c1-60)"
done
[ -z "$bad" ] && ok "end-2: every 20260828g mutant is killed and every id is covered" \
              || no "end-2: the reference corpus is not clean —$bad"

# AC-END-3 — the migrated gates still agree with the merged implementation.
redd=""
for d in "$G"/tasks/T0[1-5]-*; do
  [ -f "$d/verify.sh" ] || { redd="$redd $(basename "$d"):absent"; continue; }
  ( cd "$ROOT" && timeout 120 bash "$d/verify.sh" >/dev/null 2>&1 ) || redd="$redd $(basename "$d")"
done
[ -z "$redd" ] && ok "end-3: every migrated task gate passes against the merged implementation" \
               || no "end-3: a migrated task gate is red on the known-good tree —$redd"

# The point of the whole arc: the old monolith no longer carries per-task assertions.
if [ -f "$G/verify.sh" ]; then
  _pends="$(grep -c '\bpend\b' "$G/verify.sh" 2>/dev/null || echo 0)"
  if [ "$_pends" -le 4 ]; then
    ok "end-4: the spec-level gate is integration-only ($_pends pend guards, was 17)"
  else
    no "end-4: the spec-level gate still carries $_pends pend guards — per-task assertions were not moved out, which is the migration this spec exists to do"
  fi
fi
gate_done
