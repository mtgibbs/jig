#!/usr/bin/env bash
# T08 — the documentation.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
DOC="$ROOT/docs/per-task-gates.md"
TPL="$ROOT/specs/TEMPLATE.md"

if [ ! -r "$DOC" ]; then
  no "ac1: the layout, the two rules and the four outcomes are documented"
  no "ac2: TEMPLATE.md writes a new spec in this shape by default"
  gate_done
fi

miss=""
for t in 'assert.sh' 'tasks/' 'mutants' 'gate-selftest'; do
  grep -q -- "$t" "$DOC" || miss="$miss topic:$t"
done
for o in KILLED SURVIVED WRONG-REASON HUNG; do
  grep -qi -- "$o" "$DOC" || miss="$miss outcome:$o"
done
grep -qi 'pend'    "$DOC" || miss="$miss rule:no-pend"
grep -qi 'MUTANT:' "$DOC" || miss="$miss format:MUTANT"
grep -qi 'TARGET:' "$DOC" || miss="$miss format:TARGET"
[ -z "$miss" ] && ok "ac1: the layout, the two rules and the four outcomes are documented" \
               || no "ac1: the doc is not sufficient to write a gate against —$miss"

if [ ! -r "$TPL" ]; then
  no "ac2: TEMPLATE.md writes a new spec in this shape by default"
elif grep -q 'tasks/T' "$TPL" && grep -qi 'mutant' "$TPL"; then
  ok "ac2: TEMPLATE.md writes a new spec in this shape by default"
else
  no "ac2: TEMPLATE.md still describes only the monolithic gate — a new spec would default to the shape this arc replaced"
fi
gate_done
