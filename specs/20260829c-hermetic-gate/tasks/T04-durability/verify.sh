#!/usr/bin/env bash
# T4 — it cannot be forgotten, and it cannot come back locally.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829c-hermetic-gate/lib/fixtures.sh"
A="$ROOT/specs/lib/assert.sh"
D="$(mktemp -d)"; trap 'rm -rf "$D"' EXIT

# ── ac01: a brand-new gate is hermetic with no line of its own ───────────────────────────────
# The whole design, stated as the thing a gate author does NOT have to know. This is what
# separates the fix from the two local patches that came before it.
cat > "$D/newgate.sh" <<NEW
#!/usr/bin/env bash
set -u
. "$A"
printf '%s|%s' "\${HARNESS_REPORT_URL:-clear}" "\${RALPH_FORCE_ALL:-clear}"
NEW
_saw="$( env HARNESS_REPORT_URL=http://real HARNESS_REPORT_TOKEN=t RALPH_FORCE_ALL=1 \
           bash "$D/newgate.sh" 2>/dev/null )"
case "$_saw" in
  "clear|clear") ok "ac01: a gate that sources assert.sh and nothing else is already hermetic" ;;
  *)             no "ac01: a new gate still sees [$_saw]. Every author would have to know a rule, which is the adoption problem that produced two local patches under two different mechanisms and one comment deferring to a spec that never existed" ;;
esac

# ── ac02: no local re-implementation anywhere under specs/ ───────────────────────────────────
# Scoped hard, three ways, because each variable name appears in this spec's prose, in the
# write-up, and in every comment that explains why the entry is on the list:
#   - instruction lines only (comments stripped)
#   - the reset CONSTRUCT, not the mention
#   - and this file excluded, whose own source contains the literal strings it searches for
_self="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/$(basename "${BASH_SOURCE[0]}")"
_dupes=""
for f in "$ROOT"/specs/*/verify.sh "$ROOT"/specs/*/tasks/*/verify.sh "$ROOT"/specs/*/lib/*.sh; do
  [ -f "$f" ] || continue
  [ "$f" = "$_self" ] && continue
  # And this spec's own gates. They must contain the literal strings — T01 sets the variables to
  # test that they are cleared, and its ac05 greps ralph-build.sh for the reset CONSTRUCT, which
  # is the exact pattern this loop searches for. Third time in one session that a check matched
  # its own source; the first two were a mutant WHY: line and a rename census.
  case "$f" in "$ROOT"/specs/20260829c-hermetic-gate/*) continue ;; esac
  # `-u` OR `unset` ADJACENT to the name, not `env +-u` — because a third mechanism appeared:
  # an args LIST (`FX_UNSET="-u HARNESS_REPORT_URL …"`) held in a variable and expanded at the
  # call site. The old pattern required the literal `env` on the same line and matched none of it,
  # so the two copies this task exists to remove went invisible the day they were rewritten.
  # A detector keyed to the mechanism dies of the next mechanism; key it to the name being removed.
  strip_comments "$f" | grep -qE '(unset|-u)[[:space:]]+HARNESS_REPORT_URL' && _dupes="$_dupes ${f#$ROOT/}"
done
if [ -n "$_dupes" ]; then
  no "ac02: the quarantined set is re-implemented locally in:$_dupes — a second copy is a second thing to keep in sync, and the two that existed before this spec did not even use the same mechanism (unset at source time in one, env -u per invocation in the other)"
else
  ok "ac02: the quarantined set exists in exactly one place"
fi

# ── ac03: each entry carries the incident that earned it ─────────────────────────────────────
# So the next person adding a variable is told what kind of evidence puts one on the list. A bare
# list invites additions on suspicion, and a quarantine that grows on suspicion eventually unsets
# something a gate needed.
if ! strip_comments "$A" | grep -qE '(unset|env +-u)[^#]*HARNESS_REPORT_URL'; then
  no "ac03: assert.sh does not carry the reset at all"
else
  _undoc=""
  for v in $QUARANTINED; do
    grep -q "$v" "$A" || { _undoc="$_undoc $v"; continue; }
    # the incident: a comment mentioning the variable, or a comment block naming what it broke
    grep -B4 -A4 "$v" "$A" | grep -qiE 'coordinator|board|skip|fixture|override|posted|evict' \
      || _undoc="$_undoc $v"
  done
  if [ -n "$_undoc" ]; then
    no "ac03: these are quarantined with no incident recorded beside them:$_undoc — the list is the only place a reader learns what earns a slot, and one that reads as arbitrary gets added to arbitrarily"
  else
    ok "ac03: every quarantined variable carries the failure it came from"
  fi
fi

gate_done
