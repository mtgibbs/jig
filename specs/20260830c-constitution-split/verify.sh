#!/usr/bin/env bash
# specs/20260830c-constitution-split/verify.sh — the deterministic gate for "the constitution
# carries harness law only — consumers bring their own".
#
# THE THREE-VERDICT CONTRACT: ok / no / pend; STRICT=1 promotes every pend. The un-rewritten
# (pi-cluster) constitution reads as `pend` — the split artifact does not exist yet. A breach of
# an invariant that no later task may touch (append-only amendments, the judge's anchor shape)
# is `no` outright.
#
# Trap discipline (TEMPLATE §11): the AC1 denylist is an absence assertion, so it carries a
# POSITIVE CONTROL — the probe must fire on a planted fixture before its clean result counts.
# The AC4/AC5 script checks are region-scoped to anchor()'s body and the anchor-call block, not
# whole-file greps.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

CONST="$R/specs/constitution.md"
SREADME="$R/specs/README.md"
TEMPLATE="$R/specs/TEMPLATE.md"
AMEND="$R/specs/amendments.md"
JUDGE="$R/scripts/ralph-judge-codex.sh"

for f in "$CONST" "$SREADME" "$TEMPLATE" "$AMEND" "$JUDGE"; do
  [ -r "$f" ] || { echo "  FAIL  scope: $f missing — this spec rewrites existing files, it creates none" >&2; exit 1; }
done
ok "scope: every touched file exists"

_stray="$(find "$R/specs/20260830c-constitution-split" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name evidence 2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

# ── AC1 · no consumer-specific token in the constitution ───────────────────────────────────
# One probe, used twice: first against a planted fixture (positive control — if the probe
# cannot fire, a clean constitution proves nothing), then against the real file.
DENY='Flux|1Password|ExternalSecret|op://|clusters/pi-k3s|lab\.mtgibbs\.dev|Beelink|K3s|kubectl|Pi-hole|Grafana|Jellyfin|Immich|Ollama|pi-cluster|homelab|ARCHITECTURE\.md'
probe(){ grep -nE "$DENY" "$1"; }

printf 'GitOps via Flux is the law here\n' > "$T/fixture.md"
if probe "$T/fixture.md" >/dev/null; then
  ok "ac1: positive control — the denylist probe fires on a planted 'Flux'"
else
  no "ac1: positive control FAILED — the probe cannot fire, so a clean result below is meaningless"
fi

_hits="$(probe "$CONST" | head -5)"
if [ -n "$_hits" ]; then
  pend "ac1: the constitution still carries consumer law — $(printf '%s' "$_hits" | tr '\n' ' ' | cut -c1-200)"
else
  ok "ac1: no consumer-specific token in the constitution"
fi

# ── AC2 · every backticked file path in the three Tier-1 docs resolves ─────────────────────
# Extraction: backticked tokens that look like concrete file paths (an extension, no
# placeholders). Dir-shaped narrative citations (`specs/model-watch`) are prose, not paths.
# A path may resolve from the repo root or relative to specs/ (README says `constitution.md`).
_dangling=""
for doc in "$CONST" "$SREADME" "$TEMPLATE"; do
  while IFS= read -r p; do
    q="${p#/}"
    [ -e "$R/$q" ] || [ -e "$R/specs/$q" ] || _dangling="$_dangling $(basename "$doc"):$p"
  done <<EOF
$(grep -o '`[^`]*`' "$doc" | tr -d '\`' \
   | grep -E '^/?([A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+\.(md|sh|txt|py|mjs|yaml|yml|html)$|^/?[A-Za-z0-9_.-]+\.md$' \
   | grep -v '[<>*{}$]' | grep -v '^pi-cluster/' \
   | grep -vE '^(spec|plan|tasks)\.(md|txt)$' | sort -u)
EOF
done
if [ -n "$_dangling" ]; then
  pend "ac2: Tier-1 docs reference absent files —$_dangling"
else
  ok "ac2: every backticked file path in the three Tier-1 docs resolves"
fi

# Control for ac2's extraction (Trap A-prime — a scope that silently did nothing): the
# collection must be non-degenerate. The three docs collectively reference at least these.
_ex="$(grep -oh '`[^`]*`' "$CONST" "$SREADME" "$TEMPLATE" | tr -d '\`' \
   | grep -cE '^/?([A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+\.(md|sh|txt|py|mjs|yaml|yml|html)$|^/?[A-Za-z0-9_.-]+\.md$' || true)"
[ "${_ex:-0}" -ge 5 ] && ok "ac2: control — extraction is non-degenerate ($_ex path refs collected)" \
                      || no "ac2: control — extraction collected only ${_ex:-0} refs; the filter went inert and ac2 proves nothing"

# ── AC3 · the index lists every spec dir, and no absent one ────────────────────────────────
ls -d "$R"/specs/2026*/ 2>/dev/null | while read -r d; do basename "$d"; done | sort > "$T/have"
grep -oE '2026[0-9]{4}[a-z]-[A-Za-z0-9-]+' "$SREADME" | sort -u > "$T/listed"
if [ ! -s "$T/listed" ]; then
  pend "ac3: specs/README.md lists no spec directories yet"
else
  _miss="$(comm -23 "$T/have" "$T/listed" | tr '\n' ' ')"
  _ghost="$(comm -13 "$T/have" "$T/listed" | tr '\n' ' ')"
  [ -n "$_miss" ]  && pend "ac3: present but not indexed — $_miss" \
                   || ok "ac3: every specs/2026* directory is indexed ($(wc -l < "$T/have" | tr -d ' ') of them)"
  [ -n "$_ghost" ] && no "ac3: indexed but absent — $_ghost (an index that lists ghosts is the defect this spec removes)" \
                   || ok "ac3: the index lists no absent directory"
fi

# ── AC4 · the judge's tolerance/fatality split is intact ───────────────────────────────────
# Region-scoped to anchor()'s body: an absent file accumulates and returns; no exit in there.
_anchor_body="$(sed -n '/^anchor(){/,/^}/p' "$JUDGE")"
if [ -z "$_anchor_body" ]; then
  no "ac4: cannot find anchor() in ralph-judge-codex.sh — the seam this spec documents is gone"
else
  printf '%s' "$_anchor_body" | grep -q 'ABSENT=' && ! printf '%s' "$_anchor_body" | grep -q 'exit' \
    && ok "ac4: anchor() tolerates an absent file (accumulates ABSENT, never exits)" \
    || no "ac4: anchor() no longer tolerates absence — an absent overlay must declare nothing, not kill the judge"
fi
# The missing-HARNESS-constitution path is fatal, before any anchoring: region between the
# HCONST assignment and the first anchor call must exit nonzero.
sed -n '/^HCONST=/,/^anchor "\$HCONST"/p' "$JUDGE" | grep -q 'exit 2' \
  && ok "ac4: a missing harness constitution is fatal (exit 2) before any anchor resolves" \
  || no "ac4: the missing-harness-constitution path is no longer fatal — a judge with no principles must refuse, not report clean"

# ── AC5 · generic first, overlay second — in code and in the law ───────────────────────────
_h="$(grep -n '"harness constitution"' "$JUDGE" | head -1 | cut -d: -f1)"
_p="$(grep -n '"project constitution"' "$JUDGE" | head -1 | cut -d: -f1)"
if [ -n "$_h" ] && [ -n "$_p" ] && [ "$_h" -lt "$_p" ]; then
  ok "ac5: the judge anchors the harness constitution (line $_h) before the project's (line $_p)"
else
  no "ac5: anchor order broken or unfindable (harness=$_h project=$_p) — generic law must come first"
fi
_overlay="$(sed -n '/^## .*[Oo]verlay/,/^## /p' "$CONST")"
if [ -z "$_overlay" ]; then
  pend "ac5: the constitution has no consumer-overlay section"
elif printf '%s' "$_overlay" | grep -qi 'generic first, overlay second' \
  && printf '%s' "$_overlay" | grep -q 'specs/constitution.md' \
  && printf '%s' "$_overlay" | grep -qi 'absent'; then
  ok "ac5: the overlay section states the assembly order, the overlay's location, and absent semantics"
else
  pend "ac5: the overlay section is missing the order, the location, or the absent rule"
fi

# ── AC6 · the split is ratified by amendment; history above it untouched ───────────────────
if ! grep -q '^## The constitution carries harness law only' "$AMEND"; then
  pend "ac6: the ratifying amendment is not yet appended"
else
  awk '/^## The constitution carries harness law only/{found=1; next} found && /^Status:/{print; exit}' "$AMEND" \
    | grep -q 'Accepted' \
    && ok "ac6: the ratifying amendment is present with Status: Accepted" \
    || no "ac6: the amendment exists but is not Accepted — judges may not cite it, so the split is unratified"
fi
grep -q '^> Version: 2\.' "$AMEND" \
  && ok "ac6: amendments version went MAJOR (2.x) — the redefinition is owned, not slipped in" \
  || pend "ac6: amendments version line is not 2.x"
# Append-only: the five pre-split amendment headings all still present, in their original order.
_order="$(grep -n '^## ' "$AMEND" | grep -E 'Gates must prove they can fail|Durable facts go to the repo|PR to publish, always|Name the states|Portability follows the invoker' | cut -d: -f1 | tr '\n' ' ')"
set -- $_order
if [ $# -eq 5 ] && [ "$1" -lt "$2" ] && [ "$2" -lt "$3" ] && [ "$3" -lt "$4" ] && [ "$4" -lt "$5" ]; then
  ok "ac6: all five prior amendments survive in order — append-only held"
else
  no "ac6: prior amendments missing or reordered ($# found) — amendments are append-only"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
