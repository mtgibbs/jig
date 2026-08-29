#!/usr/bin/env bash
# T01 — argument handling and the hermetic workspace.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
. "$ROOT/specs/20260828k-gate-selftest/lib/fixtures.sh"

if [ ! -x "$ST" ]; then
  no "ac1: a missing or malformed argument is refused, saying which"
  no "ac2: a well-formed run leaves the repository byte-identical"
  gate_done
fi

mkrepo "$T/r"
mutant "$T/r" ac1-drop.txt "$GOOD_MUTANT"

# ac1 — four different wrongs, four different messages. A tool that answers all of them with
# "usage" makes the caller guess which one it hit.
bad=""
( cd "$T/r" && bound 30 bash "$ST" ) >"$T/e0" 2>&1; [ $? = 0 ] && bad="$bad no-arg-accepted"
( cd "$T/r" && bound 30 bash "$ST" specs/fx/tasks/NOPE ) >"$T/e1" 2>&1; [ $? = 0 ] && bad="$bad missing-dir-accepted"
mkdir -p "$T/r/specs/fx/tasks/T99-a/mutants"
( cd "$T/r" && bound 30 bash "$ST" specs/fx/tasks/T99-a ) >"$T/e2" 2>&1; [ $? = 0 ] && bad="$bad no-verify-accepted"
mkdir -p "$T/r/specs/fx/tasks/T98-b"; cp "$T/r/specs/fx/tasks/T01-thing/verify.sh" "$T/r/specs/fx/tasks/T98-b/"
( cd "$T/r" && bound 30 bash "$ST" specs/fx/tasks/T98-b ) >"$T/e3" 2>&1; [ $? = 0 ] && bad="$bad no-mutants-accepted"
grep -qi 'verify' "$T/e2" || bad="$bad missing-verify-unnamed"
grep -qi 'mutant' "$T/e3" || bad="$bad missing-mutants-unnamed"
rm -rf "$T/r/specs/fx/tasks/T99-a" "$T/r/specs/fx/tasks/T98-b"
[ -z "$bad" ] && ok "ac1: a missing or malformed argument is refused, saying which" \
              || no "ac1: argument handling —$bad. Tool said: $(tr '\n' ' ' < "$T/e3" | tail -c 200)"

# ac2 — hermetic. The tool must work on a COPY: a mutant left in the tree fails an unrelated
# spec's scope guard, and reads as someone else's bug.
( cd "$T/r" && git add -A && git commit -qm mut ) >/dev/null 2>&1
runst "$T/r"
if [ "$RC" = 124 ]; then
  no "ac2: the tool did not return within 90s on a well-formed task dir"
elif [ -n "$(repo_dirty "$T/r")" ]; then
  no "ac2: the tool modified the repository it was pointed at: $(repo_dirty "$T/r" | tr '\n' ' ')"
else
  ok "ac2: a well-formed run leaves the repository byte-identical"
fi
gate_done
