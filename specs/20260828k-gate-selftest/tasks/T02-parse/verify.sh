#!/usr/bin/env bash
# T02 — mutant header parsing.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
. "$ROOT/specs/20260828k-gate-selftest/lib/fixtures.sh"

[ -x "$ST" ] || { no "ac1: a mutant with no MUTANT: field fails the run, naming the file"
                  no "ac2: a mutant with no TARGET: field fails the run, naming the file"
                  no "ac3: the three fields are accepted in any order, among other comments"
                  gate_done; }

# ac1 — a mutant with no declared assertion. NEVER a skip: a silently skipped mutant is an
# assertion nobody is checking, which is the exact state this tool exists to detect.
mkrepo "$T/a"
mutant "$T/a" ac1-drop.txt "$GOOD_MUTANT"
mutant "$T/a" undeclared.txt '# TARGET: subject.txt
# WHY: no MUTANT field, so nothing says which assertion this covers.
MARKER_TWO
'
runst "$T/a"
if [ "$RC" = 0 ]; then
  no "ac1: a mutant with no MUTANT: field was accepted — a skipped mutant is an unchecked assertion"
elif ! grep -q 'undeclared' "$T/st.out"; then
  no "ac1: the run failed but never named the offending file. Tool said: $(stout)"
else
  ok "ac1: a mutant with no MUTANT: field fails the run, naming the file"
fi

# ac2 — no TARGET means nothing says what it replaces.
mkrepo "$T/b"
mutant "$T/b" ac1-drop.txt "$GOOD_MUTANT"
mutant "$T/b" notarget.txt '# MUTANT: ac1
# WHY: no TARGET field, so nothing says what this replaces.
MARKER_TWO
'
runst "$T/b"
if [ "$RC" = 0 ]; then
  no "ac2: a mutant with no TARGET: field was accepted"
elif ! grep -q 'notarget' "$T/st.out"; then
  no "ac2: the run failed but never named the offending file. Tool said: $(stout)"
else
  ok "ac2: a mutant with no TARGET: field fails the run, naming the file"
fi

# ac3 — order must not matter, and unrelated comments must not break parsing. Functionally the
# same defect as GOOD_MUTANT, so this stays a clean run at every later task too.
mkrepo "$T/c"
mutant "$T/c" reordered.txt '#!/usr/bin/env python3
# unrelated leading comment
# WHY: drops marker one, so ac1 must fail.
# TARGET: subject.txt
# another unrelated comment
# MUTANT: ac1
MARKER_TWO
'
runst "$T/c"
if [ "$RC" = 124 ]; then
  no "ac3: the tool did not return within 90s"
elif [ "$RC" != 0 ]; then
  no "ac3: a well-formed mutant with reordered fields was rejected (exit $RC). Tool said: $(stout)"
else
  ok "ac3: the three fields are accepted in any order, among other comments"
fi
gate_done
