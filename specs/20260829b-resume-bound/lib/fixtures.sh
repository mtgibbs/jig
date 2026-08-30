# fixtures.sh — a throwaway two-task loop whose FIRST task's gate has a controllable cost.
#
# Adapted from 20260828l-run-control's fixtures, which established the observation trick this
# spec depends on: the stub executor appends a line to execlog.txt per invocation, so "the task
# was skipped" is OBSERVED as the absence of a line, never inferred from the loop's own prose.
#
# What is new here is the cost dial. Task 1's gate sleeps SLEEP_SECS on its FIRST invocation only,
# marked by a flag file, and returns immediately on every later one. The resume predicate calls
# that gate before the executor runs, so it pays the sleep; the cumulative `run_gates` calls that
# follow do not. Without that, a 62-second sleep would be paid three times and this gate would
# cost minutes instead of one.

# The quarantined environment (HARNESS_REPORT_URL/_TOKEN, RALPH_FORCE_ALL/_FROM,
# RALPH_SATISFIED_TIMEOUT) is cleared by specs/lib/assert.sh, which every gate that loads this
# file sources first, and again by ralph-build.sh's run_gates. It used to be reset HERE, and the
# incidents that earned each variable now live beside the unsets in assert.sh — one place, so
# there is no second list to keep in sync and no rule a new gate's author has to know.

# mkloop <dir> <sleep-secs> <task1-done:yes|no|mixed> — a two-task fixture carrying the REAL scripts/.
#
# `mixed` is the realistic failing gate: it prints a PASS line for an assertion that holds and
# THEN fails overall. Every real gate does this — assert.sh's ok() prints "  PASS  <id>" per
# satisfied assertion and the verdict comes from the exit status. A stub that prints only FAIL
# lines when it fails cannot distinguish "the predicate read the verdict" from "the predicate
# grepped for the word PASS", and those are the two states this fixture exists to separate.
mkloop() {
  local d="$1" secs="$2" done1="$3"
  rm -rf "$d"; mkdir -p "$d/specs/fx"
  cp -r "$ROOT/scripts" "$d/scripts"
  printf '# fixture\n' > "$d/specs/fx/spec.md"
  printf 'notes\n' > "$d/notes.md"
  printf 'T1: make a.\n\nT2: make b.\n' > "$d/specs/fx/tasks.txt"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/specs/fx/verify.sh"
  chmod +x "$d/specs/fx/verify.sh"

  mkdir -p "$d/specs/fx/tasks/T01-a" "$d/specs/fx/tasks/T02-b"
  # Task 1's gate: sleep once, then answer on the marker.
  if [ "$done1" = mixed ]; then
    cat > "$d/specs/fx/tasks/T01-a/verify.sh" <<GATE
#!/usr/bin/env bash
if [ ! -f .gate1-ran ]; then : > .gate1-ran; sleep $secs; fi
echo "  PASS  ac0: a thing that is true"
echo "  FAIL  ac1: a thing that is not" >&2
echo "VERIFY: FAIL"; exit 1
GATE
  else
    cat > "$d/specs/fx/tasks/T01-a/verify.sh" <<GATE
#!/usr/bin/env bash
if [ ! -f .gate1-ran ]; then : > .gate1-ran; sleep $secs; fi
[ -f a.txt ] && { echo "  PASS  ac1: a"; echo "VERIFY: PASS"; exit 0; }
echo "  FAIL  ac1: a" >&2; echo "VERIFY: FAIL"; exit 1
GATE
  fi
  printf '#!/usr/bin/env bash\n[ -f b.txt ] && { echo "  PASS  ac1: b"; echo "VERIFY: PASS"; exit 0; }\necho "  FAIL  ac1: b" >&2; echo "VERIFY: FAIL"; exit 1\n' \
    > "$d/specs/fx/tasks/T02-b/verify.sh"
  chmod +x "$d/specs/fx/tasks/T01-a/verify.sh" "$d/specs/fx/tasks/T02-b/verify.sh"

  # Task 1 already done means its marker is COMMITTED — the state a resume walks into.
  case "$done1" in yes|mixed) echo a > "$d/a.txt" ;; esac
  ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
  # .gate1-ran must not be tracked; the loop's inter-attempt clean may remove it, which only
  # makes the gate slower, never wrong.
  printf '.gate1-ran\n' > "$d/.gitignore"
  ( cd "$d" && git add .gitignore && git commit -qm ignore ) >/dev/null 2>&1
}

# The stub executor records WHICH task invoked it, taken from the prompt, and does that task's
# work. Keying off "the next missing marker" instead — as 20260828l's fixture does — cannot tell
# this spec's two cases apart: when task 1 is NOT skipped its invocation creates task 2's marker,
# task 2 is then skipped in turn, and both the skipped and unskipped paths show exactly one
# invocation. Whether task 1 ran has to be observed directly.
#
# It also appends to a TRACKED file on every invocation, so an attempt always changes something.
# Otherwise re-running an already-complete task trips the loop's no-op guard — "changed nothing
# is a failure" — and the run burns three attempts on a condition this spec is not testing.
mkexec() {
  cat > "$T/exec.sh" <<'X'
#!/usr/bin/env bash
p="${1:-}"
printf 'invoked %s\n' "$p" >> "${FX_LOG:?fixtures: FX_LOG must point outside the fixture repo}"
printf 'touched %s\n' "$(date +%s%N)" >> "$ROOT/notes.md"
case "$p" in
  *"make a"*) echo a > "$ROOT/a.txt" ;;
  *"make b"*) echo b > "$ROOT/b.txt" ;;
esac
X
  chmod +x "$T/exec.sh"
}

# runloop <dir> [env...] — BOUNDED well above the longest fixture sleep. Sets RC.
runloop() {
  local d="$1"; shift
  local tag; tag="$(basename "$d")"
  ( cd "$d" && bound 240 env "$@" RALPH_LOG=off RALPH_EXEC_CMD="$T/exec.sh" RALPH_AGENT=gate \
      FX_LOG="$T/$tag.execlog" \
      bash scripts/ralph-build.sh specs/fx ) > "$T/$tag.out" 2>&1
  RC=$?
}
loopout() { tr '\n' ' ' < "$T/$1.out" 2>/dev/null | tail -c 500; }
# The executor's log lives in $T, OUTSIDE the fixture repo, and this is not incidental. The loop
# runs `git clean -fd` between attempts, which deletes untracked files in the worktree — measured
# 2026-08-29, when a fixture whose task never converges had its execlog removed after every
# attempt, so "the executor was invoked three times" was indistinguishable from "never invoked".
# An instrument inside the thing being measured is not an instrument. (See harness#21.)
#
# ran <tag> <make a|make b> — was the executor invoked FOR that task? Observed, not inferred.
ran() { [ -f "$T/$1.execlog" ] && grep -qF "$2" "$T/$1.execlog"; }
execs() { [ -f "$T/$1.execlog" ] && grep -c invoked "$T/$1.execlog" || echo 0; }
