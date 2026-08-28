#!/usr/bin/env bash
# Gate for 20260828i-per-task-gates.
#
# BOOTSTRAPPING NOTE, so the shape of this file is not read as hypocrisy: this spec introduces
# per-task gates, so its own gate cannot be one — the resolver that would run it is T2 of this
# very spec. It is therefore written in the old monolithic shape, `pend` ladder and all, and it
# is the last gate in this repo that should be. Every guard below keys on the artifact of the
# task that SATISFIES it, never on a value an assertion is about, and every call into the thing
# under test is bounded. Those are §7's norms, and this file is their first consumer.
set -u
fail=0
ok()   { echo "  PASS  $1"; }
no()   { echo "  FAIL  $1" >&2; fail=1; }
pend() { echo "  pend  $1 — not built yet"; [ "${STRICT:-0}" = 1 ] && fail=1; return 0; }

ROOT="$(git rev-parse --show-toplevel)"
T="$(mktemp -d)" || { echo "VERIFY: ENV (no temp dir)" >&2; exit 2; }
printf '#!/bin/sh\nexit 0\n' > "$T/x"; chmod +x "$T/x"
"$T/x" 2>/dev/null || { echo "VERIFY: ENV (noexec TMPDIR — set TMPDIR to an exec-able path)" >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
export PYTHONDONTWRITEBYTECODE=1 PYTHONPYCACHEPREFIX="$T/pyc"

ASSERT="$ROOT/specs/lib/assert.sh"
SELFTEST="$ROOT/scripts/gate-selftest.sh"

# ── the fixture ────────────────────────────────────────────────────────────────────────────
# A two-task repo carrying the REAL scripts/ from this tree, driven by a stub executor that
# makes a trivial change so the no-op guard is satisfied. Each gate appends a line to $GATELOG,
# so what ran, in what order, and under which STRICT is a fact we read rather than infer.
#
# Built and driven before a single assertion was written. Its observed baseline on unmodified
# main is exactly three invocations of the spec gate for two tasks — STRICT=0, STRICT=1
# (last-task-strict), STRICT=1 (convergence) — and that is what AC-1 pins.
mkfixture() {                              # mkfixture <dir> <tasks:yes|no> <t2gate:yes|no>
  local d="$1" want_tasks="$2" want_t2="$3"
  rm -rf "$d"; mkdir -p "$d/specs/fx"
  cp -r "$ROOT/scripts" "$d/scripts"
  printf '# fixture\n' > "$d/specs/fx/spec.md"
  printf 'T1: first thing.\n\nT2: second thing.\n' > "$d/specs/fx/tasks.txt"
  printf '#!/usr/bin/env bash\necho "SPEC STRICT=${STRICT:-0}" >> "$GATELOG"\nexit 0\n' \
    > "$d/specs/fx/verify.sh"; chmod +x "$d/specs/fx/verify.sh"
  if [ "$want_tasks" = yes ]; then
    mkdir -p "$d/specs/fx/tasks/T01-first"
    printf '#!/usr/bin/env bash\necho "T01 STRICT=${STRICT:-0}" >> "$GATELOG"\nexit 0\n' \
      > "$d/specs/fx/tasks/T01-first/verify.sh"; chmod +x "$d/specs/fx/tasks/T01-first/verify.sh"
    if [ "$want_t2" = yes ]; then
      mkdir -p "$d/specs/fx/tasks/T02-second"
      printf '#!/usr/bin/env bash\necho "T02 STRICT=${STRICT:-0}" >> "$GATELOG"\nexit 0\n' \
        > "$d/specs/fx/tasks/T02-second/verify.sh"; chmod +x "$d/specs/fx/tasks/T02-second/verify.sh"
    fi
  fi
  ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
}

printf '#!/usr/bin/env bash\necho "x $$" >> "$ROOT/work.txt"\n' > "$T/exec.sh"; chmod +x "$T/exec.sh"

# runfx <dir> -> prints the loop's exit code; $GATELOG holds the ordered gate trace.
# BOUNDED: an unbounded loop here would hang the gate rather than fail it, and the watchdog
# would then blame the executor for a defect in this file.
# GATELOG is set at TOP LEVEL, not inside runfx: runfx is called in a command substitution,
# so an assignment made inside it dies with that subshell and trace() would read an unbound
# variable. The truncation below is a filesystem side effect and does survive.
GATELOG="$T/gatelog.txt"; export GATELOG
# Output goes to a file named for the FIXTURE, not a shared one. Every assertion is evaluated
# after all fixtures have run, so a shared file meant each failure message quoted whichever
# fixture ran last. ac1 reported `Loop said:` with nothing while the loop had plenty to say,
# and the executor spent an attempt retrying against a message carrying no information.
runfx() {
  local d="$1" tag; tag="$(basename "$d")"
  : > "$GATELOG"
  ( cd "$d" && RALPH_LOG=off RALPH_EXEC_CMD="$T/exec.sh" RALPH_AGENT=gate \
      timeout 180 bash scripts/ralph-build.sh specs/fx ) > "$T/$tag.out" 2>&1
  echo $?
}
fxout() { tr '\n' ' ' < "$T/$1.out" 2>/dev/null | tail -c 400; }
trace() { tr '\n' '|' < "$GATELOG"; }

# ── AC-4 · the vocabulary (T1) ─────────────────────────────────────────────────────────────
if [ ! -r "$ASSERT" ]; then
  pend "ac4: specs/lib/assert.sh defines ok and no, and no pend"
else
  # Behavioural, not a grep: source it and ask the shell what exists. A grep for "pend" would
  # also match the header comment that the task text REQUIRES, and would fail correct work.
  _v="$(timeout 10 bash -c '. "$1" 2>/dev/null
        for f in ok no; do type -t "$f" >/dev/null 2>&1 || { echo "missing:$f"; exit 0; }; done
        type -t pend >/dev/null 2>&1 && { echo "defines:pend"; exit 0; }
        echo good' _ "$ASSERT" 2>&1)"
  case "$_v" in
    good)         ok "ac4: assert.sh defines ok and no, and pend is not callable" ;;
    missing:*)    no "ac4: assert.sh does not define ${_v#missing:}" ;;
    defines:pend) no "ac4: assert.sh defines pend — a task gate has nothing to defer (§2.3)" ;;
    *)            no "ac4: sourcing assert.sh did not answer. It said: $(echo "$_v" | tr '\n' ' ' | tail -c 200)" ;;
  esac
fi

# ── AC-1/2/3/9 · the resolver (T2) ─────────────────────────────────────────────────────────
# Guard on whether a per-task gate runs AT ALL, which is T2's artifact. Deliberately not a grep
# on ralph-build.sh: the property is behavioural, and a grep would pass an implementation that
# names the directory without ever invoking what is in it.
mkfixture "$T/fxA" no  no ; RC_A="$(runfx "$T/fxA")" ; TRACE_A="$(trace)"
mkfixture "$T/fxB" yes yes; RC_B="$(runfx "$T/fxB")" ; TRACE_B="$(trace)"

# AC-1 — the fallback. Pinned to the observed baseline, and asserted whether or not T2 is built,
# because "existing specs still behave exactly as before" is the one property T2 can REGRESS.
if [ "$RC_A" = 124 ]; then
  no "ac1: the loop did not return within 180s on a spec with no tasks/ — bounded call timed out. Loop said: $(fxout fxA)"
elif [ "$RC_A" != 0 ]; then
  no "ac1: a spec with no tasks/ exited $RC_A. Loop said: $(fxout fxA)"
elif [ "$TRACE_A" = "SPEC STRICT=0|SPEC STRICT=1|SPEC STRICT=1|" ]; then
  ok "ac1: with no tasks/, the spec gate runs exactly as before (lenient, strict, convergence)"
else
  no "ac1: with no tasks/ the gate trace changed — expected 'SPEC STRICT=0|SPEC STRICT=1|SPEC STRICT=1|', got '$TRACE_A'"
fi

# Three-way, not two. An EMPTY trace is not "unbuilt" — with no resolver at all the fallback
# still runs the spec gate, so unbuilt looks like "SPEC ...". Empty means the loop ran and
# produced no gate whatsoever, i.e. the resolver EXISTS AND IS BROKEN. Treating that as a pend
# is the defect this spec is about: a broken implementation reading as an absent one, passing
# leniently and telling the executor nothing. Observed for real on T2 attempt 1, where
# `validate_task_gates` inherited its while-loop's terminating status and exited 1 in silence.
if [ -z "$TRACE_B" ]; then
  for a in "ac2: gates run cumulatively 1..N and no gate beyond N" \
           "ac2b: a failing task gate fails the task" \
           "ac2c: task 1's gates run lenient; strict is reserved for the last task" \
           "ac3: a task with no gate directory is a hard error" \
           "ac9: the spec-level gate runs at convergence under STRICT"; do
    no "$a — with a tasks/ directory the loop ran NO gate at all (exit $RC_B). Not 'unbuilt': with no resolver the fallback still runs the spec gate. Loop said: $(fxout fxB)"
  done
else
case "$TRACE_B" in
  *T01*)
    # AC-2 — cumulative, and nothing beyond N. Both halves matter: running 1..N is what keeps
    # regression detection, and running nothing after N is the defect this spec removes.
    if [ "$RC_B" = 124 ]; then
      no "ac2: the loop did not return within 180s on a spec with tasks/. Loop said: $(fxout fxB)"
    else
      # Which task a gate invocation BELONGS to is read from STRICT, not from position: task 1
      # runs lenient (STRICT=0) and the last task runs strict (20260828d last-task-strict). So
      # "T02 STRICT=0" is T02's gate running during task 1 — a later task's gate run early.
      #
      # An earlier version of this check sliced the trace at the first T02 and then searched the
      # remainder for T02, which by construction could not be there: it was unfalsifiable, and a
      # mutant that ran EVERY task gate on task 1 — the precise defect this spec removes —
      # survived it. Keyed on the artifact instead of on the answer, per §7.1.
      if printf '%s' "$TRACE_B" | grep -q 'T02 STRICT=0'; then
        no "ac2: T02's gate ran during task 1 (lenient pass) — a later task's gate ran early. Trace '$TRACE_B'"
      elif [ "$(printf '%s' "$TRACE_B" | grep -o 'T01' | wc -l)" -lt 2 ]; then
        no "ac2: T01's gate ran only once — task 2 must re-run gates 1..N. Trace '$TRACE_B'"
      elif ! printf '%s' "$TRACE_B" | grep -q 'T02'; then
        no "ac2: T02's gate never ran at all. Trace '$TRACE_B'"
      else
        ok "ac2: gates run cumulatively 1..N and no gate beyond N ($TRACE_B)"
      fi
    fi
    # ac2c — last-task-strict (20260828d) is merged behaviour this change can silently break,
    # and nothing else here would notice. If task 1 runs STRICT=1, every `pend` becomes fatal on
    # the first task and no early task can pass. Found by asking what could break that no
    # assertion covers — the executor's `[ -n "$strict" ]` (true for the STRING "0") did exactly
    # this, and every other assertion passed it.
    case "$TRACE_B" in
      "T01 STRICT=0"*) ok "ac2c: task 1's gates run lenient; strict is reserved for the last task" ;;
      "T01 STRICT=1"*) no "ac2c: task 1 ran STRICT=1 — every pend is fatal on the first task, so no early task can pass. Trace '$TRACE_B'" ;;
      *)               no "ac2c: task 1's first gate invocation was not T01. Trace '$TRACE_B'" ;;
    esac

    # ac2b — the direction nothing else covers: a task gate that FAILS must fail the task.
    # Every gate in the fixtures above exits 0, so an implementation that inverts its own
    # return code passes all of them while reporting a red gate as green. That is the only
    # failure here that is worse than a broken loop, because it ships unbuilt work.
    mkfixture "$T/fxD" yes yes
    printf '#!/usr/bin/env bash\necho "T01 STRICT=${STRICT:-0}" >> "$GATELOG"\nexit 1\n' \
      > "$T/fxD/specs/fx/tasks/T01-first/verify.sh"
    chmod +x "$T/fxD/specs/fx/tasks/T01-first/verify.sh"
    ( cd "$T/fxD" && git add -A && git commit -qm gatefail ) >/dev/null 2>&1
    RC_D="$(runfx "$T/fxD")"
    if [ "$RC_D" = 0 ]; then
      no "ac2b: a task gate that FAILED was reported as green — the loop exited 0. Loop said: $(fxout fxD)"
    elif [ "$RC_D" = 124 ]; then
      no "ac2b: the loop hung on a failing task gate rather than failing"
    else
      ok "ac2b: a failing task gate fails the task (exit $RC_D)"
    fi

    # AC-9 — the spec gate still runs at convergence, under STRICT, in the new shape.
    case "$TRACE_B" in
      *"SPEC STRICT=1"*) ok "ac9: the spec-level gate runs at convergence under STRICT" ;;
      *"SPEC "*)         no "ac9: the spec-level gate ran but never under STRICT=1. Trace '$TRACE_B'" ;;
      *)                 no "ac9: the spec-level gate never ran at convergence. Trace '$TRACE_B'" ;;
    esac
    # AC-3 — a task with no gate is a hard error, never a skip.
    # Search the WHOLE output: a tail is flooded by unrelated stderr (ralph-status.sh noise
    # did exactly that here), which turned a correct implementation into "did not name it".
    mkfixture "$T/fxC" yes no; RC_C="$(runfx "$T/fxC")"; OUT_C="$(tr '\n' ' ' < "$T/fxC.out")"
    if [ "$RC_C" = 0 ]; then
      no "ac3: a task listed in tasks.txt with no gate directory was SKIPPED — the loop exited 0"
    elif [ "$RC_C" = 124 ]; then
      no "ac3: the loop hung on a missing task gate rather than failing"
    elif printf '%s' "$OUT_C" | grep -qi 'T02\|second'; then
      ok "ac3: a missing task gate exits non-zero ($RC_C) and names the task"
    else
      no "ac3: exited $RC_C on a missing task gate but did not name it. Loop said: $(printf '%s' "$OUT_C" | tail -c 400)"
    fi ;;
  *)
    pend "ac2: gates run cumulatively 1..N and no gate beyond N"
    pend "ac2b: a failing task gate fails the task"
    pend "ac2c: task 1's gates run lenient; strict is reserved for the last task"
    pend "ac3: a task with no gate directory is a hard error"
    pend "ac9: the spec-level gate runs at convergence under STRICT" ;;
esac
fi

# ── AC-5/6/7/8 · mutation self-test (T3) ───────────────────────────────────────────────────
if [ ! -x "$SELFTEST" ]; then
  pend "ac5: a task gate containing pend fails self-test"
  pend "ac6: an installed mutant is rejected for its declared reason"
  pend "ac7: an assertion no mutant declares fails self-test"
  pend "ac8: a covered gate whose mutants all die exits zero"
else
  # A task directory with one honest assertion, one mutant that breaks it, and a target.
  st() {                                   # st <dir> -> exit code, output in $T/st.out
    ( cd "$ROOT" && timeout 60 bash "$SELFTEST" "$1" ) > "$T/st.out" 2>&1; echo $?
  }
  mkst() {                                 # mkst <dir> <extra-assertion> <mutants...>
    local d="$1"; rm -rf "$d"; mkdir -p "$d/mutants"
    cat > "$d/verify.sh" <<'V'
#!/usr/bin/env bash
fail=0; ok(){ echo "  PASS  $1"; }; no(){ echo "  FAIL  $1" >&2; fail=1; }
grep -q 'MARKER_ONE' subject.txt && ok "ac1: subject carries marker one" || no "ac1: subject carries marker one"
EXTRA
[ "$fail" = 0 ] && { echo "VERIFY: PASS"; exit 0; }; echo "VERIFY: FAIL"; exit 1
V
    sed -i "s|^EXTRA$|$2|" "$d/verify.sh"; chmod +x "$d/verify.sh"
  }
  printf 'MARKER_ONE\nMARKER_TWO\n' > "$ROOT/subject.txt"
  trap 'rm -rf "$T" "$ROOT/subject.txt"' EXIT

  # ac8 — the all-good case. One assertion, one mutant that kills it.
  mkst "$T/stA" ':'
  printf '# MUTANT: ac1\n# TARGET: subject.txt\n# WHY: drops marker one, so ac1 must fail.\nMARKER_TWO\n' \
    > "$T/stA/mutants/ac1-drop.txt"
  RC="$(st "$T/stA")"
  if [ "$RC" = 0 ]; then ok "ac8: a covered gate whose mutants all die exits zero"
  elif [ "$RC" = 124 ]; then no "ac8: self-test did not return within 60s on the all-good case"
  else no "ac8: the all-good case exited $RC. Self-test said: $(tail -c 300 "$T/st.out" | tr '\n' ' ')"; fi

  # ac6 — the survivor. A mutant that changes nothing the gate looks at must be reported.
  mkst "$T/stB" ':'
  printf '# MUTANT: ac1\n# TARGET: subject.txt\n# WHY: claims to break ac1 but leaves the marker, so the gate should NOT kill it.\nMARKER_ONE\nMARKER_TWO\n' \
    > "$T/stB/mutants/ac1-survivor.txt"
  RC="$(st "$T/stB")"
  if [ "$RC" = 0 ]; then
    no "ac6: a mutant the gate ACCEPTED was reported as killed — a survivor is the headline failure"
  elif grep -qi 'surviv' "$T/st.out"; then
    ok "ac6: a surviving mutant is detected and named"
  else
    no "ac6: exited $RC on a survivor but never said so. Self-test said: $(tail -c 300 "$T/st.out" | tr '\n' ' ')"
  fi

  # ac7 — coverage. Two assertions, one mutant: ac2 is unobserved and must be named.
  mkst "$T/stC" 'grep -q "MARKER_TWO" subject.txt && ok "ac2: subject carries marker two" || no "ac2: subject carries marker two"'
  printf '# MUTANT: ac1\n# TARGET: subject.txt\n# WHY: drops marker one only.\nMARKER_TWO\n' \
    > "$T/stC/mutants/ac1-drop.txt"
  RC="$(st "$T/stC")"
  if [ "$RC" = 0 ]; then
    no "ac7: ac2 is declared by no mutant and self-test still passed — an unobserved assertion"
  elif grep -q 'ac2' "$T/st.out"; then
    ok "ac7: an assertion no mutant declares fails self-test, naming it"
  else
    no "ac7: exited $RC without naming the uncovered id. Self-test said: $(tail -c 300 "$T/st.out" | tr '\n' ' ')"
  fi

  # ac5 — pend is banned in a task gate.
  mkst "$T/stD" 'pend "ac2: deferred"'
  printf '# MUTANT: ac1\n# TARGET: subject.txt\n# WHY: drops marker one.\nMARKER_TWO\n' \
    > "$T/stD/mutants/ac1-drop.txt"
  RC="$(st "$T/stD")"
  if [ "$RC" = 0 ]; then
    no "ac5: a task gate containing pend passed self-test"
  elif grep -qi 'pend' "$T/st.out"; then
    ok "ac5: a task gate containing pend fails self-test, naming it"
  else
    no "ac5: exited $RC on a gate with pend but did not say why. Self-test said: $(tail -c 300 "$T/st.out" | tr '\n' ' ')"
  fi
fi

echo "---"
[ "$fail" = 0 ] && { echo "VERIFY: PASS"; exit 0; }
echo "VERIFY: FAIL"; exit 1
