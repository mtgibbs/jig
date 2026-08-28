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
RALPH_EXEC_CMD="${RALPH_EXEC_CMD:-$_SD/exec-qwen.sh}"
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

# Validate UP FRONT, before any task runs. A missing gate discovered mid-loop is folded into that
# attempt's verify feedback and retried three times, so the message never reaches the loop's own
# output and a human reading the run sees a model that could not satisfy a gate rather than a
# spec that is missing one.
_validate_task_gates() {
  [ -d "$SPEC_DIR/tasks" ] || return 0
  local i n; n="$(_task_count)"
  for i in $(seq 1 "$n"); do
    _gate_for "$i" >/dev/null && continue
    echo "ralph: task $i has no gate ($SPEC_DIR/tasks/T$(printf '%02d' "$i")-*/verify.sh)" >&2
    echo "ralph: a task running with no criteria at all is worse than the monolithic gate this replaces" >&2
    return 1
  done
  return 0   # EXPLICIT. Without it this function inherits the exit status of its last
             # construct, which for a loop is its terminating condition — reliably non-zero.
}
_validate_task_gates || exit 3   # 3, not 1: the spec needs attention, not another retry.

# _task_satisfied <n> — return 0 if task n's gate already passes, 1 otherwise.
# Answers false immediately when tasks/ does not exist (monolithic spec — question unanswerable).
# Answers false when the task has no gate or the gate cannot run (fail-closed).
# Runs ONLY that task's gate, never the cumulative group.
# Times out after 60s and treats timeout as false (gate hangs -> task runs).
_task_satisfied() {
  local n="$1"
  # Monolithic spec: unanswerable. Fail-closed.
  [ -d "$SPEC_DIR/tasks" ] || { return 1; }
  # Force-all: skip never. Fail-closed.
  [ "${RALPH_FORCE_ALL:-0}" = "1" ] && { return 1; }
  # Force-from: re-run task n and everything after. Fail-closed for this task.
  [ -n "${RALPH_FORCE_FROM:-}" ] && [ "$n" -ge "${RALPH_FORCE_FROM:-0}" ] && { return 1; }
  # Task has no gate. Fail-closed.
  local g; g="$(_gate_for "$n")" || { return 1; }
  # Bound the gate: a hanging gate must not wedge a resume.
  local out; out="$(timeout 60 bash "$g" 2>&1)" || { _rc=$?; [ "$_rc" -eq 124 ] && return 1 || return 1; }
  # Check if the gate passed (timeout returns 124, gate failure returns non-zero)
  if echo "$out" | grep -qE 'PASS|PASS|passed|passed'; then
    return 0
  fi
  return 1
}

# run_gates <task-index> <strict> — run every gate that applies after that task, print all of
# their output, and return 0 only if all of them passed. Runs the whole set even after one
# fails, so the executor sees every failure at once rather than the first.
run_gates() {
  local n="$1" strict="$2" rc=0 i g
  if [ ! -d "$SPEC_DIR/tasks" ]; then
    ( cd "$ROOT" && STRICT="$strict" bash "$VERIFY" 2>&1 )
    return $?
  fi
  for i in $(seq 1 "$n"); do
    g="$(_gate_for "$i")" || { echo "ralph: task $i has no gate" >&2; return 3; }
    ( cd "$ROOT" && STRICT="$strict" bash "$g" 2>&1 ) || rc=1
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
fi

hb_init; log_init; hb_write starting
# Keep the heartbeat alive through the long model calls, and make sure it stops when this
# loop does — a heartbeat that outlives its loop would make a dead agent look busy forever.
hb_tick_start
trap 'hb_tick_stop' EXIT INT TERM
bus_init; bus_open "$(basename "$SPEC_DIR")"

while IFS= read -r task || [ -n "$task" ]; do
  [ -z "${task// }" ] && continue
  _check_cancel
  echo "════════ TASK: $task ════════"
  HB_TASK="$task"; HB_TIDX=$((HB_TIDX + 1)); hb_write running
  # Skip-satisfied: if the task's gate already passes and we're not forcing, skip without
  # invoking the executor or consuming an attempt. Announce in the same format as other tasks.
  if _task_satisfied "$HB_TIDX"; then
    echo "  ✓ $task skipped (gate already passed)"
    HB_ATTEMPT="skipped"; LOG_OUTCOME="skipped"; LOG_STARTED="$(date +%s)"; LOG_ENDED="$LOG_STARTED"; LOG_RECORDED=1
    log_meta "$HB_TASK" "$HB_ATTEMPT"
    hb_write passed true
    feedback=""
    continue
  fi
  feedback=""; passed=0; retry_init
  for attempt in $(seq 1 $((RETRIES + 1))); do
    _check_cancel
    HB_ATTEMPT="$attempt"; LOG_STARTED="$(date +%s)"; LOG_RECORDED=""; hb_write running
    prompt="${SHEET:+$SHEET

}Read $SPEC. Implement ONLY this one task, nothing else: ${task}
Follow the spec's section 10 acceptance criteria and section 7 norms EXACTLY.
Do not run git add, git commit, or git stash — the loop owns the index.
Do not touch anything outside this task's scope. Reuse existing patterns; never invent
URLs/UIDs. When done, stop.${feedback}"

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


    # A run that changed NOTHING is not a pass. The stillborn-log guard above catches an
    # executor that never STARTED; this catches one that started, was blocked, and wrote
    # nothing. It matters because a pend-staged gate (specs/TEMPLATE.md §11) is satisfied
    # by an empty tree — every check pends — so a no-op attempt sails through and the task
    # after it inherits the work plus a spent retry budget. Observed 2026-08-12 on
    # specs/model-watch: opencode asked to Read `/specs/model-watch/spec.md` (absolute,
    # from filesystem root), opencode auto-rejected it as an external directory, the model
    # produced no file, and the staged gate passed T1 with "nothing to commit".
    if [ -z "$(git -C "$ROOT" status --porcelain -- . ':!.evidence' 2>/dev/null)" ]; then
      echo "  ✗ attempt $attempt changed nothing — a no-op is a failure, not a pass" >&2
      LOG_OUTCOME="noop"; LOG_ENDED="$(date +%s)"; LOG_RECORDED=1; log_meta "$HB_TASK" "$attempt"
      hb_write failed false
      feedback="
A previous attempt produced NO file changes at all. If a tool call was rejected, use
paths RELATIVE to the repo root (specs/... not /specs/...). Do the work this time."
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
      LOG_OUTCOME="passed"; LOG_ENDED="$(date +%s)"; LOG_RECORDED=1; log_meta "$HB_TASK" "$attempt"
      git -C "$ROOT" add -A
      # NOT "ralph(qwen)". This line named one executor while the same run filed its
      # evidence under another — a codex run committed as qwen. loop-index.py had already
      # been generalised to read any "word(word):" prefix precisely because "a tool that
      # names one executor is a tool that stops working when you change executors"
      # (loop-index.py:160); the READER was fixed and the WRITER was not. git log is the
      # record a human reads first, so it was the copy that lied.
      git -C "$ROOT" commit -q -m "ralph($RALPH_AGENT): ${task%%:*} — ${task#*: }" || true
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
        echo "WARN: no $(basename "$_idx") after ${HB_TASK%% *} — the record was not collected" >&2
      elif ! grep -q "\"task\": *\"${HB_TASK%% *}\"" "$_idx" 2>/dev/null; then
        echo "WARN: $(basename "$_idx") has no row for ${HB_TASK%% *} — indexing ran but did not record this task" >&2
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
    git -C "$ROOT" reset -q -- . 2>/dev/null || true   # reset index to HEAD so checkout -- can drop staged files
    git -C "$ROOT" checkout -- . 2>/dev/null || true   # reset tracked changes from the bad attempt
    git -C "$ROOT" clean -fd -- . 2>/dev/null || true  # ...and untracked files/dirs it created —
    # `checkout --` alone leaves these behind, letting an out-of-scope file from attempt N
    # survive into attempt N+1 (and even arm a later task's PEND-gated checks early — see
    # the rom-library-structure dogfood PR for the real failure this caused).
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
       LOG_OUTCOME="failed"; LOG_ENDED="$(date +%s)" && log_meta "$HB_TASK" "$attempt"
       hb_write stopped false; log_where
   bus_say "✋ STOP — '${task%%:*}' failed verify after $((RETRIES + 1)) attempts. Needs a human."
   exit 2
fi

hb_write done true
bus_say "done — ${HB_TOTAL:-?}/${HB_TOTAL:-?} tasks passed verify on $(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null). Branch ready for PR review."
echo "════════ all tasks passed verify — branch ready for PR review ════════"
git -C "$ROOT" log --oneline -"$(grep -cve '^[[:space:]]*$' "$TASKS")"
