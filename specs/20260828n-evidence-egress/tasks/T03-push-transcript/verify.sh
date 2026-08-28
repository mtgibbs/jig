#!/usr/bin/env bash
# T3 — the executor's own transcript leaves too.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260828n-evidence-egress/lib/fixtures.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

# ac1 — a passing attempt ships its transcript.
coord_start
mkexec_loud; mkloop_logged "$T/ok"
runloop_logged "$T/ok" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN"
disk="$(diskfile "$T/ok" '*.log')"
if [ -z "$disk" ] || [ ! -s "$disk" ]; then
  no "ac1: the run wrote no non-empty transcript, so the fixture is wrong rather than the implementation"
elif [ "$(arts log)" = 0 ]; then
  no "ac1: a transcript of $(wc -c < "$disk") bytes was written and none was shipped. Kinds that arrived: [$(grep -o '/artifacts/[a-z]*' "$T/coord.log" | sort -u | tr '\n' ' ')]"
else
  ok "ac1: a passing attempt ships the executor's transcript"
fi
coord_stop

# ac2 — so does a FAILING one. This is the transcript a reader actually wants: the run that
# passed needs no explaining. An implementation that pushes from the pass branch alone satisfies
# ac1 completely and is wrong in the only case that matters.
coord_start
mkexec_fail; mkloop_logged "$T/bad"
runloop_logged "$T/bad" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN"
if [ -z "$(diskfile "$T/bad" '*.log')" ]; then
  no "ac2: the failing fixture wrote no transcript, so the assertion could not run"
elif [ "$(arts log)" = 0 ]; then
  no "ac2: a failing attempt's transcript was written but never shipped — the run a reader most needs to read is the one that left nothing behind"
else
  ok "ac2: a failing attempt ships its transcript too"
fi
coord_stop

# ac3 — the transcript obeys T2's cap and carries T2's marker. The transcript is the largest
# artifact a run produces, so this is the case that proves the cap rather than one that may skip it.
coord_start
mkexec_loud_big 256; mkloop_logged "$T/huge"
runloop_logged "$T/huge" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN" \
  HARNESS_ARTIFACT_MAX_BYTES=8192
hdisk="$(diskfile "$T/huge" '*.log')"
horig=0; [ -n "$hdisk" ] && horig="$(wc -c < "$hdisk")"
hbody="$(artbody log)"
if [ "$horig" -le 8192 ] 2>/dev/null; then
  no "ac3: the loud fixture's transcript is only $horig bytes, at or under the cap — this run cannot test the cap"
elif [ "$(arts log)" = 0 ]; then
  no "ac3: an oversized transcript was dropped rather than truncated"
elif [ "$(artsize log)" -gt 8704 ] 2>/dev/null; then
  no "ac3: the shipped transcript is $(artsize log) bytes against an 8192-byte cap — the transcript is not going through the same bound as every other artifact"
elif ! printf '%s' "$hbody" | grep -qi 'truncat'; then
  no "ac3: the truncated transcript carries no marker. Received tail: [$(printf '%s' "$hbody" | tail -c 120 | tr '\n' ' ')]"
else
  ok "ac3: an oversized transcript is capped and says so"
fi
coord_stop

# ac4 — an empty transcript is not announced. The silent executor writes a zero-byte .log, and a
# push that fires on the file's existence rather than its content would ship it: a reader then
# opens a transcript that has nothing in it and concludes the executor produced nothing, which is
# the same wrong conclusion the loop itself draws from a missing evidence directory.
coord_start
mkexec; mkloop_logged "$T/quiet"
runloop_logged "$T/quiet" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN"
qdisk="$(diskfile "$T/quiet" '*.log')"
qsize=0; [ -n "$qdisk" ] && qsize="$(wc -c < "$qdisk")"
if [ "$qsize" != 0 ]; then
  no "ac4: the silent fixture wrote a $qsize-byte transcript, so this assertion did not test what it claims"
elif [ "$(arts log)" != 0 ]; then
  no "ac4: $(arts log) transcript artifacts were shipped for a run whose transcript was empty"
else
  ok "ac4: an empty transcript is never announced"
fi
coord_stop

gate_done
