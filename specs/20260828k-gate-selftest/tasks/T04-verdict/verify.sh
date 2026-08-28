#!/usr/bin/env bash
# T04 — the two-part verdict, the survivor headline, and the exit contract.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
. "$ROOT/specs/20260828k-gate-selftest/lib/fixtures.sh"

AC2='grep -q MARKER_TWO subject.txt && ok "ac2: subject carries marker two" || no "ac2: subject carries marker two"'

[ -x "$ST" ] || { no "ac1: a killed mutant is reported killed and the run passes"
                  no "ac2: a mutant the gate accepts is a named survivor"
                  no "ac3: a mutant that fails for another reason is not counted as a kill"
                  no "ac4: the run ends with a summary counting each outcome"
                  gate_done; }

# ac1/ac4 — the clean case.
mkrepo "$T/a"
mutant "$T/a" ac1-drop.txt "$GOOD_MUTANT"
runst "$T/a"
if [ "$RC" != 0 ]; then
  no "ac1: an all-good corpus exited $RC. Tool said: $(stout)"
elif ! grep -qi 'kill' "$T/st.out"; then
  no "ac1: a mutant the gate rejected was not reported as killed. Tool said: $(stout)"
else
  ok "ac1: a killed mutant is reported killed and the run passes"
fi
if grep -qiE 'killed[^0-9]*[0-9]|[0-9][^a-z]*killed' "$T/st.out"; then
  ok "ac4: the run ends with a summary counting each outcome"
else
  no "ac4: no summary line counting outcomes. Tool said: $(stout)"
fi

# ac2 — the headline failure. A mutant the gate ACCEPTED means the assertion cannot detect its
# own defect, and the reader must not be able to miss it.
mkrepo "$T/b"
mutant "$T/b" survivor.txt '# MUTANT: ac1
# TARGET: subject.txt
# WHY: claims ac1 but leaves the marker, so the gate should not kill it.
MARKER_ONE
MARKER_TWO
'
runst "$T/b"
if [ "$RC" = 0 ]; then
  no "ac2: a mutant the gate ACCEPTED was reported as a pass — a survivor is this tool's headline failure"
elif ! grep -qi 'surviv' "$T/st.out"; then
  no "ac2: the run failed but never used the word survivor. Tool said: $(stout)"
elif ! grep -q 'survivor.txt' "$T/st.out"; then
  no "ac2: a survivor was reported without naming the mutant file. Tool said: $(stout)"
elif ! grep -qi 'leaves the marker' "$T/st.out"; then
  no "ac2: a survivor was reported without its WHY: text — the reader cannot tell what the assertion failed to notice. Tool said: $(stout)"
else
  ok "ac2: a mutant the gate accepts is a named survivor"
fi

# ac3 — the two-part verdict. Declares ac2, actually breaks ac1. Counting this as a kill leaves
# ac2 unexercised while the corpus claims otherwise; it happened twice by hand on 20260828j.
mkrepo "$T/c" "$AC2"
mutant "$T/c" ac1-drop.txt "$GOOD_MUTANT"
mutant "$T/c" wrong-reason.txt '# MUTANT: ac2
# TARGET: subject.txt
# WHY: declares ac2 but the defect it introduces is the one ac1 catches.
MARKER_TWO
'
runst "$T/c"
if [ "$RC" = 0 ]; then
  no "ac3: a mutant that failed the gate for a DIFFERENT assertion than it declared was counted as a kill — that leaves its declared assertion unexercised while the corpus claims coverage"
elif ! grep -q 'wrong-reason.txt' "$T/st.out"; then
  no "ac3: the run failed but never named the mutant. Tool said: $(stout)"
else
  ok "ac3: a mutant that fails for another reason is not counted as a kill"
fi
gate_done
