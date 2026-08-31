#!/usr/bin/env bash
# specs/20260830a-product-naming/verify.sh — the deterministic gate for "the product is named
# Jig — identity renames, the bones do not".
#
# THE THREE-VERDICT CONTRACT: ok / no / pend; STRICT=1 promotes every pend. An identity file
# that still carries the old name is `pend` (the renamed artifact does not exist yet); an
# invariance breach is `no` outright — there is no later task that legitimately renames a bone.
#
# The AC3 invariance checks are PRESENCE greps on names that must survive: their one failure
# condition is exactly the forbidden rename, so a broken probe cannot hand out a free pass
# (TEMPLATE §11 Trap B does not apply — nothing here asserts an absence measured by a probe
# that could silently return empty; AC5's absence check has its positive control in history:
# it was RED on 2026-08-30 before T2, see evidence/).
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

README="$R/README.md"
AGENTS="$R/AGENTS.md"
BOARD="$R/scripts/dispatch/board.html"
RUNBOARD="$R/scripts/runboard.py"
COORD="$R/scripts/dispatch/coordinator.py"

for f in "$README" "$AGENTS" "$BOARD" "$RUNBOARD" "$COORD"; do
  [ -r "$f" ] || { echo "  FAIL  scope: $f missing — this spec renames prose in existing files, it creates none" >&2; exit 1; }
done
ok "scope: every touched file exists"

# ── AC1 · the README opens with the name and the one-line definition ───────────────────────
# Scoped to the head, not the whole file (TEMPLATE §11 Trap A: the words could appear anywhere).
_head="$(head -6 "$README")"
printf '%s' "$_head" | grep -q '^# Jig' \
  && ok "ac1: README title is '# Jig'" \
  || pend "ac1: README title does not open '# Jig'"
if printf '%s' "$_head" | grep -qi 'a repo brings a spec and a gate' \
   && printf '%s' "$_head" | grep -q 'Jig owns everything'; then
  ok "ac1: the opening states the one-line definition"
else
  pend "ac1: the README head does not state 'a repo brings a spec and a gate; Jig owns everything else'"
fi

# ── AC2 · every board title carries the name ───────────────────────────────────────────────
grep -q '<title>Jig Fleet</title>' "$BOARD" && grep -q '<h1>Jig Fleet</h1>' "$BOARD" \
  && ok "ac2: fleet board titled 'Jig Fleet' (<title> and <h1>)" \
  || pend "ac2: board.html is not titled 'Jig Fleet' in both <title> and <h1>"
grep -q '<title>Jig Run Board</title>' "$RUNBOARD" && grep -q '<h1>Jig Run Board</h1>' "$RUNBOARD" \
  && ok "ac2: run board titled 'Jig Run Board'" \
  || pend "ac2: runboard.py is not titled 'Jig Run Board'"
grep -q '<title>Jig</title>' "$COORD" \
  && ok "ac2: coordinator fallback page titled 'Jig'" \
  || pend "ac2: coordinator.py fallback page is not titled 'Jig'"

# ── AC3 · invariance: the bones did not move ───────────────────────────────────────────────
# Presence greps; each fails exactly when the forbidden rename happens. `no`, never `pend` —
# no later task may rename a bone.
for s in ralph-build.sh ralph-judge.sh ralph-log.sh ralph-status.sh ralph-retry.sh ralph-bus.sh; do
  [ -f "$R/scripts/$s" ] || no "ac3: scripts/$s is gone — the runtime surface is frozen until its own spec (with shims) lands"
done
[ -f "$R/scripts/ralph-build.sh" ] && ok "ac3: the ralph-*.sh runtime surface is intact"
grep -q 'RALPH_EXEC_CMD' "$R/scripts/ralph-build.sh" 2>/dev/null \
  && ok "ac3: RALPH_EXEC_CMD binding variable unchanged" \
  || no "ac3: RALPH_EXEC_CMD no longer appears in ralph-build.sh — env vars are frozen"
grep -q 'harness-coordinator' "$R/.github/workflows/build-images.yml" 2>/dev/null \
  && ok "ac3: harness-coordinator image name unchanged" \
  || no "ac3: the harness-coordinator image name moved — GHCR names are a separate, breaking decision"
grep -q 'executor-stillborn' "$R/scripts/loop-doctor.sh" 2>/dev/null \
  && ok "ac3: loop-doctor outcome vocabulary unchanged" \
  || no "ac3: 'executor-stillborn' no longer in loop-doctor.sh — outcome literals are schema"

# ── AC4 · drift is one concept, defined at first use ───────────────────────────────────────
# Scoped to the FIRST line in the README that uses the word; the definition rides that line.
_drift_line="$(grep -i 'drift' "$README" | head -1)"
if [ -z "$_drift_line" ]; then
  no "ac4: README no longer uses 'drift' at all — the pi-cluster #199 lesson lost its name"
elif printf '%s' "$_drift_line" | grep -qi 'diverg'; then
  ok "ac4: README defines 'drift' (divergence of copies) where first used"
else
  pend "ac4: the README's first 'drift' does not carry its definition on the same line"
fi

# ── AC5 · the old display titles are gone from scripts/ ────────────────────────────────────
_old="$(grep -rl 'Harness Fleet\|Harness Run Board' "$R/scripts" 2>/dev/null)"
[ -n "$_old" ] && pend "ac5: old board titles survive in — $(printf '%s' "$_old" | tr '\n' ' ')" \
              || ok "ac5: no 'Harness Fleet' / 'Harness Run Board' under scripts/"

# ── AC6 · AGENTS.md introduces the project as Jig ──────────────────────────────────────────
head -6 "$AGENTS" | grep -q 'Jig' \
  && ok "ac6: AGENTS.md opening brief names Jig" \
  || pend "ac6: AGENTS.md opening brief does not name Jig"

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
