#!/usr/bin/env bash
# Gate for T03-board-mutant-panel (20260831s-live-board-evidence).
#
# A static gate over board.html, and static gates over this repo's HTML have a specific way of
# lying: every word worth grepping for — selftest, SURVIVOR, textContent, innerHTML — already
# appears somewhere in board.html or its neighbours as prose or as unrelated code (Trap A).
# So every check here is scoped to the panel's own region, delimited by the markers the spec
# pins (MUTANT PANEL BEGIN/END), and comments are stripped INSIDE that region afterwards.
#
# The scope itself is proven non-degenerate before anything is asserted through it, because a
# scope can be written and be inert and an inert scope looks exactly like a working one
# (Trap A-prime, specs/harness-egress-allowlist 2026-08-18).
#
# ac14 is an ABSENCE assertion ("no innerHTML in the panel"), so it ships a positive control:
# the same probe must FIND the innerHTML that legitimately exists elsewhere in this file. A
# probe that matches nothing anywhere would report the panel clean either way (Trap B).
#
# Named limit, stated rather than papered over: this gate proves the panel's MECHANICS, not
# that it looks right. Nothing here can see "this reads badly" — spec §11b says a human eye is
# required before the PR merges, and that is not a gap this gate can close.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
# shellcheck source=/dev/null
. "$R/specs/lib/assert.sh"

B="$R/scripts/dispatch/board.html"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

[ -f "$B" ] || { no "gate: $B missing"; gate_done; }

# The panel region, markers excluded. Extracted BEFORE comments are stripped, because the
# markers are themselves comments.
sed -n '/MUTANT PANEL BEGIN/,/MUTANT PANEL END/p' "$B" \
  | sed '1d;$d' > "$W/region.raw" 2>/dev/null || true

# Comments out, `://` protected so an http:// URL is not mistaken for one.
strip() { sed 's|^[[:space:]]*//.*||; s|\([^:]\)//.*|\1|' "$1"; }
strip "$W/region.raw" > "$W/region"
strip "$B" > "$B.stripped.$$" ; mv "$B.stripped.$$" "$W/all"

# `grep -c` prints 0 AND exits 1 on no match, so `|| echo 0` yields the two-line "0\n0"
# that made this comparison a syntax error rather than a verdict. Count, then default.
rlines="$(grep -c . "$W/region" 2>/dev/null)"; [ -n "$rlines" ] || rlines=0

# ── the scope, before anything is asserted through it ───────────────────────────────────────
[ "${rlines:-0}" -ge 20 ] \
  && ok "scope: the panel region is present and non-degenerate ($rlines lines)" \
  || { no "scope: the MUTANT PANEL BEGIN/END region holds ${rlines:-0} lines — every check below would pass vacuously against an empty scope, so they are not run"; gate_done; }

_all_lines="$(grep -c . "$W/all" 2>/dev/null)"; [ -n "$_all_lines" ] || _all_lines=0
[ "$rlines" -lt "$_all_lines" ] \
  && ok "scope: the region is a proper subset of board.html — the filter took effect" \
  || no "scope: the region is the whole file — the markers are not delimiting anything"

# ── ac11 : the panel is fed by the artifact route, and shows the counts ─────────────────────
grep -q '/api/artifact' "$W/region" \
  && ok "ac11: the panel fetches its rows from /api/artifact" \
  || no "ac11: the panel never calls /api/artifact — it has no way to get a selftest artifact's bytes"

grep -q 'selftest' "$W/region" \
  && ok "ac11: the panel selects the selftest artifact kind" \
  || no "ac11: the panel does not name the selftest kind — it cannot tell one artifact from another"

_missv=""
for _v in KILLED SURVIVOR WRONG-REASON HUNG; do
  grep -q "$_v" "$W/region" || _missv="$_missv $_v"
done
[ -z "$_missv" ] \
  && ok "ac11: all four verdicts are handled (KILLED, SURVIVOR, WRONG-REASON, HUNG)" \
  || no "ac11: the panel never mentions$_missv — an unhandled verdict renders as nothing at all"

# ── ac12 : survivors first, provable from the rank the spec pins ────────────────────────────
# The ordering lives in a literal rank map (spec §6), which is the only form of "survivors
# first" a static gate can actually read. Ranks are extracted and COMPARED — a gate that only
# greps for the word SURVIVOR passes on a map that ranks it last.
_rank() {
  sed -n 's/.*VRANK[^=]*=[[:space:]]*{\(.*\)}.*/\1/p' "$W/region" | head -1 \
    | tr ',' '\n' | sed "s/['\"]//g" \
    | awk -F: -v k="$1" '{ gsub(/[[:space:]]/,"",$1); gsub(/[[:space:]]/,"",$2);
                           if ($1 == k) print $2 }' | head -1
}
_rs="$(_rank SURVIVOR)"; _rk="$(_rank KILLED)"
if [ -n "$_rs" ] && [ -n "$_rk" ]; then
  if [ "$_rs" -lt "$_rk" ] 2>/dev/null; then
    ok "ac12: VRANK orders SURVIVOR ($_rs) ahead of KILLED ($_rk)"
  else
    no "ac12: VRANK puts SURVIVOR at $_rs and KILLED at $_rk — the one row a reader opened the board for is buried under the ones that behaved"
  fi
else
  no "ac12: no VRANK literal in the panel region — ordering that is not a readable rank cannot be verified, and the spec pins this shape for exactly that reason"
fi

grep -q 'VRANK' "$W/region" && grep -Eq '\.sort\(' "$W/region" \
  && ok "ac12: the rows are sorted through VRANK" \
  || no "ac12: VRANK is declared but nothing sorts by it — a rank nothing reads orders nothing"

# ── ac13 : each row carries what makes it readable ──────────────────────────────────────────
# Property ACCESSES, not bare words. A bare `diff` matches the `mdiff` CSS class the viewer
# also uses, so a panel that stopped rendering diffs entirely would still satisfy the check —
# the needle is already in the haystack (Trap A). `r.diff` is only there if a row is read.
_missf=""
for _f in 'r\.assertion' 'r\.target' 'r\.why' 'r\.diff'; do
  grep -q "$_f" "$W/region" || _missf="$_missf ${_f//\\/}"
done
[ -z "$_missf" ] \
  && ok "ac13: rows render assertion, target, why and diff" \
  || no "ac13: the panel never reads$_missf — without the diff there is no 'how the mutant was formed', and without the why there is no reason it existed"

# ── ac14 : worker bytes are inserted as text, never markup ──────────────────────────────────
# Positive control FIRST. If this probe cannot find the innerHTML that render() and detail()
# legitimately use, then "none in the panel" is not a finding.
_n_all="$(grep -c 'innerHTML' "$W/all" 2>/dev/null)"; [ -n "$_n_all" ] || _n_all=0
[ "${_n_all:-0}" -ge 1 ] \
  && ok "ac14 control: the innerHTML probe finds the $_n_all use(s) elsewhere in board.html" \
  || no "ac14 control: the probe finds no innerHTML anywhere in board.html — it is not looking, so its verdict on the panel is meaningless"

_n_region="$(grep -c 'innerHTML' "$W/region" 2>/dev/null)"; [ -n "$_n_region" ] || _n_region=0
[ "${_n_region:-0}" -eq 0 ] \
  && ok "ac14: no innerHTML inside the panel region" \
  || no "ac14: $_n_region innerHTML use(s) in the panel — every field here is a worker-controlled string, and a WHY containing markup would execute in the board's origin"

grep -q 'textContent' "$W/region" \
  && ok "ac14: the panel inserts its fields with textContent" \
  || no "ac14: the panel never uses textContent — absence of innerHTML alone does not prove the fields are escaped"

# ── ac15 : a bad line is skipped, not fatal ─────────────────────────────────────────────────
grep -q 'JSON.parse' "$W/region" \
  && ok "ac15: the panel parses the artifact line by line" \
  || no "ac15: no JSON.parse in the panel — it is not reading JSONL"

# The catch must be attached to THIS parse. showArtifact has a try/catch of its own around
# fetch, so a region-wide grep for `catch` passes on a parseSelftest with no guard at all —
# the same needle-already-present failure (Trap A), one function over.
grep -A3 'JSON.parse' "$W/region" | grep -q 'catch' \
  && ok "ac15: the JSON.parse itself is guarded, so one bad line cannot take the panel down" \
  || no "ac15: JSON.parse is unguarded — the byte cap truncates the artifact mid-line by design, and one clipped line would blank the whole panel"

gate_done
