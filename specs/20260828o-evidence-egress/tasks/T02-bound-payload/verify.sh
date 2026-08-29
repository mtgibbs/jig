#!/usr/bin/env bash
# T2 — the payload is bounded, and a bounded artifact says so.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260828o-evidence-egress/lib/fixtures.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

CAP=8192

# ac1 — artifacts comfortably under the cap arrive WHOLE.
#
# Compared as SETS of content hashes, not "the largest received vs the largest on disk". Those
# were two independent max() picks over two different collections, and two prompts of equal size
# tie-break independently — so the gate diffed two different files and failed a correct
# implementation. Hashing both sides asks what this assertion means: everything written arrived,
# and nothing was altered on the way. An implementation that truncates everything to the cap
# fails it, which is the point — this is the assertion separating bounding from mangling.
coord_start
mkexec_loud; mkloop_logged "$T/small"
runloop_logged "$T/small" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN" \
  HARNESS_ARTIFACT_MAX_BYTES=1000000
rx="$(arthashes prompt)"
dk="$(diskhashes "$T/small" '*.prompt.md')"
if [ "$(arts prompt)" = 0 ]; then
  no "ac1: no prompt artifact arrived, so nothing could be compared"
elif [ -z "$dk" ]; then
  no "ac1: the run wrote no prompt file, so the fixture is wrong rather than the implementation"
elif [ "$rx" != "$dk" ]; then
  no "ac1: what arrived is not what was written — $(printf '%s' "$rx" | grep -c .) artifact(s) received against $(printf '%s' "$dk" | grep -c .) written, and their contents do not match as a set. Under the cap nothing may be altered and nothing may be dropped"
else
  ok "ac1: every artifact under the cap arrives byte-identical to what was written"
fi
coord_stop

# ac2..ac5 — one oversized run, four questions about it.
coord_start
mkexec_big 256; mkloop_logged "$T/big"
runloop_logged "$T/big" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN" \
  HARNESS_ARTIFACT_MAX_BYTES="$CAP"
bigdisk="$(diskfile "$T/big" '*.patch')"
orig=0; [ -n "$bigdisk" ] && orig="$(wc -c < "$bigdisk")"
got="$(artsize patch)"
body="$(artbody patch)"

if [ "$orig" -le "$CAP" ] 2>/dev/null; then
  no "ac2: the fixture's largest patch is only $orig bytes, at or under the ${CAP}-byte cap — this run cannot test truncation at all"
elif [ "$(arts patch)" = 0 ]; then
  no "ac2: an artifact of $orig bytes was DROPPED rather than truncated. A large artifact is the one most worth reading; it must be sent, clipped"
else
  ok "ac2: an artifact over the cap is sent truncated rather than dropped"
fi

# The allowance exists because the marker itself is bytes. It is deliberately small: an
# implementation that appended the whole original after the marker would blow through it.
if [ "$(arts patch)" = 0 ]; then
  no "ac3: no patch artifact arrived, so its size could not be checked"
elif [ "$got" -gt "$((CAP + 512))" ] 2>/dev/null; then
  no "ac3: the received artifact is $got bytes against a ${CAP}-byte cap — the cap is not being applied"
else
  ok "ac3: the shipped artifact respects the cap"
fi

# The marker must be IN the received bytes. A note appended after the cap was reached is not a
# marker; it is more bytes that were cut, and the reader sees a clipped artifact claiming nothing.
if [ -z "$body" ]; then
  no "ac4: nothing was received, so no marker could be found"
elif ! printf '%s' "$body" | grep -qi 'truncat'; then
  no "ac4: the truncated artifact carries no truncation marker in the bytes that arrived — a clipped artifact that says nothing is indistinguishable from the whole of a small one. Received tail: [$(printf '%s' "$body" | tail -c 120 | tr '\n' ' ')]"
else
  ok "ac4: a truncated artifact announces itself, in the bytes that survive"
fi

if [ -z "$body" ]; then
  no "ac5: nothing was received, so the marker's contents could not be checked"
elif ! printf '%s' "$body" | grep -q "$orig"; then
  no "ac5: the marker does not state the original size ($orig bytes). 'this was clipped' and 'this was clipped at $CAP of $orig' are different facts, and only the second tells a reader whether to go looking. Received tail: [$(printf '%s' "$body" | tail -c 120 | tr '\n' ' ')]"
else
  ok "ac5: the marker states how large the artifact actually was"
fi
coord_stop

# ac6 — the cap is genuinely the variable's value, not a constant that happens to match.
coord_start
mkexec_big 256; mkloop_logged "$T/wide"
runloop_logged "$T/wide" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN" \
  HARNESS_ARTIFACT_MAX_BYTES=40000
wide="$(artsize patch)"
if [ "$(arts patch)" = 0 ]; then
  no "ac6: no patch arrived on the raised-cap run, so the override could not be observed"
elif [ "$wide" -le "$got" ] 2>/dev/null; then
  no "ac6: raising HARNESS_ARTIFACT_MAX_BYTES from $CAP to 40000 did not raise what was sent ($got then $wide bytes) — the cap is hardcoded, and an operator cannot widen it without editing the script"
else
  ok "ac6: HARNESS_ARTIFACT_MAX_BYTES actually sets the cap"
fi
coord_stop

gate_done
