# MUTANT: ac5
# TARGET: scripts/ralph-build.sh
# WHY: a stray fi. bash -n refuses the file; nothing that sources or execs it can run.
#!/usr/bin/env bash
# ralph-build.sh — THE bounded SDD build loop. One loop; the executor is a binding
# (RALPH_EXEC_CMD), so this drives qwen, Codex, or anything else without being copied.
# The filename still says qwen for now — renaming it ripples into seven specs' gates;
# see specs/20260825c-executor-binding §5.
#
# Philosophy (learned the hard way): qwen3-coder is a fast, faithful, literal STAMPER
# with no stamina, taste, or self-checking. So we don't make it smarter — we build the
# fixture around it. This loop is the conveyor belt + jig + inspector:
#
#   for each task in the spec:
#     fresh executor session (no context accumulation)   <- bound the context
#     give it ONE task + the spec as source               <- bound the scope
#     timebox the run (run_bounded, below)                <- a stall can't cost hours
#     run verify.sh — the DETERMINISTIC gate, not the model's self-report
#     pass -> commit ; fail -> retry with the failure fed back ; stuck -> stop for a human
#
# The model executes; the loop carries the rigor; the human reviews the PR at the end.
#
# Usage (run from inside a git worktree on a throwaway branch):
#   scripts/ralph-build.sh specs/<feature>              # default binding: qwen
#   scripts/run-loop.sh build-codex specs/<feature>    # or pick a strategy
# spec dir must contain: spec.md, verify.sh, tasks.txt (one task per line, e.g. "T1: arr widgets")
#
# Resume control:
#   RALPH_FORCE_FROM=<n>    skip tasks 1..n-1, run task n and onward
#   RALPH_FORCE_ALL=1       disable skip-satisfied; every task runs regardless of gate state
#
# A task is "satisfied" if its own gate passed before the executor runs. Only specs with per-task
# gates (e.g., `20260828i`) support this question; monolithic-gate specs cannot answer it (green
# gate just means spec is done). The loop polls its own state — workers cannot receive external
# signals, so run control decisions must be discovered by polling.
set -uo pipefail

# ── Snapshot-and-re-exec (issue #48) ──────────────────────────────────────────────────────────
# Bash reads a running script incrementally and remembers a byte offset. A spec whose task
# edits THIS FILE rewrites it while bash executes it; the next read resumes at the old offset
# in displaced content and bash runs whatever fragment it finds. Observed 2026-08-29
# (20260829b-resume-bound): the task passed and COMMITTED, then the loop died on a fragment of
# a comment ("last: command not found") and exited 2 — a false red after the work succeeded,
# inviting exactly the wrong response. So the loop never executes the worktree's copy: it
# copies its scripts dir to a run-local snapshot and re-execs from there. The executor still
# edits the worktree's copy — that is the deliverable; it is just not the copy being read.
# $0/_SD then resolve into the snapshot, so every sibling (bound.sh, loop-index.py, the
# default exec binding) is read from the frozen copy too. Failure is fatal up front: a loop
# that silently ran unprotected would reintroduce the bug only on the days it matters.
# RALPH_NO_SNAPSHOT=1 skips (debugging). Cleanup rides the hb_tick_stop EXIT trap below.
if [ -z "${RALPH_SNAPSHOT:-}" ] && [ "${RALPH_NO_SNAPSHOT:-0}" != "1" ]; then
  _src="$(cd "$(dirname "$0")" && pwd)"
  _snap="$(mktemp -d "${TMPDIR:-/tmp}/ralph-snap.XXXXXX")" \
    || { echo "ralph-build: cannot create the script snapshot" >&2; exit 1; }
  cp -R "$_src/." "$_snap/" \
    || { rm -rf "$_snap"; echo "ralph-build: cannot populate the script snapshot" >&2; exit 1; }
  RALPH_SNAPSHOT="$_snap" exec bash "$_snap/$(basename "$0")" "$@"
fi
# Cleanup must be armed NOW, not only at the hb_tick_stop trap much further down: the early
# exits (missing spec files, gate validation's exit 3) fire before that line is reached, and
# each one leaked a snapshot until this trap existed. The later trap REPLACES this one and
# carries the same rm — one trap at a time is bash's rule, so both sites must know it.
trap '[ -n "${RALPH_SNAPSHOT:-}" ] && rm -rf "$RALPH_SNAPSHOT"' EXIT INT TERM

SPEC_DIR="${1:?usage: ralph-build.sh <spec-dir>}"
RETRIES="${RALPH_RETRIES:-2}"

if [ "${RALPH_FORCE_FROM:-}" != "" ]; then
  echo "RALPH_FORCE_FROM=$RALPH_FORCE_FROM: re-running from task $RALPH_FORCE_FROM onward"
fi
if [ "${RALPH_FORCE_ALL:-0}" = "1" ]; then
  echo "RALPH_FORCE_ALL=1: skipping disabled; every task will run"
fi

# The executor is a binding, exactly as JUDGE_CMD/EXECUTOR_CMD are for ralph-judge.sh. A
# strategy in scripts/loops/ sets it; unset, the loop drives qwen and behaves as it always has.
# The binding takes ONE argument (the prompt), reads ROOT from the environment, and writes the
# transcript to stdout. It owns no tasks, no gate, no evidence — see specs/20260825c-executor-binding §3.
# Expanded UNQUOTED at the call site, exactly as ralph-judge.sh expands $EXECUTOR_CMD, so a
# binding may carry arguments ("bash /path/x.sh", or a wrapper plus flags) rather than having to
# be a single executable file.
_SD="$(cd "$(dirname "$0")" && pwd)"
# The portable wall-clock bound (defines `bound`, runs nothing on load). _task_satisfied
# needs it: its old bare `timeout(1)` call was coreutils-only, so on macOS every satisfied
# check exited 127, read as "gate did not pass", and skip-satisfied never once skipped
# there (issue #98 — the same 127 gate-selftest hit in 20260828k, same cure).
. "$_SD/bound.sh"
RALPH_EXEC_CMD="${RALPH_EXEC_CMD:-$_SD/exec-opencode.sh}"
EXEC_TIMEOUT="${RALPH_EXEC_TIMEOUT:-480}"

# Portable watchdog, same shape as ralph-judge.sh's. It lives in the LOOP, not in the binding:
# oc happens to carry its own timeout and codex did not, so the old codex copy hand-rolled one
# and a third executor would have had to remember to. A bound every attempt gets is a property
# of the loop. Not timeout(1) — stock macOS does not ship it.
run_bounded() { # <seconds> <cmd...> -> 124 on timeout, else the command's exit code
  local secs="$1"; shift
  "$@" & local pid=$! waited=0
  local poll="${RALPH_CANCEL_POLL:-10}"
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      echo "  ! executor exceeded ${secs}s — killing (likely a stalled session)." >&2
      kill -TERM "$pid" 2>/dev/null; sleep 1; kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null; return 124
    fi
    # Collect a cancel WHILE the executor runs, not only between attempts.
    #
    # Checking only between attempts made Stop take up to RALPH_EXEC_TIMEOUT — 25 minutes by
    # default — which is not a stop button, it is a request. Measured: a run cancelled six minutes
    # into an attempt kept going, and the T3 gate passed anyway because its fixture executor
    # finishes instantly, so "stops promptly" and "stops whenever this attempt happens to end"
    # were the same reading.
    #
    # The earlier comment here claimed interrupting mid-executor was unsafe because it leaves a
    # half-written tree. It does — and that is fine, because the run is ENDING. The danger was
    # ever only a half-written tree the NEXT ATTEMPT inherits, and after a cancel there is no next
    # attempt. A deliberate stop leaves the same partial work any interrupted run leaves.
    if [ "$waited" -gt 0 ] && [ "$poll" -gt 0 ] && [ $((waited % poll)) -eq 0 ] \
       && command -v _hb_control >/dev/null 2>&1 && [ "$(_hb_control)" = cancel ]; then
      echo "  ! cancel intent collected — stopping the executor." >&2
      kill -TERM "$pid" 2>/dev/null; sleep 1; kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null; return 125
    fi
    sleep 1; waited=$((waited+1))
  done
  wait "$pid"
}

SPEC="$SPEC_DIR/spec.md"; VERIFY="$SPEC_DIR/verify.sh"; TASKS="$SPEC_DIR/tasks.txt"
# _check_cancel — collect an intent and act on it between tasks and between attempts, the two
# moments the loop is already at rest. run_bounded polls as well, so a cancel is also collected
# mid-executor; this covers the gaps that one cannot see — while a gate is running, or between the
# last attempt and the next task.
#
# Exit 4 is its own code. 0 would report success for work that never happened, and 1/2/3 already
# mean "gate failed", "stop, needs a human" and "the spec needs attention" — a cancelled run is
# none of those, and a reader who cannot tell them apart will go looking for a bug that is not
# there.
_check_cancel() {
  command -v _hb_control >/dev/null 2>&1 || return 0
  [ "$(_hb_control)" = cancel ] || return 0
  echo "✋ CANCELLED: a stop intent was collected from the coordinator." >&2
  echo "   The run ended here on purpose — this is not a gate failure and not a broken executor." >&2
  command -v hb_write >/dev/null 2>&1 && hb_write cancelled
  exit 4
}

for f in "$SPEC" "$VERIFY" "$TASKS"; do [ -f "$f" ] || { echo "missing $f" >&2; exit 1; }; done

# ── Per-task gate resolution (20260828i) ──────────────────────────────────────────────────────
#
# A spec MAY carry tasks/T<NN>-<slug>/verify.sh, one per task in tasks.txt order. When it does,
# the gate for task N is the gates for tasks 1..N — cumulative, so a later task that breaks an
# earlier one still fails, while nothing beyond N is ever consulted. When it does not, the gate
# is $SPEC_DIR/verify.sh exactly as before. Every existing spec relies on that fallback; it is a
# superset, not a migration.

_task_count() { grep -c '^T[0-9]' "$TASKS"; }

# _gate_for <n> — print the gate path for the nth task, or return 1. Two-digit zero-padded
# prefix so a numeric sort and a lexical one agree, which they stop doing at ten tasks.
_gate_for() {
  local d
  d="$(ls -d "$SPEC_DIR"/tasks/T"$(printf '%02d' "$1")"-* 2>/dev/null | head -1)"
  [ -n "$d" ] && [ -f "$d/verify.sh" ] || return 1
  printf '%s' "$d/verify.sh"
}

# _scope_for <n> — print the nth task's scope file, or return 1. Opt-in: a task with no
# scope file is unscoped and the loop behaves exactly as before (superset, not migration).
_scope_for() {
  local d
  d="$(ls -d "$SPEC_DIR"/tasks/T"$(printf '%02d' "$1")"-* 2>/dev/null | head -1)"
  [ -n "$d" ] && [ -f "$d/scope" ] || return 1
  printf '%s' "$d/scope"
}

# _scope_lines <scope-file> — the effective globs: comments and blanks dropped.
_scope_lines() { sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "$1"; }

# _scope_violations <scope-file> — every changed path OUTSIDE the scope's globs.
# Pure git, no hand-rolled matching: one `:(exclude)` pathspec per scope line, plus the
# fixed excludes for the loop's own bookkeeping (heartbeats, metrics, indexes, run logs
# are written DURING the attempt and are never the executor's doing). `set --` keeps the
# built-up exclude list function-local (bash 3.2 floor — no arrays).
_scope_violations() {
  local g _sf="$1"
  set --
  # ${1+"$@"}, not "$@": under `set -u`, bash before 4.4 (macOS ships 3.2) treats an
  # EMPTY "$@" as an unbound variable and aborts the function mid-substitution.
  while IFS= read -r g; do
    set -- ${1+"$@"} ":(exclude)$g"
  done <<EOF
$(_scope_lines "$_sf")
EOF
  git -C "$ROOT" status --porcelain -- . \
    ':(exclude).evidence/status' ':(exclude).evidence/metrics.jsonl' \
    ':(exclude).evidence/index-*' ':(exclude).evidence/runs' ${1+"$@"} 2>/dev/null \
    | cut -c4-
}

# _reset_tree — the three-step failure reset, single-sourced so the verify-failure and
# scope-violation paths cannot drift apart. The clean spares the loop's own bookkeeping
# (issue #21): a NEW spec's status dir / index / metrics are untracked until first merged,
# and a clean that eats them leaves a worker that cannot classify itself
# (ADR-001 D6). Litter is the executor's; the record is ours. Same fixed set
# _scope_violations excludes, and it must hold in consumer repos whose .gitignore says
# nothing about .evidence — hence -e excludes here, not gitignore policy.
_reset_tree() {
  git -C "$ROOT" reset -q -- . 2>/dev/null || true   # index to HEAD so checkout -- can drop staged files
  git -C "$ROOT" checkout -- . 2>/dev/null || true   # tracked changes from the bad attempt
  git -C "$ROOT" clean -fd \
    -e '.evidence/status' -e '.evidence/metrics.jsonl' \
    -e '.evidence/index-*' -e '.evidence/runs' -- . 2>/dev/null || true
}

# Validate UP FRONT, before any task runs. A missing gate discovered mid-loop is folded into that
# attempt's verify feedback and retried three times, so the message never reaches the loop's own
# output and a human reading the run sees a model that could not satisfy a gate rather than a
# spec that is missing one.
_validate_task_gates() {
  if [ ! -d "$SPEC_DIR/tasks" ]; then
    # The monolithic pend-staged gate is DEAD for multi-task specs (20260828i, defect 2:
    # "the gate is the roadmap" — an executor reads a later task's pend as a to-do and
    # overshoots; re-proved twice on 20260831a, 2026-08-31). There is NO escape hatch:
    # 20260831b shipped an allow-env for legacy re-runs and 20260831p removed it — a spec
    # that does not match the convention is refused, full stop. The ~30 legacy specs are
    # done; their gates still run directly (bash verify.sh), which needs no loop. One
    # task needs no pend and is exempt.
    local _n; _n="$(_task_count)"
    if [ "$_n" -gt 1 ]; then
      echo "ralph: $SPEC_DIR has $_n tasks and no tasks/ directory — the monolithic pend-staged gate is dead for multi-task specs (specs/20260828i-per-task-gates: the gate is the roadmap)." >&2
      echo "ralph: give each task its own tasks/T<NN>-<slug>/verify.sh (specs/TEMPLATE.md §gate layout). There is no override." >&2
      return 1
    fi
    return 0
  fi
  local i n _sf; n="$(_task_count)"
  # The mutant-corpus policy (20260831u). A CORPUS-ERA spec — date prefix 20260831u or
  # later, the id ordering the repo already lives by — ships one authored poison pill per
  # task or does not run: a gate that has never proven it can fail is not qualified to
  # judge work. A LEGACY spec is warned out loud, once per task, and NEVER backfilled —
  # editing rigor into history is the same defect as editing history's gates.
  local _era=0 _slug; _slug="$(basename "$SPEC_DIR")"
  case "$_slug" in
    [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][a-z]-*)
      [ "${_slug%%-*}" \< "20260831u" ] || _era=1 ;;
  esac
  for i in $(seq 1 "$n"); do
    if ! _gate_for "$i" >/dev/null; then
      echo "ralph: task $i has no gate ($SPEC_DIR/tasks/T$(printf '%02d' "$i")-*/verify.sh)" >&2
      echo "ralph: a task running with no criteria at all is worse than the monolithic gate this replaces" >&2
      return 1
    fi
    # A scope file with zero effective globs matches nothing, which makes EVERY attempt a
    # violation — that is a spec authoring error, refused up front like a missing gate.
    if _sf="$(_scope_for "$i")" && [ -z "$(_scope_lines "$_sf")" ]; then
      echo "ralph: task $i has a scope file with no globs ($_sf) — a scope that matches nothing makes every attempt a violation" >&2
      return 1
    fi
    local _md; _md="$(dirname "$(_gate_for "$i")")/mutants"
    if ! ls "$_md"/* >/dev/null 2>&1; then
      if [ "$_era" -eq 1 ]; then
        echo "ralph: task $i has no mutant corpus ($_md) — a corpus-era spec ships one poison pill per task, or its gates are unproven (20260831u)" >&2
        echo "ralph: author one mutant per assertion id by inverting the assertion (specs/TEMPLATE.md §11), then run again" >&2
        return 1
      fi
      echo "ralph: WARN task $i has no mutant corpus — this gate has never proven it can fail (legacy spec, pre-20260831u: warned, never backfilled)" >&2
    elif grep -l '^#[[:space:]]*TARGET:.*<' "$_md"/* >/dev/null 2>&1; then
      # The sentinel TARGET (<...>) is the scaffolder's stub. Refusing it HERE, not at
      # first green, is the difference between a five-second refusal and a wasted build.
      echo "ralph: task $i's mutant corpus is still the scaffold template ($_md) — a placeholder is not a poison pill (20260831u)" >&2
      echo "ralph: replace the template with real mutants — one per assertion id, TARGET a real repo-relative path" >&2
      return 1
    fi
  done
  return 0   # EXPLICIT. Without it this function inherits the exit status of its last
             # construct, which for a loop is its terminating condition — reliably non-zero.
}
_validate_task_gates || exit 3   # 3, not 1: the spec needs attention, not another retry.

# _task_satisfied <n> <task-name> — return 0 if task n's gate already passes, 1 otherwise.
# Answers false immediately for a MULTI-task spec without tasks/ (monolithic — unanswerable);
# a single-task spec's question is answered by its spec gate under STRICT (issue #30).
# Answers false when the task has no gate or the gate cannot run (fail-closed).
# Runs ONLY that task's gate, never the cumulative group.
# Times out after RALPH_SATISFIED_TIMEOUT (default RALPH_EXEC_TIMEOUT) and treats timeout as false (gate hangs -> task runs).
_task_satisfied() {
  local n="$1" task="$2" g="" _strict=""
  if [ ! -d "$SPEC_DIR/tasks" ]; then
    # Multi-task monolithic (the legacy escape hatch): unanswerable — a green whole-spec
    # gate says the SPEC is done, not that task N is. Fail-closed.
    [ "$(_task_count)" = 1 ] || return 1
    # Single-task spec (the 20260828i exemption has no tasks/ dir): the spec gate IS the
    # task's gate, so the question is answerable after all — under STRICT, because a
    # legacy pend-staged gate is green on an empty tree and must not read as satisfied.
    # This is what lets an operator interrupt and resume a finished single-task spec
    # instead of watching it die as a no-op ×3 (issue #30).
    g="$VERIFY"; _strict=1
  fi
  # Force-all: skip never. Fail-closed.
  [ "${RALPH_FORCE_ALL:-0}" = "1" ] && { return 1; }
  # Force-from: re-run task n and everything after. Fail-closed for this task.
  [ -n "${RALPH_FORCE_FROM:-}" ] && [ "$n" -ge "${RALPH_FORCE_FROM:-0}" ] && { return 1; }
  # Task has no gate. Fail-closed.
  if [ -z "$g" ]; then g="$(_gate_for "$n")" || { return 1; }; fi
  # Bound the gate: a hanging gate must not wedge a resume.
  # Default to RALPH_EXEC_TIMEOUT if unset, empty, or non-positive-integer.
  local _bound="${RALPH_SATISFIED_TIMEOUT:-$EXEC_TIMEOUT}"
  if [ -z "$_bound" ] || ! [ "$_bound" -gt 0 ] 2>/dev/null; then
    _bound="$EXEC_TIMEOUT"
  fi
  # The verdict is the gate's EXIT STATUS, never a search of its output. A failing gate prints a
  # PASS line for every assertion that did hold, so grepping for the word reads a red gate as a
  # satisfied task and skips it — worse than never skipping, because not skipping costs time and
  # this costs correctness in silence. `out` is captured for the announcements, not consulted for
  # the answer.
  # STRICT reaches only the single-task path; per-task gates ban pend and never read it.
  local out
  if [ -n "$_strict" ]; then
    out="$(STRICT=1 bound "$_bound" bash "$g" 2>&1)"
  else
    out="$(bound "$_bound" bash "$g" 2>&1)"
  fi
  local _rc=$?
  # The two refusals are different facts and read differently: one is a bound to raise or a gate
  # to make cheaper, the other is work still to do. Neither says "skipped" — on both of these
  # paths the task is about to RUN, and a line claiming otherwise tells a reader the reverse of
  # what happened.
  if [ "$_rc" -eq 124 ]; then
    echo "  ! $task did not skip (gate did not finish within ${_bound}s; raise RALPH_SATISFIED_TIMEOUT to allow more time)" >&2
    return 1
  fi
  if [ "$_rc" -ne 0 ]; then
    echo "  ! $task did not skip (gate did not pass)" >&2
    return 1
  fi
  return 0
}

# run_gates <task-index> <strict> — run every gate that applies after that task, print all of
# their output, and return 0 only if all of them passed. Runs the whole set even after one
# fails, so the executor sees every failure at once rather than the first.
run_gates() {
  local n="$1" strict="$2" rc=0 i g
  # The SECOND placement of the quarantine; specs/lib/assert.sh is the first. Neither is
  # redundant, because they cover different populations: assert.sh reaches the 31 per-task gates
  # that source it and a gate run by hand or by gate-selftest, and NONE of the 24 monolithic
  # gates — 20260801a..20260828j predate the per-task layout and define ok/no inline. Several of
  # those drive the real loop, which makes them precisely the gates that can post to a
  # coordinator. Clearing it here covers every gate the loop runs, whatever that gate sources.
  #
  # Not `unset` in this function: the LOOP reads RALPH_FORCE_ALL and RALPH_FORCE_FROM itself, and
  # unsetting them here would take the loop's own controls with it. `env -u` is scoped to the
  # child, which is the only scope that should lose them.
  #
  # Adding a source line to all 24 instead would be 24 edits that must not change one verdict,
  # and it reinstates the rule-you-must-remember for gate number 25.
  local _hermetic="env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN -u RALPH_FORCE_ALL -u RALPH_FORCE_FROM -u RALPH_SATISFIED_TIMEOUT"
  if [ ! -d "$SPEC_DIR/tasks" ]; then
    ( cd "$ROOT" && $_hermetic STRICT="$strict" bash "$VERIFY" 2>&1 )
    return $?
  fi
  for i in $(seq 1 "$n"); do
    g="$(_gate_for "$i")" || { echo "ralph: task $i has no gate" >&2; return 3; }
    ( cd "$ROOT" && $_hermetic STRICT="$strict" bash "$g" 2>&1 ) || rc=1
  done
  return $rc   # 0 = every gate passed. Getting this backwards reports a red gate as green,
               # which is the only failure here worse than a broken loop.
}
# EXPORTED, because the executor binding is a separate process and the contract
# (README, "binding") says it reads ROOT from the environment. It never actually did: bindings
# only worked because exec-qwen.sh falls back to ${ROOT:-$PWD} and the loop happens to run with
# cwd inside the worktree. A binding that trusted the documented contract got an unset variable
# — caught the first time one was written strictly, dispatching to a repo outside pi-cluster.
export ROOT="$(git rev-parse --show-toplevel)"

# Durable heartbeat (see ralph-status.sh). Sourced so a dashboard can see live
# loop state without attaching tmux. No-op stubs if the helper is absent, so the
# loop never depends on it.
RALPH_AGENT="${RALPH_AGENT:-qwen}"
# The agent name is not decoration. It becomes an evidence path segment (ralph-log.sh:
# "<agent>-$$") and the commit prefix "ralph(<agent>):" that loop-index.py parses back out
# of git log. Its grammar there is [a-z0-9-]+ — give it a space or a capital and the index
# silently stops matching the very commits this run just wrote, which reads exactly like
# "the loop did nothing". Fail at the top instead, where the name is still fixable.
case "$RALPH_AGENT" in
  ''|*[!a-z0-9-]*)
    echo "ralph: RALPH_AGENT must match [a-z0-9-]+ (got '$RALPH_AGENT')" >&2; exit 2 ;;
esac
if [ -f "$(dirname "$0")/ralph-status.sh" ]; then
  . "$(dirname "$0")/ralph-status.sh"
else
  hb_init() { :; }; hb_write() { :; }; hb_tick_start() { :; }; hb_tick_stop() { :; }
fi

# Matrix bus narration — the discrete-event companion to the heartbeat's continuous
# state. Same optional-and-never-fatal contract. See scripts/ralph-bus.sh for why both
# exist rather than one.
if [ -f "$(dirname "$0")/ralph-bus.sh" ]; then
  . "$(dirname "$0")/ralph-bus.sh"
else
  bus_init() { :; }; bus_open() { :; }; bus_say() { :; }
fi
# Attempt artefacts. ralph discarded the model's output and then reset the tree, so a stopped
# loop left nothing to diagnose with. See scripts/ralph-log.sh.
if [ -f "$(dirname "$0")/ralph-log.sh" ]; then
  . "$(dirname "$0")/ralph-log.sh"
else
  log_init() { :; }; log_path() { printf '/dev/null'; }; log_failure() { :; }; log_where() { :; }
fi
# Retry contract — track regressions across attempts. See scripts/ralph-retry.sh.
if [ -f "$(dirname "$0")/ralph-retry.sh" ]; then
  . "$(dirname "$0")/ralph-retry.sh"
else
  retry_init() { :; }; retry_record() { :; }; retry_regressions() { :; }
fi

# Navigation codesheet (repo map + shape-appropriate reference sheet), generated
# ONCE for the whole loop: byte-stable across every task and retry, so after the
# first attempt it rides the Beelink's prefix cache for ~free. Deliberately not
# regenerated after commits — stability beats freshness for caching, and each
# task is bounded anyway. Measured: 20-56% less context at equal-or-better
# accuracy (docs/research/codemap-serena-token-efficiency.md). RALPH_SHEET=off
# disables. The qwen binding sets OC_SHEET=off so the sheet isn't injected twice.
SHEET=""
SHEET_GEN="$(dirname "$0")/gen-codesheet.mjs"
if [ "${RALPH_SHEET:-on}" = "on" ] && [ -f "$SHEET_GEN" ] && command -v node >/dev/null 2>&1; then
  SHEET="$(node "$SHEET_GEN" "$ROOT" 2>/dev/null || true)"
  [ -n "$SHEET" ] && echo "codesheet: injected (~$(( ${#SHEET} / 4 )) tokens, stable for the whole loop)"
else
  # Say it ONCE, and say it here. RALPH_SHEET defaults on, harness-base ships no node (only
  # gen-codesheet.mjs needs it, and the npm-based derived images add it themselves), so in any
  # image that does not add node the default is silently off. The only symptom is a token count
  # nobody is comparing — a run quietly losing its measured context saving with nothing in the
  # log is the failure this repo catalogues most often.
  # Flat, not a nested if: the announcement has to be the else branch's OWN statement. Wired
  # behind another condition it is invisible to a reader scanning the guard, and it stops being
  # the thing that fires in the case that matters.
  [ "${RALPH_SHEET:-on}" = "on" ] && [ -f "$SHEET_GEN" ] && ! command -v node >/dev/null 2>&1 \
    && echo "codesheet: OFF — node is not on PATH, so $(basename "$SHEET_GEN") cannot run. The measured 20-56% context saving is not being applied. Install node in the image, or set RALPH_SHEET=off to make this deliberate." \
    || true
fi

hb_init; log_init; hb_write starting
# Keep the heartbeat alive through the long model calls, and make sure it stops when this
# loop does — a heartbeat that outlives its loop would make a dead agent look busy forever.
hb_tick_start
# One trap, two duties: a second `trap … EXIT` would silently replace the first.
# The snapshot (issue #48, top of file) is this process's own litter to remove.
trap 'hb_tick_stop; [ -n "${RALPH_SNAPSHOT:-}" ] && rm -rf "$RALPH_SNAPSHOT"' EXIT INT TERM
bus_init; bus_open "$(basename "$SPEC_DIR")"

while IFS= read -r task || [ -n "$task" ]; do
  [ -z "${task// }" ] && continue
  _check_cancel
  echo "════════ TASK: $task ════════"
  HB_TASK="$task"; HB_TIDX=$((HB_TIDX + 1)); hb_write running
  # Skip-satisfied: if the task's gate already passes and we're not forcing, skip without
  # invoking the executor or consuming an attempt. Announce in the same format as other tasks.
  if _task_satisfied "$HB_TIDX" "$task"; then
    echo "  ✓ $task skipped (gate already passed)"
    HB_ATTEMPT="skipped"; LOG_OUTCOME="skipped"; LOG_STARTED="$(date +%s)"; LOG_ENDED="$LOG_STARTED"; LOG_RECORDED=1
    log_meta "$HB_TASK" "$HB_ATTEMPT"
    hb_write passed true
    feedback=""
    continue
  fi
  feedback=""; passed=0; retry_init
  # The task's declared scope, if any (tasks/T<NN>-*/scope). Stated in the prompt first —
  # prevention before punishment — and enforced before the gate below.
  scope_file=""; scope_note=""
  if scope_file="$(_scope_for "$HB_TIDX")"; then
    scope_note="
This task may change ONLY paths matching these globs (repo-relative):
$(_scope_lines "$scope_file")
Any change outside them fails the attempt outright."
  else
    scope_file=""
  fi
  for attempt in $(seq 1 $((RETRIES + 1))); do
    _check_cancel
    HB_ATTEMPT="$attempt"; LOG_STARTED="$(date +%s)"; LOG_RECORDED=""; hb_write running
    prompt="${SHEET:+$SHEET

}Read $SPEC. Implement ONLY this one task, nothing else: ${task}
Follow the spec's section 10 acceptance criteria and section 7 norms EXACTLY.
Do not run git add, git commit, or git stash — the loop owns the index.
Do not touch anything outside this task's scope. Reuse existing patterns; never invent
URLs/UIDs. When done, stop.${scope_note}${feedback}"

    # Fresh session each attempt (no continuation) = no context bloat. The executor is a
    # BINDING, not a hardcoded command: whoever the loop drives, it is invoked the same way,
    # bounded the same way, and its transcript kept the same way. That seam is why there is one
    # build loop rather than one per executor — a duplicated loop is what a missing parameter
    # looks like, and the copy this replaced cost three specs a rule apiece to keep in sync.
    # See specs/20260825c-executor-binding §1.
    log_prompt "$HB_TASK" "$attempt" "$prompt"

    # Keep the transcript. This used to go to /dev/null, which made every STOP undiagnosable.
    # shellcheck disable=SC2086  # deliberate word-split: see below
    run_bounded "$EXEC_TIMEOUT" $RALPH_EXEC_CMD "$prompt" \
      > "$(log_path "$HB_TASK" "$attempt")" 2>&1; _rc=$?
    _logfile="$(log_path "$HB_TASK" "$attempt")"
    # Guarded the way every other cross-file call here is (see `command -v hb_write` below):
    # ralph-log.sh is sourced, and a ralph-build.sh that hard-depends on one of its functions
    # breaks the moment the two files are not the same vintage. T01's control does exactly that
    # on purpose — it runs this script against main's ralph-log.sh to prove the unconfigured
    # path is unchanged — and an unguarded call turns that into "command not found" on stdout.
    [ -s "${_logfile:-}" ] && command -v ralph_log_artifact_push >/dev/null 2>&1 \
      && ralph_log_artifact_push log "$_logfile" "$HB_TASK" "$attempt"
    if [ "$_rc" = 125 ]; then
      echo "✋ CANCELLED: a stop intent was collected while the executor was running." >&2
      echo "   The run ended here on purpose — this is not a gate failure and not a broken executor." >&2
      command -v hb_write >/dev/null 2>&1 && hb_write cancelled
      exit 4
    fi
    # An executor that never started is NOT a failed attempt — it is a broken container, and
    # letting it fall through to verify is how a no-op run reports success. Observed 2026-07-22:
    # the executor died in <1s with "current working directory was deleted" on every attempt,
    # each log 247 bytes, and the loop happily marked 3/3 done. A real attempt (even one the
    # watchdog kills at EXEC_TIMEOUT) leaves a substantial transcript; a stillborn one a stub.
    _log="$(log_path "$HB_TASK" "$attempt")"
    _sz=$(wc -c < "$_log" 2>/dev/null || echo 0)
    if [ "$_rc" != 0 ] && [ "$_sz" -lt 512 ]; then
      echo "✋ ABORT: the executor did not start (exit $_rc, ${_sz}B of output) — the container needs attention, not another retry." >&2
      sed 's/^/    | /' "$_log" 2>/dev/null | head -4 >&2
      LOG_OUTCOME="stillborn"; LOG_ENDED="$(date +%s)"; LOG_RECORDED=1; log_meta "$HB_TASK" "$attempt"
      hb_write stopped false; log_where
      bus_say "✋ ABORT — executor did not start (exit $_rc). Container needs attention."
      exit 3
    fi


    # There is no separate no-op work guard here any more (20260831p). It existed
    # for the pend-staged legacy shape, where an empty tree satisfied every lenient gate;
    # that shape is refused up front now. Every runnable shape is gate-decided: a per-task
    # gate bans pend, and a single-task spec's only gate run is STRICT (task 1 of 1 is the
    # last task) — an empty tree fails an honest gate with feedback naming the missing
    # criteria, which beats a generic hint. Deleting it also removed its ':!.evidence'
    # blind spot, which refused a task whose DELIVERABLE lives under .evidence/ (issue #91,
    # 20260831a's T2, both watched runs).

    # The scope guard (20260831d, issue #91): where a task declared its scope, any change
    # outside it fails the attempt BEFORE the gate. Reject WHOLESALE, never filter the
    # commit — stripping the out-of-scope files could commit a task whose gate went green
    # BECAUSE of them, which is a lie in the history worse than a lost attempt. The reset
    # below is the same three steps as the verify-failure path.
    if [ -n "$scope_file" ]; then
      _viol="$(_scope_violations "$scope_file")"
      if [ -n "$_viol" ]; then
        echo "  ✗ attempt $attempt touched files outside this task's scope — rejected before the gate" >&2
        printf '%s\n' "$_viol" | sed 's/^/      | /' >&2
        LOG_OUTCOME="scope"; LOG_ENDED="$(date +%s)"; LOG_RECORDED=1; log_meta "$HB_TASK" "$attempt"
        # Capture the rejected work BEFORE the reset erases it, exactly as the verify-failure
        # path does (issue #23: a reset with no artifact makes the attempt undiagnosable —
        # and a scope violation is precisely the diff a human wants to read).
        log_failure "$HB_TASK" "$attempt" "attempt rejected: out-of-scope changes
$_viol"
        hb_write failed false
        feedback="
A previous attempt changed files OUTSIDE this task's declared scope and was rejected
before the gate ran; NOTHING was kept, including any in-scope work it also did.
This task may change ONLY paths matching:
$(_scope_lines "$scope_file")
Out-of-scope paths it touched:
$_viol
Redo the work touching only in-scope paths."
        _reset_tree
        continue
      fi
    fi

    # The spec-dir guard (20260831r, notes-from-hearing run 1): the executor edited its own
    # task gate in the same attempt that satisfied it. That edit happened to widen coverage;
    # one that WEAKENS a check rides into the commit the same silent way — reward hacking's
    # front door. Fail-closed, like the scope guard above: an attempt that changes ANYTHING
    # under the spec dir is rejected wholesale before the gate. A genuine gate blind spot
    # then deadlocks to escalation, which is correct — humans own gate changes.
    _spec_edits="$( { git -C "$ROOT" diff --name-only -- "$SPEC_DIR"
                      git -C "$ROOT" ls-files --others --exclude-standard -- "$SPEC_DIR"
                    } 2>/dev/null | sort -u )"
    if [ -n "$_spec_edits" ]; then
      echo "  ✗ attempt $attempt edited the spec dir — rejected before the gate (the executor does not change the ruler)" >&2
      printf '%s\n' "$_spec_edits" | sed 's/^/      | /' >&2
      LOG_OUTCOME="spec-edit"; LOG_ENDED="$(date +%s)"; LOG_RECORDED=1; log_meta "$HB_TASK" "$attempt"
      log_failure "$HB_TASK" "$attempt" "attempt rejected: it modified the spec dir
$_spec_edits"
      hb_write failed false
      feedback="
A previous attempt MODIFIED files under $SPEC_DIR and was rejected before the gate ran;
NOTHING was kept, including any product work it also did. The spec, its tasks and its
gates are the operator's ruler — never edit them. If a gate seems wrong or unpassable,
say so in your transcript and stop; a human owns gate changes. Files it touched:
$_spec_edits
Redo the work without touching $SPEC_DIR."
      _reset_tree
      continue
    fi

    # The gate: deterministic, external. The model does NOT get to say "done".
    hb_write verifying
    # Last task is HB_TIDX equals HB_TOTAL. If HB_TOTAL is empty/0, lenient (safe default).
    STRICT=0
    [ "${HB_TOTAL:-0}" -gt 0 ] && [ "$HB_TIDX" -eq "$HB_TOTAL" ] && STRICT=1
    if out="$(run_gates "$HB_TIDX" "$STRICT" 2>&1)"; then
      _mode="lenient"; [ "$STRICT" -eq 1 ] && _mode="strict"
      echo "  ✓ $task passed verify (attempt $attempt, gate: $_mode)"
      log_gate "$HB_TASK" "$attempt" "$out" "0"
      log_patch "$HB_TASK" "$attempt"
      # The gate went green — prove it COULD have failed before that green buys a commit
      # (20260831u). gate-selftest copies the WORKING TREE, so the built-but-uncommitted
      # work is exactly what each mutant is measured against; this is why the moment is
      # first-green, not preflight — pristine, a red-first gate fails everything and every
      # mutant dies vacuously. Once per task is sufficient: the spec-dir guard above froze
      # gate and corpus for the run's duration. Refusal is a STOP, not a retry, and the
      # tree is LEFT IN PLACE: the work passed its gate — it is the GATE that is broken,
      # and gates are the operator's.
      _st_gate="$(_gate_for "$HB_TIDX" 2>/dev/null || true)"
      _st_dir=""; [ -n "$_st_gate" ] && _st_dir="$(dirname "$_st_gate")/mutants"
      if [ -n "$_st_dir" ] && ls "$_st_dir"/* >/dev/null 2>&1; then
        _st_out="$( cd "$ROOT" && SELFTEST_EVID="${SELFTEST_EVID:-$ROOT/.evidence}" \
            GATE_SELFTEST_TIMEOUT="${GATE_SELFTEST_TIMEOUT:-90}" \
            bash "$(dirname "$0")/gate-selftest.sh" "$(dirname "$_st_gate")" 2>&1 )"; _st_rc=$?
        printf '%s\n' "$_st_out" | grep -E 'SURVIVOR|WRONG-REASON|HUNG|uncovered|^summary:' | sed 's/^/    | selftest /'
        if [ "$_st_rc" -ne 0 ]; then
          echo "✋ STOP: ${task%%:*} went green, but its GATE failed its selftest — a gate that cannot fail for the right reason proves nothing by passing." >&2
          printf '%s\n' "$_st_out" | tail -12 | sed 's/^/    | /' >&2
          echo "    This is the GATE failing, not the work. The built tree is left in place for a human;" >&2
          echo "    fix the gate or its mutants (operator-owned, 20260831r T5), then run again." >&2
          LOG_OUTCOME="gate-selftest"; LOG_ENDED="$(date +%s)"; LOG_RECORDED=1; log_meta "$HB_TASK" "$attempt"
          hb_write stopped false; log_where
          bus_say "✋ STOP — ${task%%:*} went green but its GATE failed selftest. The gate needs a human."
          exit 6
        fi
      fi
      # The outcome is recorded AFTER the commit, not before. It used to be this line, and the
      # commit below ended in `|| true` — so a run whose commit failed recorded `passed`, kept
      # going, and the next task's failure path (`git checkout -- .`) deleted the work. Silent
      # loss of a task that had genuinely gone green. Absent a git identity — which no image in
      # this repo provides and which every fixture happens to set — that is the DEFAULT path.
      _head_before="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"
      git -C "$ROOT" add -A
      # NOT "ralph(qwen)". This line named one executor while the same run filed its
      # evidence under another — a codex run committed as qwen. loop-index.py had already
      # been generalised to read any "word(word):" prefix precisely because "a tool that
      # names one executor is a tool that stops working when you change executors"
      # (loop-index.py:160); the READER was fixed and the WRITER was not. git log is the
      # record a human reads first, so it was the copy that lied.
      _commit_err="$(git -C "$ROOT" commit -q -m "ralph($RALPH_AGENT): ${task%%:*} — ${task#*: }" 2>&1)" || true
      # HEAD MOVED is the assertion, not the exit code. They are two different questions, and
      # only one of them is about whether the work survives: a non-zero rc with a commit made
      # and a zero rc with nothing committed are both reachable, and the durable fact is the
      # ref. Checking rc alone would have kept the weaker half of the same bug.
      if [ "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)" = "$_head_before" ]; then
        echo "✋ ABORT: $task passed its gate but the commit did not land — the work is not saved." >&2
        printf '%s\n' "$_commit_err" | sed 's/^/    | /' | head -4 >&2
        echo "    The tree still holds the change; commit it by hand before running again." >&2
        echo "    If this is a container, it has no git identity: set user.name and user.email." >&2
        LOG_OUTCOME="uncommitted"; LOG_ENDED="$(date +%s)"; LOG_RECORDED=1; log_meta "$HB_TASK" "$attempt"
        hb_write stopped false; log_where
        bus_say "✋ ABORT — $task went green but the commit did not land. Work is uncommitted."
        exit 5
      fi
      # Recorded HERE, on the far side of the commit, which is the whole point of the change:
      # `passed` now means "the gate went green AND the change is in the history", not "the gate
      # went green and we tried". Moving this line without re-adding it is exactly the mistake
      # this spec's own AC-1 caught on the first draft — a passing attempt wrote no record at all.
      LOG_OUTCOME="passed"; LOG_ENDED="$(date +%s)"; LOG_RECORDED=1; log_meta "$HB_TASK" "$attempt"
      passed=1; hb_write passed true
      bus_say "✓ ${task%%:*} passed verify (attempt $attempt/$((RETRIES + 1))) — ${HB_TIDX}/${HB_TOTAL:-?}"
      retry_record "$out"
      # $(dirname $0), NOT a bare `scripts/…`: that path was relative to the TARGET
      # worktree, and a project that correctly owns only specs and gates has no scripts/
      # dir at all. notes-from-hearing#9 removed the harness from the product repo exactly
      # as the convention asks, and every task of every run after it printed
      # "scripts/loop-index.py: No such file or directory". The harness must reach its own
      # tools by its own location.
      "$(dirname "$0")/loop-index.py" --repo "$ROOT" --spec "$SPEC_DIR" 2>&1 \
        || { echo "WARN: loop-index.py failed" >&2; }
      # loop-metrics.sh had NO CALLERS. It was written to answer "how is the loop doing" —
      # attempts per task, whether cost is falling, how much of the gate is real evidence —
      # and nothing ever invoked it, so .evidence/metrics.jsonl went stale and the 2026-08-25
      # run had no cost record of any kind. Wiring it here, beside the indexer, on the same
      # best-effort contract: recording a run must never be able to fail the run.
      SPEC_DIR="$SPEC_DIR" "$(dirname "$0")/loop-metrics.sh" \
        "${HB_TASK%%:*}" "$ROOT" "${LOG_DIR:-}" \
        >/dev/null 2>&1 || { echo "WARN: loop-metrics.sh failed" >&2; }
      # "Did work happen" and "was evidence collected" are two questions. The guard above
      # now excludes .evidence/ from the first one — which would silently hide a broken
      # indexer, since loop-index.py is best-effort. So ask the second question directly:
      # the row for this task must exist. Warn, never fail: recording the run must not be
      # able to fail the run it is recording.
      _idx="$ROOT/.evidence/index-$(basename "$SPEC_DIR").jsonl"
      if [ ! -s "$_idx" ]; then
        echo "WARN: no $(basename "$_idx") after ${HB_TASK%%:*} — the record was not collected" >&2
      elif ! grep -q "\"task\": *\"${HB_TASK%%:*}\"" "$_idx" 2>/dev/null; then
        echo "WARN: $(basename "$_idx") has no row for ${HB_TASK%%:*} — indexing ran but did not record this task" >&2
      fi
      break
    fi
      _mode="lenient"; [ "$STRICT" -eq 1 ] && _mode="strict"
       echo "  ✗ verify failed (attempt $attempt, gate: $_mode); retrying with feedback" >&2
        hb_write failed false
        LOG_ENDED="$(date +%s)"; log_gate "$HB_TASK" "$attempt" "$out" "1"
      LOG_ENDED="$(date +%s)"; log_failure "$HB_TASK" "$attempt" "$out"   # BEFORE the reset below erases the evidence
    retry_record "$out"
    # Feed the failing checks back into the next fresh attempt — targeted, not vibes.
    _regression_block=""
    if _rb="$(retry_regressions "$out")" && [ -n "$_rb" ]; then
      _regression_block="
REGRESSION — these checks PASSED in an earlier attempt of this same task and now do not:
$_rb
Keep them passing while you fix the failures above. Do not trade one check for another."
    fi
    feedback="
A previous attempt FAILED verification with:
$(printf '%s' "$out" | grep -E 'FAIL|VERIFY' | head -20)
Fix exactly those failures.${_regression_block}"
    # `checkout --` alone would leave untracked files behind, letting an out-of-scope file
    # from attempt N survive into attempt N+1 (and even arm a later task's PEND-gated
    # checks early — see the rom-library-structure dogfood PR for the real failure this
    # caused); _reset_tree's clean takes them, sparing only the loop's own bookkeeping.
    _reset_tree
  done

  if [ "$passed" != 1 ]; then
    echo "✋ STOP: '$task' failed verify after $((RETRIES + 1)) attempts — needs a human." >&2
    # Guarded on LOG_RECORDED, not LOG_ENDED: LOG_ENDED is stamped on every attempt, so an
    # ENDED-based guard is always false and this site silently never fires — losing the only
    # record a gate-rejected attempt would ever get. This is a TASK-level stop reusing the last
    # attempt's number, so it must not overwrite a record that attempt already wrote.
    if [ -z "${LOG_RECORDED:-}" ]; then
      LOG_OUTCOME="failed"; LOG_ENDED="$(date +%s)"; LOG_RECORDED=1; log_meta "$HB_TASK" "$attempt"
    fi
    hb_write stopped false
    log_where
    bus_say "✋ STOP — '${task%%:*}' failed verify after $((RETRIES + 1)) attempts. Needs a human."
    exit 2
  fi
done < "$TASKS"

# Presence-gated checks pend until their target exists, so passing every task individually does
# NOT prove the work was done — see the STRICT note in verify.sh. Run the gate once more with
# pending treated as failure before declaring victory.
# At convergence, run every task gate under STRICT and then the spec-level gate, which in the
# per-task shape holds only integration and end-state assertions and runs nowhere else.
if ! _strict_out="$( { run_gates "${HB_TOTAL:-0}" 1; _r=$?
     [ -d "$SPEC_DIR/tasks" ] && { cd "$ROOT" && STRICT=1 bash "$VERIFY" 2>&1 || _r=1; }
     exit $_r; } 2>&1)"; then
   echo "✋ STOP: every task passed, but the final STRICT gate found unbuilt work:" >&2
       printf '%s\n' "$_strict_out" | grep -E 'FAIL' | head -10 >&2
       # ${attempt:-skipped}: `attempt` is assigned only inside the attempt loop, and a run
       # whose every task was skip-satisfied never enters it — this line crashed unbound
       # under set -u before hb_write could stamp the status terminal (issue #49). The
       # default is the skip path's own sentinel, not 0, because 0 reads as a real attempt.
       LOG_OUTCOME="failed"; LOG_ENDED="$(date +%s)" && log_meta "$HB_TASK" "${attempt:-skipped}"
       hb_write stopped false; log_where
   bus_say "✋ STOP — every task passed, but the final STRICT gate found unbuilt work. Needs a human."
   exit 2
fi

hb_write done true
bus_say "done — ${HB_TOTAL:-?}/${HB_TOTAL:-?} tasks passed verify on $(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null). Branch ready for PR review."
echo "════════ all tasks passed verify — branch ready for PR review ════════"
git -C "$ROOT" log --oneline -"$(grep -cve '^[[:space:]]*$' "$TASKS")"

fi
