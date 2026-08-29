# fixtures.sh — shared by this spec's task gates. Sourced, never executed.
#
# gate-selftest.sh copies "the repository" it is run inside, so a fixture is a tiny real git
# repo built in $T: a subject file, a task dir holding a gate and mutants. Running the tool with
# cwd inside that repo keeps every test hermetic and leaves the real tree untouched — which
# matters twice over here, because three specs in this repo fail if files outside their scope
# change, and this tool's whole job is not to litter.

ST="$ROOT/scripts/gate-selftest.sh"

# mkrepo <dir> [second-assertion] — a fixture repo whose gate asserts ac1 (and optionally ac2).
mkrepo() {
  local d="$1" extra="${2:-}"
  rm -rf "$d"; mkdir -p "$d/specs/fx/tasks/T01-thing/mutants"
  printf 'MARKER_ONE\nMARKER_TWO\n' > "$d/subject.txt"
  printf 'UNRELATED\n' > "$d/other.txt"   # a second target, so a mutant can leave subject.txt alone
  {
    printf '#!/usr/bin/env bash\n'
    printf 'fail=0\n'
    printf 'ok(){ echo "  PASS  $1"; }\n'
    printf 'no(){ echo "  FAIL  $1" >&2; fail=1; }\n'
    printf 'grep -q MARKER_ONE subject.txt && ok "ac1: subject carries marker one" || no "ac1: subject carries marker one"\n'
    [ -n "$extra" ] && printf '%s\n' "$extra"
    printf '[ "$fail" = 0 ] && { echo "VERIFY: PASS"; exit 0; }\n'
    printf 'echo "VERIFY: FAIL"; exit 1\n'
  } > "$d/specs/fx/tasks/T01-thing/verify.sh"
  chmod +x "$d/specs/fx/tasks/T01-thing/verify.sh"
  ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
}

# mutant <repo> <filename> <body> — write a mutant file verbatim.
mutant() { printf '%s' "$3" > "$1/specs/fx/tasks/T01-thing/mutants/$2"; }

# A well-formed mutant that genuinely breaks ac1.
GOOD_MUTANT='# MUTANT: ac1
# TARGET: subject.txt
# WHY: drops marker one, so ac1 must fail.
MARKER_TWO
'

# runst <repo> [taskdir] — run the tool from inside the fixture repo. BOUNDED: a tool that hangs
# would wedge this gate rather than fail it, and the loop watchdog would then charge the delay to
# the executor. Sets RC and leaves output in $T/st.out.
runst() {
  local d="$1" td="${2:-specs/fx/tasks/T01-thing}"
  ( cd "$d" && bound 90 bash "$ST" "$td" ) > "$T/st.out" 2>&1
  RC=$?
  [ "$RC" = 124 ] && echo "  (tool did not return within 90s)" >&2
  return 0
}
stout() { tr '\n' ' ' < "$T/st.out" 2>/dev/null | tail -c 400; }

# Did the fixture repo change? The tool must operate on a copy.
repo_dirty() { ( cd "$1" && git status --porcelain 2>/dev/null | head -5 ); }
