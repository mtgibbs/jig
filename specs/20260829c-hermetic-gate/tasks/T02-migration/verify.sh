#!/usr/bin/env bash
# T2 — the two local copies are gone, and the central reset covers what they covered.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829c-hermetic-gate/lib/fixtures.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac00: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi
FA="specs/20260829a-executor-image-layer/lib/fixtures.sh"
FB="specs/20260829b-resume-bound/lib/fixtures.sh"
FC="specs/20260828o-evidence-egress/lib/fixtures.sh"

# ── ac01: neither fixture file still resets the set itself ───────────────────────────────────
# Scoped to instruction lines. Both files EXPLAIN the quarantine in comments that must survive —
# the incidents are the reason the list has the entries it has — so a check that reads comments
# reports a finished migration as unfinished forever.
_local=""
for f in "$FA" "$FB" "$FC"; do
  [ -f "$ROOT/$f" ] || continue
  strip_comments "$ROOT/$f" | grep -qE '(^|[^a-z_])(unset|env +-u)[^#]*HARNESS_REPORT_URL' \
    && _local="$_local $f"
done
if [ -n "$_local" ]; then
  no "ac01: still resetting the quarantined set locally:$_local — while a local copy exists the central reset is UNPROVEN, because the two gates that most need it pass on their own patches and say nothing about the file every other gate loads"
else
  ok "ac01: neither fixture file resets the quarantined set itself"
fi

# ── ac02: the central set covers everything the local copies covered ─────────────────────────
# Read from git rather than from the working tree: after T2 the local lists are gone, and
# "covers what they covered" is a claim about what they USED to say. A superset check is the
# actual safety property — an omission here is a variable that silently stops being quarantined.
_hist="$(for _f in "$FA" "$FB" "$FC"; do git -C "$ROOT" show "origin/main:$_f" 2>/dev/null; done)"
if [ -z "$_hist" ]; then
  no "ac02: could not read either fixture file from origin/main, so the superset check has nothing to compare against and its verdict would be free"
else
  # Extract from the RESET CONSTRUCTS only, not from the file. The first draft grepped every
  # (HARNESS|RALPH)_* token anywhere in both files and "found" HARNESS_DIR, RALPH_AGENT,
  # RALPH_EXEC_CMD and RALPH_LOG — variables the fixtures USE, in comments and in loop
  # invocations. It would have demanded they be quarantined, which would break every fixture
  # that sets them on purpose. The claim is about what the local copies UNSET.
  _was="$(printf '%s' "$_hist" \
           | grep -oE '(unset|env +-u)[^#]*' \
           | grep -oE '(HARNESS|RALPH)_[A-Z_]+' | sort -u)"
  # Read the central set from assert.sh, NOT from this spec's $QUARANTINED constant. The first
  # draft compared history against the constant, so it passed however assert.sh was actually
  # written — a mutant that narrowed the real set survived it. A check that reads the spec's own
  # declaration instead of the implementation measures the author's intent, which is never the
  # thing in doubt.
  _now="$(strip_comments "$ROOT/specs/lib/assert.sh" \
           | grep -oE '(unset|env +-u)[^#]*' \
           | grep -oE '(HARNESS|RALPH)_[A-Z_]+' | sort -u)"
  _missing=""
  for v in $_was; do
    case " $(printf '%s' "$_now" | tr '\n' ' ') " in *" $v "*) ;; *) _missing="$_missing $v" ;; esac
  done
  # The probe must be non-degenerate: if it found no variables at all, "nothing missing" is free.
  if [ -z "$_was" ]; then
    no "ac02: found no quarantined variables in either historical fixture — the extraction is broken, and an empty set trivially satisfies the superset check"
  elif [ -n "$_missing" ]; then
    no "ac02: the local copies covered variables assert.sh does not:$_missing — each was on a local list because it changed what a gate measured, and dropping one un-quarantines it silently"
  else
    ok "ac02: the central set covers every variable both local copies covered ($(printf '%s' "$_was" | wc -w | tr -d ' ') of them)"
  fi
fi

# ── ac03: no gate is left uncovered by BOTH placements ───────────────────────────────────────
# The first draft asked "do those two specs still see a clean environment" and 20260829a PASSED
# on its own local unset — the check could not tell "the central reset works" from "the local
# copy is still here". Reframed, it asked whether every gate in those specs sources assert.sh,
# and found that TWENTY-FOUR monolithic gates across the repo source nothing at all. That is what
# put the second placement in the design.
#
# So the census: a gate is covered if it sources assert.sh, or if it delegates to one that does.
# Everything else is reached only by run_gates, which ac05 in T1 asserts separately.
_uncovered=0; _names=""
for _g in "$ROOT"/specs/*/verify.sh "$ROOT"/specs/*/tasks/*/verify.sh; do
  [ -f "$_g" ] || continue
  strip_comments "$_g" | grep -q 'assert\.sh' && continue
  strip_comments "$_g" | grep -qE 'exec bash .*tasks/.*verify\.sh' && continue   # delegates
  _uncovered=$((_uncovered + 1))
  _names="$_names $(basename "$(dirname "$_g")")"
done
if [ "$_uncovered" -eq 0 ]; then
  no "ac03: the census found ZERO gates outside assert.sh's reach, which contradicts the 24 this spec was written for — the probe is broken, and 'everything is covered' is the reading a broken census always gives"
elif ! strip_comments "$ROOT/scripts/ralph-build.sh" 2>/dev/null | grep -qE '(env +-u|unset)[^|]*HARNESS_REPORT_URL'; then
  no "ac03: $_uncovered gates source neither assert.sh nor a delegate, and run_gates does not clear the set either, so nothing reaches them:$_names"
else
  ok "ac03: $_uncovered gates are outside assert.sh's reach and all of them are covered by run_gates"
fi

gate_done
