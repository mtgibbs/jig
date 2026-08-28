#!/usr/bin/env bash
# T02 — RALPH_FORCE_FROM and RALPH_FORCE_ALL, the mechanism a "retry from here" control needs.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
. "$ROOT/specs/20260828l-run-control/lib/fixtures.sh"
mkexec

# Both tasks already complete: without an override nothing should run at all.
prep() { mkloop "$1" yes; echo a > "$1/a.txt"; echo b > "$1/b.txt"
         ( cd "$1" && git add -A && git commit -qm alldone ) >/dev/null 2>&1; }

prep "$T/base"; runloop "$T/base"
base="$(execs "$T/base")"
[ "$base" = 0 ] && ok "control: with every task satisfied and no override, the executor never runs" \
                || no "control: $base executor runs with everything satisfied and no override — T01's skip is not in effect, so nothing below measures the overrides. Loop said: $(loopout base)"

# ac1 — FORCE_FROM=2 re-runs task 2 and after; task 1 may still be skipped.
prep "$T/ff"; runloop "$T/ff" RALPH_FORCE_FROM=2
n="$(execs "$T/ff")"
if [ "$RC" = 124 ]; then no "ac1: the loop did not return within 180s under RALPH_FORCE_FROM"
elif [ "$n" = 0 ]; then no "ac1: RALPH_FORCE_FROM=2 ran nothing — task 2 must run regardless of its gate. Loop said: $(loopout ff)"
elif [ "$n" -gt 1 ]; then no "ac1: RALPH_FORCE_FROM=2 ran the executor $n times — task 1 is before the index and may still be skipped. Loop said: $(loopout ff)"
else ok "ac1: RALPH_FORCE_FROM=n re-runs task n onward and leaves earlier tasks skippable"; fi

# ac2 — FORCE_ALL disables skipping entirely.
prep "$T/fa"; runloop "$T/fa" RALPH_FORCE_ALL=1
n="$(execs "$T/fa")"
[ "$n" -ge 2 ] && ok "ac2: RALPH_FORCE_ALL=1 runs every task regardless of gate state" \
               || no "ac2: RALPH_FORCE_ALL=1 ran the executor $n times, expected 2. Loop said: $(loopout fa)"

# ac3 — a malformed value is absent, not zero. Silently meaning "force everything" would surprise;
# silently meaning "force nothing" would be worse.
prep "$T/bad"; runloop "$T/bad" RALPH_FORCE_FROM=banana
n="$(execs "$T/bad")"
[ "$n" = 0 ] && ok "ac3: a malformed override is treated as absent, not as force-everything" \
             || no "ac3: RALPH_FORCE_FROM=banana caused $n executor runs — a value that is not a positive integer must read as absent. Loop said: $(loopout bad)"

# ac4 — an override in effect is announced, because it may have been set in an earlier shell.
grep -qiE 'force|override' "$T/ff.out" \
  && ok "ac4: an override in effect is announced at the start of the run" \
  || no "ac4: RALPH_FORCE_FROM was in effect and never mentioned — an operator cannot see that a variable set earlier is still acting. Loop said: $(loopout ff)"
gate_done
