#!/usr/bin/env bash
# T05 — the two static checks on the gate file itself.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
. "$ROOT/specs/20260828k-gate-selftest/lib/fixtures.sh"

AC2='grep -q MARKER_TWO subject.txt && ok "ac2: subject carries marker two" || no "ac2: subject carries marker two"'

[ -x "$ST" ] || { no "ac1: an assertion no mutant declares fails the run, naming the id"
                  no "ac2: a task gate that INVOKES pend fails the run, naming the file"
                  gate_done; }

# ac1 — coverage. Mutation says an assertion is too WEAK; only this says one is UNEXERCISED.
# Two assertions, one mutant: ac2 is covered by nothing.
mkrepo "$T/a" "$AC2"
mutant "$T/a" ac1-drop.txt "$GOOD_MUTANT"
runst "$T/a"
if [ "$RC" = 0 ]; then
  no "ac1: ac2 is declared by no mutant and the run still passed — an assertion no mutant exercises has never been observed to work"
elif ! grep -q 'ac2' "$T/st.out"; then
  no "ac1: the run failed but never named the uncovered id. Tool said: $(stout)"
else
  ok "ac1: an assertion no mutant declares fails the run, naming the id"
fi

# Control: with BOTH ids covered the same corpus must pass, so ac1's failure above is about
# coverage and not about something else in that fixture.
mutant "$T/a" ac2-drop.txt '# MUTANT: ac2
# TARGET: subject.txt
# WHY: drops marker two, so ac2 must fail.
MARKER_ONE
'
runst "$T/a"
[ "$RC" = 0 ] && ok "control: covering both ids makes the same corpus pass" \
              || no "control: both ids covered but the run still failed ($RC) — ac1 above may be measuring something else. Tool said: $(stout)"

# ac2 — the pend ban. A per-task gate has nothing to defer; assert.sh does not define the verb.
mkrepo "$T/b"
mutant "$T/b" ac1-drop.txt "$GOOD_MUTANT"
printf 'pend(){ :; }\npend "ac9: deferred"\n' >> "$T/b/specs/fx/tasks/T01-thing/verify.sh"
runst "$T/b"
if [ "$RC" = 0 ]; then
  no "ac2: a task gate containing pend passed the run"
elif ! grep -qi 'pend' "$T/st.out"; then
  no "ac2: the run failed but never said pend was the reason. Tool said: $(stout)"
else
  ok "ac2: a task gate that INVOKES pend fails the run, naming the file"
fi

# Control: a gate that only MENTIONS the verb in prose must pass. Without this the check bans a
# word rather than a call, and it would fail the gates in this very spec — they are the ones
# asserting the ban, so they have to be able to name it.
mkrepo "$T/c"
mutant "$T/c" ac1-drop.txt "$GOOD_MUTANT"
printf '# this gate deliberately does not use the deferred verdict (no pend here)\n' >> "$T/c/specs/fx/tasks/T01-thing/verify.sh"
runst "$T/c"
[ "$RC" = 0 ] && ok "control: a gate that only mentions the verb in a comment still passes" \
              || no "control: a gate mentioning pend in a COMMENT was rejected — the check bans a word, not a call, and would fail this spec own gates. Tool said: $(stout)"
gate_done
