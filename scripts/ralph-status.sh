# ralph-status.sh — durable heartbeat for ralph loops. SOURCED, not executed.
#
# Why: a ralph loop's live state (which task, which attempt, pass/fail) only
# ever existed in stdout → tmux scrollback. Nothing on disk, nothing a
# dashboard could read without attaching the tmux session. This writes one
# small JSON status file per running loop so a collector can answer "what is
# this agent doing right now?" over `docker exec cat` — no tmux, no guessing.
#
# Contract — file: $RALPH_STATUS_DIR/<spec-slug>/<host>/<agent>-<pid>.json (the root
# defaults to the target repo's own .evidence/status, scoped so two projects'
# loops cannot collide on a recycled PID; an explicit RALPH_STATUS_DIR is used
# verbatim). <spec-slug> is the spec directory's basename — the same level
# ralph-log.sh puts run dirs under, and the same key .evidence/judge/<spec>/ and
# .evidence/supervisor/<spec>/ already use, so the four stores walk alike.
# <host> is the host discriminator resolved by scripts/run-key.sh.
#
# The slug is a DIRECTORY, not part of the filename: `scripts/harness` and
# loop-index.py both parse the pid out of the leaf, and both already handle one
# level of nesting (`status/*.json` and `status/*/*.json`; harness_roots()).
# Renaming the leaf would have broken those parsers; adding a level does not.
# Environment variables:
#   RALPH_STATUS_DIR — output root (default <target-repo>/.evidence/status)
#   RALPH_STATUS_KEEP_MIN — status file retention in minutes (default 1440)
# Written
# ATOMICALLY (tmp + mv) so a reader never sees a half-written object. Fields:
#   agent pid repo branch spec task task_index total_tasks attempt
#   max_attempts phase verify_pass last_commit started updated
# phase ∈ starting | running | verifying | passed | failed | stopped | done
#       | killed | stalled | timeout          (the last three: see hb_mark)
# verify_pass ∈ true | false | null   (JSON literals, unquoted)
# started/updated/… are unix seconds.
#
# Liveness rule for a collector: a file whose phase is running|verifying but
# whose `updated` is more than a few minutes old is a DEAD loop (a killed
# process can't update its own file) — treat it as stale, not active.
#
# That rule works LIVE and is worthless afterwards: at any later date every run
# is stale, so a killed run and a completed one read identically. Whoever ends a
# loop should therefore write its epitaph — see hb_mark, and the supervisor that
# calls it. Four killed runs sat at `running` permanently before this existed
# (2026-08-24 observability brief, D5).
#
# Best-effort by design: every write is guarded so a full disk, a missing
# $HOME, or a read-only mount can NEVER fail the loop it's reporting on.

# _ralph_slug <spec-dir> — the feature identifier: the spec directory's basename,
# lowercased and reduced to a single filename-safe path component
# ("specs/Asset Ladder/" -> "asset-ladder"). Falls back to "nospec" so the level is
# never empty and a status file can never land in the root.
#
# Deliberately duplicated verbatim in ralph-log.sh. Both files are best-effort
# helpers whose contract is that either may be absent without breaking the loop, so
# neither may depend on the other. Keep the two copies identical.
#
# Derived at runtime from SPEC_DIR — never a literal. specs/20260825a-evidence-convention AC-5
# forbids any project's name appearing in a harness file, and that is the point: the
# harness learns the feature from the target repo it was pointed at.
_ralph_slug() {
  local s="${1:-}"
  s="${s%/}"; s="${s##*/}"
  s="$(printf '%s' "$s" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9._-' '-' \
        | sed -e 's/-\{2,\}/-/g' -e 's/^[-.]*//' -e 's/-*$//' | cut -c1-40)"
  printf '%s' "${s:-nospec}"
}

# Escape a string for embedding in a JSON double-quoted value.
_hb_esc() {
  printf '%s' "${1-}" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g' -e 's/\t/\\t/g'
}

# hb_init — call once after ROOT / SPEC_DIR / TASKS / RETRIES are known.
hb_init() {
  HB_AGENT="${RALPH_AGENT:-qwen}"
  HB_ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  # HB_REPO is now a PATH COMPONENT (HB_DIR below), not just a JSON field. A relative ROOT
  # would make it "." and silently un-scope the store back into the shared root — which is the
  # exact contamination the scoping exists to prevent. Resolve, then reject the degenerate cases.
  HB_REPO="$(basename "$(git -C "$HB_ROOT" rev-parse --show-toplevel 2>/dev/null \
                         || (cd "$HB_ROOT" 2>/dev/null && pwd) \
                         || printf '%s' "$HB_ROOT")" 2>/dev/null || echo '')"
  case "$HB_REPO" in ''|.|..|/) HB_REPO="unknown-repo" ;; esac
  HB_SPEC="${SPEC_DIR:-}"
  HB_TOTAL="$(grep -cve '^[[:space:]]*$' "${TASKS:-/dev/null}" 2>/dev/null || echo 0)"
  HB_MAX="$(( ${RETRIES:-2} + 1 ))"
  HB_STARTED="$(date +%s 2>/dev/null || echo 0)"
  HB_TASK=""; HB_TIDX=0; HB_ATTEMPT=0
  HB_SLUG="$(_ralph_slug "$HB_SPEC")"
   HB_HOST="$(scripts/run-key.sh 2>/dev/null || echo 'unknown')"
   HB_DIR="${RALPH_STATUS_DIR:-$(git -C "${ROOT:-.}" rev-parse --show-toplevel 2>/dev/null || echo "$HOME/.harness")/.evidence/status}"
   # The root stays addressable: the sweeps below run from it so they still span every spec,
   # not just the one this loop happens to be running. HB_DIR then descends into this run's
   # feature. Assigned in this order deliberately — evidence-convention's AC-1 gate reads the
   # FIRST `HB_DIR=` line and requires the override seam and the .evidence default to be
   # visible on it, so the root keeps that shape and the slug is appended after.
   HB_STATUS_ROOT="$HB_DIR"
   HB_DIR="$HB_DIR/$HB_SLUG/$HB_HOST"
   HB_FILE="$HB_DIR/${HB_AGENT}-$$.json"
  # Cap accumulation: drop this agent's terminal files older than a day.
  #
  # BEFORE the mkdir below, not after: unlike ralph-log.sh — whose slug directory always holds
  # the run dir it just created — this store's file is not written until the first hb_write, so
  # a slug directory created here would still be empty when the -empty sweep ran and would be
  # deleted out from under it. Sweep first, then create.
  #
  # Swept from the ROOT, not from our own slug directory. The sweep has no -maxdepth, so
  # rooting it here keeps it reaching every spec's files the way it did when the store was
  # flat; rooted at $HB_DIR it would only ever reap the spec currently being run, and any
  # feature that finished would keep its files forever — an accumulation cap that stops
  # capping the moment you move on is worse than none, because it still looks like one.
  find "$HB_STATUS_ROOT" -name "${HB_AGENT}-*.json" -mmin "+${RALPH_STATUS_KEEP_MIN:-1440}" -delete 2>/dev/null || true
  # Directories emptied by that sweep, same as ralph-log.sh, and for the same reason in two
  # passes: with <slug>/<host>/ an expired spec's slug directory is not empty until the host
  # directory inside it is gone, so the inner level has to go first. Ours gets its file below.
  find "$HB_STATUS_ROOT" -mindepth 2 -maxdepth 2 -type d -empty -delete 2>/dev/null || true
  find "$HB_STATUS_ROOT" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true
  mkdir -p "$HB_DIR" 2>/dev/null || true
}

# hb_write <phase> [verify_pass]  — emit the current status. Never fails.
# _hb_runkey — the run's identity, DERIVED from HB_FILE, never minted.
#
# HB_FILE already encodes it as .../<host>/<agent>-<pid>.json, and that name is what the
# evidence tree, the index and the status file all agree on. A second identity computed from
# `hostname` and `$$` would be a second name for one run, and two names for one run are two
# names that will disagree the moment either is written by a different process.
_hb_runkey() {
  local f="${HB_FILE:-}"
  [ -n "$f" ] || return 1
  local leaf="${f##*/}"; leaf="${leaf%.json}"
  local hostdir="${f%/*}"; hostdir="${hostdir##*/}"
  [ -n "$leaf" ] && [ -n "$hostdir" ] || return 1
  printf '%s/%s' "$hostdir" "$leaf"
}

# _hb_control — ask the coordinator whether an intent is waiting for this run.
#
# Prints the action on stdout, ALWAYS, and prints "none" whenever the answer cannot be read.
# That asymmetry is the whole design: fail OPEN on the channel, CLOSED on the intent. A 500, a
# body that is not JSON, a coordinator that is not there — each of those is a broken channel, and
# a broken channel must never be able to stop a build. Only an answer that is legibly a cancel
# stops one.
#
# This is a pull, and it has to be: nothing can connect into a worker, so an intent is collected
# rather than delivered — the same way a CI runner discovers it has been cancelled.
_hb_control() {
  local url="${HARNESS_REPORT_URL:-}"
  [ -n "$url" ] || { printf 'none'; return 0; }
  local key; key="$(_hb_runkey)" || { printf 'none'; return 0; }
  local target="${url%/}/runs/$key/control"
  local tok="${HARNESS_REPORT_TOKEN:-}" body=""
  if command -v curl >/dev/null 2>&1; then
    # Seeded non-empty on purpose: "${arr[@]}" on an empty array is an unbound-variable error
    # under `set -u` on bash before 4.4, and this file is sourced by whatever the operator runs.
    local -a args=(-s -f -m 3)
    [ -n "$tok" ] && args+=(-H "Authorization: Bearer $tok")
    body="$(curl "${args[@]}" "$target" 2>/dev/null)" || body=""
  elif command -v python3 >/dev/null 2>&1; then
    body="$(HB_T="$target" HB_K="$tok" python3 -c '
import os, sys, urllib.request
try:
    req = urllib.request.Request(os.environ["HB_T"])
    if os.environ.get("HB_K"):
        req.add_header("Authorization", "Bearer " + os.environ["HB_K"])
    sys.stdout.write(urllib.request.urlopen(req, timeout=3).read().decode("utf-8", "replace"))
except Exception:
    pass
' 2>/dev/null)" || body=""
  fi
  # Extracted with a pattern rather than a JSON parser so an unreadable body yields no match and
  # therefore "none". jq would be a second failure mode here, and its absence would read as an
  # intent rather than as a missing tool.
  local act
  act="$(printf '%s' "$body" | grep -o '"action"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 \
        | sed 's/.*"\([^"]*\)"$/\1/')"
  case "$act" in
    ''|*[!a-z-]*) printf 'none' ;;
    *)            printf '%s' "$act" ;;
  esac
  return 0
}

# _hb_report <file> — POST a status record outward. Never fails, never stalls, never prints.
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
_hb_report() {
  local url="${HARNESS_REPORT_URL:-}"
  [ -n "$url" ] || return 0
  [ -s "${1:-}" ] || return 0
  local key; key="$(_hb_runkey)" || return 0
  local target="${url%/}/runs/$key/status"
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

hb_write() {
  [ -n "${HB_FILE:-}" ] || return 0
  # The directory can vanish mid-run: .evidence/status/ is untracked, so the loop's
  # between-attempt `git clean` takes it, and hb_reap only recreates it on its own schedule.
  # Recreate rather than skip — a status file that stops updating is exactly the signal a
  # supervisor reads as "hung", and every write after the sweep was failing.
  #
  # It also has to be fixed HERE and not by silencing: the write below is
  # `} > "$HB_FILE.tmp" 2>/dev/null`, and bash applies redirections left to right, so it
  # reports the failed TARGET before `2>/dev/null` is in effect. That is why this function
  # printed an error per write for the rest of the run while its own header promised
  # "Never fails". Verified: `{ echo hi; } > /nonexistent/x 2>/dev/null` still prints.
  [ -d "${HB_FILE%/*}" ] || mkdir -p "${HB_FILE%/*}" 2>/dev/null || return 0
  local phase="${1:-running}" verify="${2:-null}" now branch commit
  now="$(date +%s 2>/dev/null || echo 0)"
  branch="$(git -C "$HB_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
  commit="$(git -C "$HB_ROOT" rev-parse --short HEAD 2>/dev/null || echo '')"
  {
    printf '{"agent":"%s","pid":%s,"repo":"%s","branch":"%s","spec":"%s",' \
      "$(_hb_esc "$HB_AGENT")" "$$" "$(_hb_esc "$HB_REPO")" \
      "$(_hb_esc "$branch")" "$(_hb_esc "$HB_SPEC")"
    printf '"task":"%s","task_index":%s,"total_tasks":%s,"attempt":%s,"max_attempts":%s,' \
      "$(_hb_esc "$HB_TASK")" "${HB_TIDX:-0}" "${HB_TOTAL:-0}" "${HB_ATTEMPT:-0}" "${HB_MAX:-0}"
    printf '"phase":"%s","verify_pass":%s,"last_commit":"%s","started":%s,"updated":%s}\n' \
      "$phase" "$verify" "$(_hb_esc "$commit")" "${HB_STARTED:-0}" "$now"
  } > "$HB_FILE.tmp" 2>/dev/null && mv -f "$HB_FILE.tmp" "$HB_FILE" 2>/dev/null || true
  _hb_report "$HB_FILE"
}

# hb_mark <status-file> <phase> — stamp a TERMINAL phase on a file this process does NOT own.
#
# For a supervisor that has just killed a hung loop. The killed process cannot write its own
# final state, so the file freezes at whatever it last said — `running`, forever. The collector's
# staleness rule papers over that while the run is recent and stops meaning anything once it is
# not. A record whose last state was written by whoever ended it needs no heuristic to read.
#
# Call it AFTER the kill, so the victim's keep-alive ticker (which dies with its parent) cannot
# race the write back to `running`. Rewrites in place, atomically, and never fails: a supervisor
# must not die because it could not annotate a log.
hb_mark() {
  local f="${1:-}" phase="${2:-killed}" now
  [ -f "$f" ] || return 0
  now="$(date +%s 2>/dev/null || echo 0)"
  sed -e "s/\"phase\":\"[^\"]*\"/\"phase\":\"$phase\"/" \
      -e "s/\"updated\":[0-9]*/\"updated\":$now/" "$f" > "$f.mark" 2>/dev/null \
    && mv -f "$f.mark" "$f" 2>/dev/null || true
}

# --- keep-alive ticker -------------------------------------------------------------------
# hb_write only fires at TRANSITIONS: task start, attempt start, verify, pass/fail. Between
# them sits a single model call bounded at OC_RUN_TIMEOUT (480s by default). So the file went
# untouched for up to eight minutes while the agent was working hardest, the collector's
# 120s staleness rule marked it dead, and pulse drew a resting atom. Watched a real run against
# the live board on 2026-07-22 and the house looked asleep the entire time.
#
# The ticker refreshes only the `updated` field, re-reading the file each pass, so it always
# carries whatever phase hb_write last wrote — no stale copy of the loop's variables.
#
# It MUST die with the loop. If a killed loop kept its heartbeat fresh, "stale means dead" —
# the collector's only liveness signal — would stop meaning anything, and a crashed agent would
# glow on the board forever. Hence the kill -0 check on the parent, plus hb_tick_stop on exit.
hb_tick_stop() {
  # `wait` inside the redirected block swallows the shell's own "Terminated: 15" job-control
  # notice, which otherwise prints on every clean exit and looks like a crash in the tmux log.
  if [ -n "${HB_TICKER:-}" ]; then
    { kill "$HB_TICKER" 2>/dev/null; wait "$HB_TICKER" 2>/dev/null; } 2>/dev/null || true
  fi
  HB_TICKER=""
}

hb_tick_start() {
  [ -n "${HB_FILE:-}" ] || return 0
  hb_tick_stop
  (
    parent=$$
    while kill -0 "$parent" 2>/dev/null; do
      sleep "${HB_TICK_SEC:-20}"
      kill -0 "$parent" 2>/dev/null || break
      [ -f "$HB_FILE" ] || continue
      now="$(date +%s 2>/dev/null || echo 0)"
      sed "s/\"updated\":[0-9]*/\"updated\":$now/" "$HB_FILE" > "$HB_FILE.tick" 2>/dev/null \
        && mv -f "$HB_FILE.tick" "$HB_FILE" 2>/dev/null
    done
  ) &
  HB_TICKER=$!
}
