#!/usr/bin/env bash
# T1 — sourcing assert.sh is the protection.
#
# Ids are two-digit: gate-selftest matches `FAIL.*<id>` as a SUBSTRING, so past nine assertions
# ac1 aliases ac10 and a mutant is reported killed by a neighbour's failure.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829c-hermetic-gate/lib/fixtures.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac00: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi
A="$ROOT/specs/lib/assert.sh"
trap 'stub_stop' EXIT

# ── ac01: every quarantined variable is gone after sourcing ──────────────────────────────────
# A CHILD shell, so this measures what a gate's own environment looks like rather than what this
# gate happens to have already unset by sourcing assert.sh itself at the top.
_left="$(env HARNESS_REPORT_URL=x HARNESS_REPORT_TOKEN=x RALPH_FORCE_ALL=1 \
              RALPH_FORCE_FROM=2 RALPH_SATISFIED_TIMEOUT=9 \
           bash -c '. "$1" >/dev/null 2>&1; for v in '"$QUARANTINED"'; do
                      eval "[ -n \"\${$v:-}\" ] && printf \"%s \" $v"; done' _ "$A" 2>/dev/null)"
if [ -n "$_left" ]; then
  no "ac01: still set after sourcing assert.sh: $_left — a gate launched from a harness container inherits these, and every one of them changes what a fixture measures"
else
  ok "ac01: sourcing assert.sh clears the quarantined set"
fi

# ── ac02: what a gate spawns cannot reach a configured endpoint ──────────────────────────────
# THE assertion of this spec, and an absence — so it needs TWO controls, not one.
#
# The first draft had only the stub control (a direct POST, proving the server records). It
# PASSED on a tree where no reset exists, because the probe itself never posted: an empty log
# read as "hermetic" when it meant "my probe does nothing". That is the exact defect this spec
# was written to remove, committed by its own gate, one control short.
#
#   control A  the stub records            — a direct POST must appear
#   control B  the probe posts             — the SAME probe, without assert.sh, must appear
#   measure    the probe with assert.sh    — must appear nowhere
#
# Control B is the one that was missing. Without it, every way of breaking the probe reads as a
# pass.
_probe() {   # _probe <source-assert:yes|no>  -> posts via the real reporting path
  # The inner script is SINGLE-quoted and everything it needs arrives as a positional. Written
  # with double quotes first, where the OUTER shell expanded $1 and $2 before the inner bash ever
  # saw them: $1 became the yes/no flag and $2 was unset, so the probe died on `set -u` and both
  # controls silently stopped running.
  env HARNESS_REPORT_URL="$STUB_URL" HARNESS_REPORT_TOKEN=tok RALPH_LOG=on \
      RALPH_LOG_DIR="$T/ev" RALPH_AGENT=gate ROOT="$T" \
    bash -c '
      [ "$1" = yes ] && . "$2" >/dev/null 2>&1
      . "$3" >/dev/null 2>&1
      log_init >/dev/null 2>&1 || true
      printf hi > "$4/art.txt"
      command -v ralph_log_artifact_push >/dev/null 2>&1 \
        && ralph_log_artifact_push gate "$4/art.txt" T1 1 >/dev/null 2>&1
      exit 0' _ "$1" "$A" "$ROOT/scripts/ralph-log.sh" "$T" 2>/dev/null || true
}

stub_start
if [ -z "${STUB_URL:-}" ] || [ "$STUB_URL" = "http://127.0.0.1:" ]; then
  no "ac02: the stub server never came up, so nothing below could be measured"
else
  curl -sS -X POST --data 'x' "$STUB_URL/control" >/dev/null 2>&1 || true
  if [ "$(stub_hits)" -lt 1 ]; then
    no "ac02: control A failed — a direct POST did not reach the stub, so the recorder is broken and an empty log proves nothing"
  else
    : > "$STUB_LOG"; _probe no; _n_open="$(stub_hits)"
    : > "$STUB_LOG"; _probe yes; _n_shut="$(stub_hits)"
    if [ "$_n_open" -lt 1 ]; then
      no "ac02: control B failed — the probe reached the stub 0 times even with NO reset in the way, so it does not exercise the reporting path at all. An empty log in the measured case would mean nothing. Re-anchor the probe before trusting this check"
    elif [ "$_n_shut" -gt 0 ]; then
      no "ac02: $_n_shut request(s) reached the endpoint the launching shell configured (the same probe reaches it $_n_open time(s) unprotected). A gate's fixtures post to the real coordinator — eight rows keyed spec=fx landed on the live board this way, sharing harness#46's eviction, so they can push out the record of an actual run"
    else
      ok "ac02: the probe reaches the endpoint $_n_open time(s) unprotected and 0 times after sourcing assert.sh"
    fi
  fi
fi

# ── ac03: silent on load, and does not exit ──────────────────────────────────────────────────
# assert.sh's own header requires it. A reset that prints breaks every assertion in other specs
# that compares a gate's stdout, and one that exits takes the gate with it.
_out="$( env HARNESS_REPORT_URL=x RALPH_FORCE_ALL=1 bash -c '. "$1"; echo READY' _ "$A" 2>&1 )"
case "$_out" in
  READY) ok "ac03: sourcing assert.sh prints nothing and returns" ;;
  "")    no "ac03: the shell never reached READY — sourcing assert.sh exits, which takes every gate with it" ;;
  *)     no "ac03: sourcing assert.sh printed [${_out%READY}] — a gate's stdout is compared in other specs' assertions, so anything on load is a defect in those" ;;
esac

# ── ac04: the reset bounds the LAUNCHING SHELL, not the gate ─────────────────────────────────
# Several gates configure these deliberately for the case under test, ac02 above included. A
# reset that also clobbered those would make this spec's own gate impossible to write.
_after="$( env HARNESS_REPORT_URL=parent bash -c '. "$1"; HARNESS_REPORT_URL=mine; printf %s "${HARNESS_REPORT_URL:-EMPTY}"' _ "$A" 2>/dev/null )"
case "$_after" in
  mine)   ok "ac04: a value set after sourcing survives" ;;
  parent) no "ac04: the parent's value survived — the reset did not run" ;;
  *)      no "ac04: a value the gate set after sourcing was lost [$_after]. Gates configure these on purpose; a reset that outlives the source line makes the deliberate case untestable" ;;
esac

# ── ac05: the boundary covers gates that source nothing ──────────────────────────────────────
# assert.sh reaches the 31 per-task gates that source it and NONE of the 24 monolithic ones —
# 20260801a..20260828j define ok/no/pend inline. Several of those drive the real loop, which
# makes them precisely the gates that can post to a coordinator. So run_gates clears the set
# before invoking any gate, whatever that gate sources.
#
# Asserted on run_gates' own region with comments stripped: every one of these variable names
# appears in ralph-build.sh's prose, so a whole-file grep passes with no reset at all.
RB="$ROOT/scripts/ralph-build.sh"
if [ ! -f "$RB" ]; then
  no "ac05: scripts/ralph-build.sh is missing"
else
  _rg="$(strip_comments "$RB" | grep -n 'run_gates()' | head -1 | cut -d: -f1)"
  if [ -z "$_rg" ]; then
    no "ac05: could not find run_gates() in ralph-build.sh — this check is not measuring what it claims and must be re-anchored"
  else
    # POSITION, not presence. The first draft grepped the region for the construct and PASSED on
    # a mutant that put the reset at the END of run_gates — after the gate had already run with
    # the launching shell's environment. "The reset is in this function" and "the gate ran
    # without those variables" are two different claims and only the second one is the feature.
    _body="$(strip_comments "$RB" | sed -n "${_rg},$(( _rg + 30 ))p")"
    _at="$(printf '%s\n' "$_body" | grep -nE '(env +-u|unset)[^|]*HARNESS_REPORT_URL' | head -1 | cut -d: -f1)"
    _inv="$(printf '%s\n' "$_body" | grep -nE 'bash +"\$(VERIFY|g)"' | head -1 | cut -d: -f1)"
    if [ -z "$_at" ]; then
      no "ac05: run_gates invokes gates with the launching shell's environment intact. 24 monolithic gates source nothing, so assert.sh cannot reach them, and several of them drive the real loop"
    elif [ -z "$_inv" ]; then
      no "ac05: could not find where run_gates invokes a gate, so 'the reset comes first' is unmeasurable here and must be re-anchored rather than assumed"
    elif [ "$_at" -gt "$_inv" ]; then
      no "ac05: run_gates clears the set at line $_at but invokes the gate at line $_inv — after the fact. The gate already ran with everything inherited, which was the only moment that mattered"
    else
      ok "ac05: run_gates clears the quarantined set before it invokes a gate"
    fi
  fi
fi

gate_done
