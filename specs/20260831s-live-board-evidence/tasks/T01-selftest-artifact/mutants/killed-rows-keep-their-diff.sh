# MUTANT: ac4
# TARGET: scripts/ralph-log.sh
# WHY: clips every diff instead of dropping the killed ones. Uniform, simpler to read, and it
# WHY: multiplies the payload by the number of mutants that behaved — straight into the byte cap
# WHY: whose truncator cuts a JSON line in half.
# shellcheck shell=bash
# ralph-log.sh — keep the evidence from a failed attempt. SOURCED, not executed.
#
# WHY: ralph sent the model's entire output to /dev/null, and resets the working tree after
# EVERY failed attempt — including the last one. So a loop that stopped left a stopped loop, an
# empty diff, and nothing else. On 2026-07-22 a run failed all three attempts on one task and it
# was impossible to tell whether the model had written the wrong code, or written the right code
# in the wrong place. Those point at completely different fixes; without the artefact you can
# only re-roll and hope.
#
# A gate that says "no" without saying what it saw is only half an inspector.
#
# Writes, per failed attempt, to $RALPH_LOG_DIR/<spec-slug>/<agent>-<pid>/:
#   <task>-attempt<n>.log    the executor's own stdout+stderr
#   <task>-attempt<n>.diff   the verify output, the tracked diff, and the untracked file list
#                            — captured BEFORE the reset that would otherwise erase it
#
# <spec-slug> is the spec directory's basename (`specs/asset-ladder` -> `asset-ladder`), and it
# is a DIRECTORY LEVEL rather than part of the leaf name. Two reasons, in order:
#
#   1. A flat root grows without bound and without shape. Five specs over one night produced
#      48 sibling `qwen-<pid>` directories; at a few hundred runs `ls` alone is unreadable and
#      every consumer pays to enumerate the whole store to answer a question about one spec.
#      A level you can walk down costs nothing and bounds every listing to one feature.
#   2. It keeps the leaf EXACTLY `<agent>-<pid>`, which is what every existing reader parses.
#      `loop-index.py` takes the pid with `basename(d).split("-", 1)[1]`; folding the slug into
#      the leaf instead (`qwen-asset-ladder-37173`) yields "asset-ladder-37173", a pid that
#      matches no status file — the index would still generate, with every run unattributed.
#      Nesting changes the path and leaves the name alone, so nothing downstream has to know.
#
# `harness_roots()` in loop-index.py already descends exactly one level and already skips
# entries prefixed `qwen-`/`codex-` as run dirs rather than scopes, so it discovers this layout
# unchanged. `.evidence/judge/<spec>/` and `.evidence/supervisor/<spec>/` are keyed the same
# way, so all four subtrees now group on one identifier.
#
# <task> is the TASK LABEL (T21), not the queue position. Those coincide on a cold start and
# diverge the moment anything is requeued: a single-task rerun and a fourteen-task run both
# used to write `T1-attempt1.log`, so the name collided across every run in the root and named
# a different task nearly every time. Twelve surviving T21 logs across five runs had to be
# re-attributed by parsing the PID out of the directory name (2026-08-24 observability brief,
# D1). The queue index still rides in the JSON status, where it is cheap and unambiguous.
#
# The ROOT is scoped per project by living inside the target repo's own `.evidence/` (D2).
# One shared directory collected three unrelated repos' runs into a single evidence bundle,
# distinguishable only by grepping the transcripts for a working directory — and a recycled
# PID would have merged two projects into one directory outright. An explicit RALPH_LOG_DIR is
# used verbatim; only the DEFAULT is scoped, so every gate that redirects this channel to a
# temp dir keeps working unchanged. Project scope is the root, feature scope is the slug level
# below it, and the PID identifies the process — three questions, three levels, no overloading.
#
# Best-effort, same contract as ralph-status.sh: a full disk or a read-only mount can never fail
# the loop it is reporting on. RALPH_LOG=off disables.
#
# Evidence egress: on 20260828o-evidence-egress, the loop now pushes attempt artifacts over the
# same outbound channel used for status (20260828m-worker-channel). Artifacts are pushed at the
# moment each is written — prompt, patch (passing attempts), diff (failing attempts), gate output,
# meta, and the executor transcript — never later, never in bulk. A run that dies mid-attempt still
# delivers everything written up to the crash.
#
# Configuration:
#
#   HARNESS_REPORT_URL           same URL as status; unset means push nothing, print nothing
#   HARNESS_REPORT_TOKEN         same bearer token as status; optional
#   HARNESS_ARTIFACT_MAX_BYTES   cap per artifact; default 1048576 (1 MiB)
#
# When an artifact exceeds the cap it is clipped at (max_bytes - 1024) and a marker is appended:
#
#     --- artifact truncated (original: XXXX bytes, clipped at YYYY bytes) ---
#
# Truncation is visible so a reader can tell a complete artifact from a clipped one; a silently
# short diff is as bad as no diff at all.
#
# This channel ends at the POST. It does not decide how artifacts are stored, indexed, retained,
# or served — that is the coordinator's concern. It does not add polling, controls, or any inbound
# path. It does not introduce a second identity: artifacts are keyed by the run key the loop
# already has, plus the task and attempt.

# _ralph_slug <spec-dir> — the feature identifier: the spec directory's basename, lowercased
# and reduced to a single filename-safe path component ("specs/Asset Ladder/" -> "asset-ladder").
# Falls back to "nospec" so the level is never empty and a run can never land in the root.
#
# Deliberately duplicated verbatim in ralph-status.sh. Both files are best-effort helpers whose
# contract is that either may be absent without breaking the loop, so neither may depend on the
# other. Keep the two copies identical.
#
# Derived at runtime from SPEC_DIR — never a literal. specs/20260825a-evidence-convention AC-5 forbids any
# project's name appearing in a harness file, and that is the whole point: the harness learns the
# feature from the target repo it was pointed at.
_ralph_slug() {
  local s="${1:-}"
  s="${s%/}"; s="${s##*/}"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-' \
        | sed -e 's/-\{2,\}/-/g' -e 's/^[-.]*//' -e 's/-*$//' | cut -c1-40)"
  printf '%s' "${s:-nospec}"
}

# _ralph_host — the host discriminator for fleet-wide uniqueness.
# Returns the value from run-key.sh (first non-empty: RALPH_HOST_ID, hostname, "unknown").
# Sanitised to [A-Za-z0-9._-]; every other byte becomes _.
# Used by log_init() and log_meta() to build the run directory path and run_key field.
#
# Deliberately duplicated verbatim in ralph-status.sh. Both files are best-effort helpers whose
# contract is that either may be absent without breaking the loop, so neither may depend on the
# other. Keep the two copies identical.
_ralph_host() {
  if [ -n "${RALPH_HOST_ID:-}" ]; then
    printf '%s' "$RALPH_HOST_ID"
  else
    local _hn
    _hn=$(hostname 2>/dev/null)
    if [ -n "$_hn" ]; then
      printf '%s' "$_hn"
    else
      printf '%s' "unknown"
    fi
  fi | tr -c 'A-Za-z0-9._-' '_'
}

log_init() {
  LOG_OK=0
  [ "${RALPH_LOG:-on}" = "on" ] || { echo "logs: off (RALPH_LOG=off)" >&2; return 0; }
  LOG_ROOT="${RALPH_LOG_DIR:-$(git -C "${ROOT:-.}" rev-parse --show-toplevel 2>/dev/null || echo "$HOME/.harness")/.evidence/runs}"
  # Prefer the heartbeat's slug when ralph-status.sh is loaded, so the two stores can never
  # disagree about which feature a run belongs to; derive our own when it is absent.
  LOG_SLUG="${HB_SLUG:-$(_ralph_slug "${SPEC_DIR:-}")}"
  LOG_DIR="$LOG_ROOT/$LOG_SLUG/$(_ralph_host)/${HB_AGENT:-${RALPH_AGENT:-agent}}-$$"
  # Floor the run clock here so `started` is a measurement from the moment logging exists, not
  # from whenever a caller remembers to stamp it. `:-` so the per-attempt stamp in
  # ralph-build.sh (which is more precise) still wins; this only covers the caller that forgets.
  LOG_STARTED="${LOG_STARTED:-$(date +%s)}"
  mkdir -p "$LOG_DIR" 2>/dev/null || { echo "logs: unavailable ($LOG_DIR not writable)" >&2; return 0; }
  local _log_basename; _log_basename="${LOG_DIR##*/}"
  local _log_parent="${LOG_DIR%/*}"
  [ -w "$_log_parent" ] && ln -sfn "$_log_basename" "$_log_parent/latest" 2>/dev/null || true

# Cap accumulation the same way the heartbeat does — these hold whole model transcripts.
#
# DEPTH 3, not 2: a run directory now lives at <root>/<slug>/<host>/<agent>-<pid>, so depth 2
# is the host. Reaping there would delete a host's entire run history in one stroke the moment
# the host went quiet — and a directory's mtime tracks its newest child, so an active host
# would look immortal right up until it didn't. Expiry is per run; only whole runs age out.
#
# -mindepth is also what keeps `find X -maxdepth N -type d` from matching X itself, which
# would rm -rf the entire store. That has never fired (the mkdir -p above refreshes the root's
# mtime first), but the guard costs nothing and the failure mode is total.
find "$LOG_ROOT" -mindepth 3 -maxdepth 3 -type d -mmin "+${RALPH_LOG_KEEP_MIN:-4320}" -exec rm -rf {} + 2>/dev/null || true
# The OLDER <slug>/<agent>-<pid> layout still exists on disk and sits at depth 2, where the reap
# above cannot see it — so moving the reap from 2 to 3 stopped collecting those corpora entirely
# rather than widening what it collects. Depth 2 cannot simply be reaped as well: it holds BOTH
# a legacy run AND a host directory, and a host's mtime tracks its newest child, so an aged host
# would be deleted with its live runs inside it.
#
# The discriminator is STRUCTURE, not name. A run directory holds files and no subdirectories; a
# host directory holds run directories. A name test cannot do this — <agent>-<pid> is
# indistinguishable from a Kubernetes pod name like `harness-run-7`, which is exactly why the
# host level is excluded by position everywhere else in the harness.
for _d in "$LOG_ROOT"/*/*; do
  [ -d "$_d" ] || continue
  find "$_d" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -q . && continue   # a host, not a run
  if find "$_d" -maxdepth 0 -type d -mmin "+${RALPH_LOG_KEEP_MIN:-4320}" 2>/dev/null | grep -q .; then
    rm -rf "$_d" 2>/dev/null || true
  fi
done
  # …then sweep up whatever the reap emptied, so nothing is left as a husk. TWO passes, rooted at
  # the STORE ROOT rather than at our own slug: a wholly-expired OTHER spec keeps an empty host
  # directory, which keeps its slug directory non-empty, so the slug survives unless the host is
  # removed first. Inner level, then outer — that order is what lets the second pass see an empty
  # slug at all. Ours always holds the run dir created above, so it is never a candidate.
  find "$LOG_ROOT" -mindepth 2 -maxdepth 2 -type d -empty -delete 2>/dev/null || true
  find "$LOG_ROOT" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true
  LOG_OK=1
  echo "logs: $LOG_DIR" >&2
}

# log_task <task-line> — the filename-safe label for a task ("T21: do the thing" -> "T21").
# Callers pass the whole task line; this takes the label and guarantees it is a FILENAME. A task
# title containing a slash would otherwise produce a path, and one containing a space would
# produce two arguments. Anything not a bare word collapses to `Tx`.
# Note what this deliberately does NOT do: coerce a non-`T<n>` label into one. Every tasks.txt in
# this repo labels `T<n>:`, and a run that does not will surface in `loop-doctor` as `unparsed`
# rather than as a plausible wrong number. Visible beats tidy.
log_task() {
  local t="${1:-}"; t="${t%%:*}"; t="${t%%[[:space:]]*}"
  case "$t" in
    ''|*[!A-Za-z0-9_-]*) printf 'Tx' ;;
    *)                   printf '%s' "$t" ;;
  esac
}

# log_path <task-label> <attempt> [ext] — where this attempt's artefact goes.
# Prints /dev/null when logging is unavailable, so callers can redirect unconditionally.
log_path() {
  [ "${LOG_OK:-0}" = 1 ] || { printf '/dev/null'; return 0; }
  printf '%s/%s-attempt%s.%s' "$LOG_DIR" "$(log_task "${1:-T0}")" "${2:-0}" "${3:-log}"
}

# log_patch <task-label> <attempt> — write an applyable patch for a passing attempt.
# Uses intent-to-add (`git add -A -N`) so new files appear in the diff; must precede the real
# `git add -A` that follows in the pass branch. Excludes `.evidence/` so the harness's own
# record never enters the patch.
log_patch() {
  [ "${LOG_OK:-0}" = 1 ] || return 0
  local f; f="$(log_path "$1" "$2" patch)"
  {
    git -C "${ROOT:-.}" add -A -N -- . ':!.evidence' 2>/dev/null
    git -C "${ROOT:-.}" diff -- . ':!.evidence' 2>/dev/null
  } > "$f" 2>/dev/null || { echo "$f" >&2; return 0; }
  ralph_log_artifact_push patch "$f" "$1" "$2"
}

# log_failure <task-label> <attempt> <verify-output>
# MUST be called before `git checkout -- .` / `git clean -fd`, which is the whole point: after
# the reset the evidence is gone.
log_failure() {
  [ "${LOG_OK:-0}" = 1 ] || return 0
  local f; f="$(log_path "$1" "$2" diff)"
  {
    printf '=== verify output ===\n%s\n\n' "${3:-（none captured）}"
    printf '=== tracked changes (git diff) ===\n'
    git -C "${ROOT:-.}" diff 2>/dev/null
    printf '\n=== untracked files created ===\n'
    git -C "${ROOT:-.}" ls-files --others --exclude-standard 2>/dev/null
    # …and their CONTENTS, not just their names.
    #
    # `git diff` covers tracked files only, so for any task whose deliverable is a NEW file —
    # which is most net-new work — this evidence recorded a filename and nothing else, and
    # `git clean -fd` then deleted the file. Observed 2026-08-25 on specs/asset-ladder T3:
    # three attempts each wrote VoiceCapture/SpeechAssetProbe.swift, the gate reported 16 of
    # 20 checks passing, and the run could not be replayed or salvaged because the only
    # surviving trace was the path.
    printf '\n=== untracked file contents ===\n'
    git -C "${ROOT:-.}" ls-files --others --exclude-standard -z 2>/dev/null \
    | while IFS= read -r -d '' _p; do
        case "$_p" in .evidence/*) continue ;; esac   # our own record, not the model's work
        _abs="${ROOT:-.}/$_p"
        [ -f "$_abs" ] || continue
        # Skip anything that is not text, and cap each file: this is diagnostic evidence, not
        # a backup, and one stray binary would make the whole .diff unreadable.
        if LC_ALL=C grep -qI . "$_abs" 2>/dev/null; then
          printf -- '--- %s ---\n' "$_p"
          head -c 65536 "$_abs" 2>/dev/null
          [ "$(wc -c < "$_abs" 2>/dev/null || echo 0)" -gt 65536 ] \
            && printf '\n[truncated at 64 KiB]\n'
          printf '\n'
        else
          printf -- '--- %s --- [binary, not captured]\n' "$_p"
        fi
      done
  } > "$f" 2>/dev/null || true
  ralph_log_artifact_push diff "$f" "$1" "$2"
}

# log_prompt <task-label> <attempt> <text>
# Write the prompt that preceded the model's attempt. Like log_failure, call before the reset.
log_prompt() {
  [ "${LOG_OK:-0}" = 1 ] || return 0
  local f; f="$(log_path "$1" "$2" prompt.md)"
  { printf '%s' "$3"; } > "$f" 2>/dev/null || true
  ralph_log_artifact_push prompt "$f" "$1" "$2"
}

# log_gate <task-label> <attempt> <output> <rc>
# Write the gate's output and exit status to <stem>.gate.txt.
# NEVER invokes verify.sh; records output its caller already captured.
log_gate() {
  [ "${LOG_OK:-0}" = 1 ] || return 0
  local f; f="$(log_path "$1" "$2" gate.txt)"
  { printf '%s\n' "$3"; printf '%s\n' "---GATE-RC---"; printf '%s\n' "$4"; } > "$f" 2>/dev/null || { echo "$f" >&2; return 0; }
  ralph_log_artifact_push gate "$f" "$1" "$2"
}

# ralph_log_artifact_push <kind> <file> <task-label> <attempt> — POST an artifact to the coordinator.
# Uses same transport and safety as hb_report: silent, timeout-bounded, no output on failure.
# Does not fail if HARNESS_REPORT_URL is unset.
ralph_log_artifact_push() {
  local kind="$1" file="$2" task="$3" attempt="$4"
  local url="${HARNESS_REPORT_URL:-}"
  [ -n "$url" ] || return 0
  [ -s "${file:-}" ] || return 0
  local host; host="$(_ralph_host)"
  local agent="${HB_AGENT:-${RALPH_AGENT:-agent}}"
  local run_key="${host}/${agent}-$$"
  local task_slug; task_slug="$(log_task "$task")"
  local target="${url%/}/runs/${run_key}/attempts/${task_slug}/${attempt}/artifacts/${kind}"
  local max_bytes="${HARNESS_ARTIFACT_MAX_BYTES:-8192}"
  case "$max_bytes" in
    ''|*[!0-9]*) max_bytes=8192 ;;
    0) max_bytes=8192 ;;
  esac
  local file_size; file_size=$(wc -c < "$file" 2>/dev/null || echo 0)
  local truncated_file="$file"
  if [ "$file_size" -gt "$max_bytes" ]; then
    local tmp_trunc; tmp_trunc=$(mktemp "${TMPDIR:-/tmp}/ralph-log-trunc-XXXXXX")
    local head_bytes=$((max_bytes - 1024))
    head -c "$head_bytes" "$file" > "$tmp_trunc"
    printf '\n\n--- artifact truncated (original: %s bytes, clipped at %s bytes) ---\n' "$file_size" "$max_bytes" >> "$tmp_trunc"
    truncated_file="$tmp_trunc"
  fi
  if command -v curl >/dev/null 2>&1; then
    local -a hdr=(-H 'Content-Type: application/octet-stream')
    local tok="${HARNESS_REPORT_TOKEN:-}"
    [ -n "$tok" ] && hdr+=(-H "Authorization: Bearer $tok")
    curl -s -o /dev/null -X POST --connect-timeout 2 --max-time 3 \
      "${hdr[@]}" --data-binary "@$truncated_file" "$target" >/dev/null 2>&1 || true
  elif command -v python3 >/dev/null 2>&1; then
    RLA_F="$truncated_file" RLA_T="$target" RLA_K="$tok" python3 -c '
import os, urllib.request
try:
    h = {"Content-Type": "application/octet-stream"}
    if os.environ.get("RLA_K"):
        h["Authorization"] = "Bearer " + os.environ["RLA_K"]
    with open(os.environ["RLA_F"], "rb") as fh:
        body = fh.read()
    urllib.request.urlopen(
        urllib.request.Request(os.environ["RLA_T"], body, h, method="POST"), timeout=3)
except Exception:
    pass
' >/dev/null 2>&1 || true
  fi
  [ "$truncated_file" != "$file" ] && rm -f "$truncated_file"
  return 0
}

# _log_report <file> — POST an attempt record outward. Never fails, never stalls, never prints.
#
# Fire-and-forget by contract: an unreachable coordinator, a refused connection, a 500 or a
# hang must not fail, delay or alter the run. `run-loop.sh` has to keep working on a laptop
# with no infrastructure at all, which is why an unset HARNESS_REPORT_URL returns before
# anything happens and leaves the run byte-identical to what it is today.
#
# On the header quoting: the arguments go in an ARRAY. Quotes are literal after expansion,
# so building the flag as a string —
#     auth="-H 'Authorization: Bearer $tok'" ; curl $auth ...
# — word-splits into `-H`, `'Authorization:`, `Bearer`, `tok'`: a malformed header plus two
# arguments curl reads as URLs. The `${tok:+-H "Authorization: Bearer $tok"}` shorthand fails
# the same way for the same reason, splitting into `-H`, `Authorization:`, `Bearer`, `tok`,
# where the bare `Authorization:` is curl's syntax for REMOVING the header. An array is the
# only form that survives, because its elements are never re-split.
_log_report() {
  local url="${HARNESS_REPORT_URL:-}"
  [ -n "$url" ] || return 0
  [ -s "${1:-}" ] || return 0
  local key; key="$(_ralph_host)/${HB_AGENT:-${RALPH_AGENT:-agent}}-$$"
  local target="${url%/}/runs/$key/attempts"
  local tok="${HARNESS_REPORT_TOKEN:-}"
  if command -v curl >/dev/null 2>&1; then
    local -a hdr=(-H 'Content-Type: application/json')
    [ -n "$tok" ] && hdr+=(-H "Authorization: Bearer $tok")
    curl -s -o /dev/null -X POST --connect-timeout 2 --max-time 3 \
      "${hdr[@]}" --data-binary "@$1" "$target" >/dev/null 2>&1 || true
  elif command -v python3 >/dev/null 2>&1; then
    # The token goes through the ENVIRONMENT, not argv: argv is visible in `ps` to anyone on
    # the box, and a secret that leaks through the process table has still leaked.
    HB_T="$target" HB_B="$1" HB_K="$tok" python3 -c '
import os, urllib.request
try:
    h = {"Content-Type": "application/json"}
    if os.environ.get("HB_K"):
        h["Authorization"] = "Bearer " + os.environ["HB_K"]
    with open(os.environ["HB_B"], "rb") as fh:
        body = fh.read()
    urllib.request.urlopen(
        urllib.request.Request(os.environ["HB_T"], body, h, method="POST"), timeout=3)
except Exception:
    pass
' >/dev/null 2>&1 || true
  fi
  return 0
}

# log_meta <task-label> <attempt> — write the per-attempt metadata JSON.
# Uses jq -n with --arg/--argjson so a quote in a task label or binding path does not produce
# invalid JSON. Every field is always emitted; null means unmeasurable, 0 means measured-zero.
log_meta() {
  [ "${LOG_OK:-0}" = 1 ] || return 0
  [ -x "$(command -v jq 2>/dev/null)" ] || { echo "logs: jq unavailable" >&2; return 0; }
  local f; f="$(log_path "$1" "$2" json)"
  # ── Floors ──────────────────────────────────────────────────────────────────────────────
  # 20260828e R1 ("every attempt record carries one of four outcomes, never the empty string")
  # and R3/R4 (the timing pair is coherent, duration_s non-negative) are properties of the
  # RECORD. That makes them the writer's job, not a rule five call sites must each remember —
  # and a sixth caller, the fleet dispatcher, is on the way. #19 fixed the call sites; a record
  # emitted by a caller that forgets still violated R1, which is what the gate caught.
  local _out _st _en _dur
  # No stamp reached means the attempt ended before any of the five ending points — which is
  # precisely "died before producing an outcome". Never "": ADR-001 D6 reads an unknown outcome
  # as a failure, and it cannot do that with a field no branch matches.
  _out="${LOG_OUTCOME:-stillborn}"
  _st="${LOG_STARTED:-0}"; _en="${LOG_ENDED:-0}"
  # Writing the record IS the end of the attempt, so `now` is a measurement and not a guess.
  # The same test catches a LOG_ENDED left stale by a previous attempt, which would otherwise
  # produce a NEGATIVE duration — the one value R4 can never accept.
  { [ "$_en" -gt 0 ] && [ "$_en" -ge "$_st" ]; } 2>/dev/null || _en="$(date +%s)"
  # null still means "not measurable" (§3.2): reachable only with no start, i.e. log_meta called
  # without log_init — in which case LOG_OK is 0 and we already returned. Kept for the contract.
  if [ "$_st" -gt 0 ] 2>/dev/null; then _dur="$((_en - _st))"; else _dur=null; fi
  {
    jq -n \
      --arg host "$(_ralph_host)" \
      --arg run_key "$(_ralph_host)/${HB_AGENT:-${RALPH_AGENT:-agent}}-$$" \
      --arg run_id "${LOG_DIR##*/}" \
      --arg run_label "$([ -n "${RUN_LABEL:-}" ] && printf '%s' "$RUN_LABEL" | jq -R . || jq -n null)" \
      --arg repo "$([ -n "${ROOT:-}" ] && basename "$ROOT" || echo null)" \
      --arg spec "$([ -n "${SPEC_DIR:-}" ] && basename "$SPEC_DIR" || echo null)" \
      --arg task "$1" \
      --argjson attempt "$2" \
      --arg binding "${RALPH_EXEC_CMD:-}" \
      --arg agent "${RALPH_AGENT:-}" \
      --argjson started "$_st" \
      --argjson ended "$_en" \
      --argjson duration_s "$_dur" \
      --argjson exec_rc "${LOG_EXEC_RC:-0}" \
      --argjson verify_rc "$([ -n "${LOG_VERIFY_RC:-}" ] && echo "$LOG_VERIFY_RC" || jq -n null)" \
      --arg outcome "$_out" \
      --argjson bytes_prompt "$([ -f "$(log_path "$1" "$2" prompt.md)" ] && wc -c < "$(log_path "$1" "$2" prompt.md)" || echo null)" \
      --argjson bytes_transcript "$([ -f "$(log_path "$1" "$2" log)" ] && wc -c < "$(log_path "$1" "$2" log)" || echo null)" \
      --argjson bytes_patch "$([ -f "$(log_path "$1" "$2" patch)" ] && wc -c < "$(log_path "$1" "$2" patch)" || echo null)" \
      '{
        run_id: $run_id,
        run_label: $run_label,
        repo: $repo,
        spec: $spec,
        task: $task,
        attempt: $attempt,
        binding: $binding,
        agent: $agent,
        started: $started,
        ended: $ended,
        duration_s: $duration_s,
        exec_rc: $exec_rc,
        verify_rc: $verify_rc,
        outcome: $outcome,
        bytes_prompt: $bytes_prompt,
        bytes_transcript: $bytes_transcript,
        bytes_patch: $bytes_patch,
        host: $host,
        run_key: $run_key
      }'
  } > "$f" 2>/dev/null || true
  ralph_log_artifact_push meta "$f" "$1" "$2"
  _log_report "$f"
}

# log_where — one line telling a human where to look. Called on STOP.
log_where() {
  [ "${LOG_OK:-0}" = 1 ] || return 0
  echo "   evidence: $LOG_DIR  (.log = what the model did, .diff = what it changed + why verify said no)" >&2
}

# ralph_log_selftest_push <evid-dir> <spec-slug> <task-label> <attempt> — ship the run's
# gate-selftest verdicts over the artifact channel (20260831s).
#
# The rows exist already: 20260831u runs each task's mutant corpus the moment that task's gate
# first goes green, and SELFTEST_EVID appends them to <evid>/selftest-<spec-slug>.jsonl. They
# never left the worker, which for a dispatched Job is a container that is gone moments after
# it exits — and the run whose gate a mutant SURVIVED is precisely the run whose evidence
# matters most.
#
# WHICH ROWS. The evidence file is append-only across tasks AND runs, so sending the file
# would send every previous task's verdicts every time. One gate-selftest invocation writes
# exactly one run_id, and the selftest that just finished wrote the last one — so the last
# run_id in the file selects this task's rows. In-loop these are strictly sequential; a
# concurrent selftest writing the same file would break that assumption, and nothing does.
#
# COMPACTION. `diff` is the only large field, and it is dropped from every KILLED row: a killed
# mutant's diff is reconstructible from the corpus file committed beside the gate. On every
# other verdict it is kept — that diff is how the mutant was formed, and there is nowhere else
# to read it — clipped to SELFTEST_ARTIFACT_DIFF_LINES (default 40). This is what keeps the
# normal case (everything killed) far under HARNESS_ARTIFACT_MAX_BYTES, whose truncator clips
# at a byte offset and would otherwise cut a JSON line in half.
#
# Fire-and-forget, like every push in this file: an unset HARNESS_REPORT_URL returns before
# anything happens, and no failure here is allowed to alter the run.
ralph_log_selftest_push() {
  local evid="$1" slug="$2" task="$3" attempt="$4"
  [ -n "${HARNESS_REPORT_URL:-}" ] || return 0
  local src="$evid/selftest-$slug.jsonl"
  [ -s "$src" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local tmp; tmp="$(mktemp "${TMPDIR:-/tmp}/ralph-selftest-XXXXXX")" || return 0
  SELFTEST_SRC="$src" SELFTEST_OUT="$tmp" \
  SELFTEST_CLIP="${SELFTEST_ARTIFACT_DIFF_LINES:-40}" python3 -c '
import json, os
src, out = os.environ["SELFTEST_SRC"], os.environ["SELFTEST_OUT"]
try:
    clip = int(os.environ.get("SELFTEST_CLIP") or 40)
except ValueError:
    clip = 40
if clip < 1:
    clip = 1
rows = []
with open(src, encoding="utf-8") as fh:
    for ln in fh:
        ln = ln.strip()
        if not ln:
            continue
        try:
            rows.append(json.loads(ln))
        except ValueError:
            # A corrupt line is skipped, never fatal: this push runs on the STOP path too, and
            # refusing to ship anything because one line is malformed loses the rest with it.
            continue
run_id = ""
for r in rows:
    if r.get("run_id"):
        run_id = r["run_id"]
with open(out, "w", encoding="utf-8") as fh:
    for r in rows:
        if r.get("run_id") != run_id:
            continue
        d = r.get("diff")
        if d is not None:
            if False:
                r.pop("diff", None)
            else:
                lines = d.splitlines()
                if len(lines) > clip:
                    r["diff"] = "\n".join(lines[:clip]) + \
                        "\n--- diff clipped at %d lines ---" % clip
        fh.write(json.dumps(r) + "\n")
' >/dev/null 2>&1 || true
  ralph_log_artifact_push selftest "$tmp" "$task" "$attempt"
  rm -f "$tmp" 2>/dev/null
  return 0
}
