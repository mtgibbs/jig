#!/usr/bin/env bash
# T07 — the mutant corpus for 20260828g, checked with the tool this spec builds.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
G="$ROOT/specs/20260828g-dispatch-core"
ST="$ROOT/scripts/gate-selftest.sh"

have=0
for d in "$G"/tasks/T0[1-5]-*; do [ -d "$d/mutants" ] && have=$((have+1)); done
if [ ! -x "$ST" ] || [ "$have" = 0 ]; then
  no "ac1: every task directory carries a mutant corpus"
  no "ac2: self-test reports every mutant killed and every id covered"
  gate_done
fi

# ac1
miss=""
for i in 1 2 3 4 5; do
  d="$(ls -d "$G"/tasks/T0"$i"-* 2>/dev/null | head -1)"
  [ -n "$d" ] || { miss="$miss T0$i-absent"; continue; }
  n="$(ls -A "$d/mutants" 2>/dev/null | wc -l)"
  [ "$n" -gt 0 ] || miss="$miss T0$i-empty"
done
[ -z "$miss" ] && ok "ac1: every task directory carries a mutant corpus" \
               || no "ac1: missing or empty mutant corpus —$miss"

# ac2 — BOUNDED per task dir. A corpus edited to agree with its gates proves nothing, so this
# runs the real tool rather than inspecting the files.
bad=""
for d in "$G"/tasks/T0[1-5]-*; do
  [ -d "$d/mutants" ] || continue
  rel="${d#"$ROOT"/}"
  out="$( cd "$ROOT" && bound 300 bash "$ST" "$rel" 2>&1 )"; rc=$?
  if [ "$rc" = 124 ]; then bad="$bad $(basename "$d"):hung"
  elif [ "$rc" != 0 ]; then
    bad="$bad $(basename "$d"):$(printf '%s' "$out" | grep -iE 'surviv|wrong|uncovered|pend' | head -1 | cut -c1-70)"
  fi
done
[ -z "$bad" ] && ok "ac2: self-test reports every mutant killed and every id covered" \
              || no "ac2: self-test is not clean —$bad"
gate_done
