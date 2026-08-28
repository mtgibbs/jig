#!/usr/bin/env bash
# T03 — installation, the bounded gate run, and one observable line per mutant.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
. "$ROOT/specs/20260828k-gate-selftest/lib/fixtures.sh"

[ -x "$ST" ] || { no "ac1: every mutant is named in the output"
                  no "ac2: a mutant that hangs the gate is bounded and reported as such"
                  no "ac3: the workspace is restored between mutants"
                  gate_done; }

# ac1/ac3 — two mutants with OPPOSITE effects. If the workspace is not restored between them,
# the harmless one runs against the killing one's damage and the two become indistinguishable —
# which is the whole discriminator, and it survives T04 replacing raw detail with verdicts.
mkrepo "$T/a"
# NAMES MATTER: mutants run in glob order, so the destructive one must sort FIRST or there is
# no contamination for the second to be measured against. With the harmless mutant first this
# assertion passes even when the workspace is never restored — it was written that way, and did
# not fail until the fixture was reordered.
mutant "$T/a" a-kills-ac1.txt "$GOOD_MUTANT"
mutant "$T/a" b-harmless.txt '# MUTANT: ac1
# TARGET: other.txt
# WHY: touches a file the gate never reads, so the gate should NOT fail — and it must target a
# DIFFERENT file from the first mutant, or it repairs the damage from the first mutant and the loss
# of isolation becomes unobservable.
UNRELATED-CHANGED
'
runst "$T/a"
if [ "$RC" = 124 ]; then
  no "ac1: the tool did not return within 90s"
  no "ac3: the workspace is restored between mutants"
else
  if grep -q 'a-kills-ac1' "$T/st.out" && grep -q 'b-harmless' "$T/st.out"; then
    ok "ac1: every mutant is named in the output"
  else
    no "ac1: the output does not name every mutant. Tool said: $(stout)"
  fi
  _k="$(grep 'a-kills-ac1' "$T/st.out" | head -1 | sed 's/a-kills-ac1[^ ]*//')"
  _h="$(grep 'b-harmless'  "$T/st.out" | head -1 | sed 's/b-harmless[^ ]*//')"
  if [ -z "$_k" ] && [ -z "$_h" ]; then
    no "ac3: neither mutant produced a report line. Tool said: $(stout)"
  elif [ "$_k" = "$_h" ]; then
    no "ac3: a mutant that breaks the gate and one that does not were reported identically ('$_k') — the workspace is not restored between mutants, so the second runs against the first's damage"
  else
    ok "ac3: the workspace is restored between mutants"
  fi
fi

# ac2 — a mutant that makes the GATE hang must not hang the TOOL. Reporting it as an ordinary
# failure would hide it while making the gate look like it works.
mkrepo "$T/b"
mutant "$T/b" ac1-drop.txt "$GOOD_MUTANT"
mutant "$T/b" hangs.txt '# MUTANT: ac1
# TARGET: specs/fx/tasks/T01-thing/verify.sh
# WHY: replaces the gate with one that never returns.
#!/usr/bin/env bash
sleep 600
'
_t0=$(date +%s); runst "$T/b"; _t1=$(date +%s)
if [ "$RC" = 124 ]; then
  no "ac2: a hanging gate hung the tool — it must bound every gate invocation, not inherit the hang"
elif [ $((_t1 - _t0)) -ge 85 ]; then
  no "ac2: the tool took $((_t1 - _t0))s on a gate that sleeps 600 — it returned, but not by bounding the call"
elif grep -qiE 'hung|timed out|timeout' "$T/st.out"; then
  ok "ac2: a mutant that hangs the gate is bounded and reported as such"
else
  no "ac2: a hanging gate was not reported as a hang, so it is indistinguishable from a failure. Tool said: $(stout)"
fi
gate_done
