#!/usr/bin/env bash
# T4 — the channel is written down, including what it deliberately does not do.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260828o-evidence-egress/lib/fixtures.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

# Find the doc by CONTENT, not by a filename this gate invented. Whether the channel is written
# up in a new file or folded into the one the status channel already has is the author's call;
# what matters is that some doc describes it. Absence is a FAIL, never a skip — a per-task gate
# has nothing to defer to.
DOC="$(grep -rl 'artifacts' "$ROOT/docs" 2>/dev/null | head -1)"
has() { [ -n "$DOC" ] && grep -qi -- "$1" "$DOC" 2>/dev/null; }

if [ -z "$DOC" ]; then
  no "ac1: no file under docs/ mentions the artifact channel at all. Searched: $(ls "$ROOT/docs"/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"
elif ! grep -q '/artifacts/' "$DOC"; then
  no "ac1: $(basename "$DOC") does not give the endpoint shape — a reader cannot tell where an artifact goes without /runs/{key}/attempts/{task}/{attempt}/artifacts/{kind}"
else
  missing=""
  for k in prompt patch diff gate meta log; do
    grep -qw "$k" "$DOC" 2>/dev/null || missing="$missing $k"
  done
  if [ -n "$missing" ]; then
    no "ac1: $(basename "$DOC") documents the endpoint but not every kind that travels it — missing:$missing. A reader who does not know 'patch' exists will look for a passing task's file changes under 'diff' and find nothing"
  else
    ok "ac1: the endpoint and every artifact kind are documented"
  fi
fi

if [ -z "$DOC" ]; then
  no "ac2: no doc to check for the configuration"
elif ! has 'HARNESS_REPORT_URL' || ! has 'HARNESS_REPORT_TOKEN'; then
  no "ac2: $(basename "$DOC") does not name both configuration variables (HARNESS_REPORT_URL, HARNESS_REPORT_TOKEN)"
elif ! grep -qiE 'unset|not set|no coordinator|absent' "$DOC"; then
  no "ac2: $(basename "$DOC") does not say what happens with NO coordinator configured. That nothing is sent and nothing is printed is the portability bar, not a footnote"
else
  ok "ac2: the configuration is documented, including the unconfigured case"
fi

if [ -z "$DOC" ]; then
  no "ac3: no doc to check for the cap"
elif ! has 'HARNESS_ARTIFACT_MAX_BYTES'; then
  no "ac3: $(basename "$DOC") does not document HARNESS_ARTIFACT_MAX_BYTES, so an operator cannot discover that the cap is adjustable"
elif ! grep -qi 'truncat' "$DOC"; then
  no "ac3: $(basename "$DOC") documents the cap but not what a truncated artifact looks like to a reader"
else
  ok "ac3: the cap, its override and the appearance of truncation are documented"
fi

if [ -z "$DOC" ]; then
  no "ac4: no doc to check"
elif ! grep -qiE 'push|outbound|cannot connect|no inbound|dials' "$DOC"; then
  no "ac4: $(basename "$DOC") does not say WHY this is a push. Without it the next reader proposes a fetch, which cannot work: nothing can connect into a worker and a run that died has nothing left to fetch from"
else
  ok "ac4: the reason it is a push and not a fetch is recorded"
fi

if [ -z "$DOC" ]; then
  no "ac5: no doc to check"
elif ! grep -qiE 'does not (store|retain|serve|index)|not stored|no retention|coordinator[^.]*separate|separate piece' "$DOC"; then
  no "ac5: $(basename "$DOC") does not record what this deliberately does NOT do. A channel that ends at the POST and a channel that keeps things are different systems, and the next reader will assume the second"
else
  ok "ac5: the boundary — no storage, no retention, no serving — is written down"
fi

# ac6 — the script a reader opens says what it now sends.
if ! sed -n '1,60p' "$ROOT/scripts/ralph-log.sh" | grep -qiE 'artifact|coordinator|ship|POST'; then
  no "ac6: scripts/ralph-log.sh's header block does not mention that artifacts now leave the worker — the file's own documentation still describes a writer that only writes"
else
  ok "ac6: ralph-log.sh's header block records that artifacts are shipped"
fi

# ac7 — a documentation task must not change what runs.
mkexec_loud; mkloop_logged "$T/off"; runloop_logged "$T/off"
off_rc="$RC"
mkdir -p "$T/ctl"; mkloop_logged "$T/ctl"
if [ "$off_rc" != 0 ]; then
  no "ac7: an unconfigured run exited $off_rc — this task documents, it does not change behaviour. Loop said: $(loopout off)"
elif [ "$(arts prompt)" != 0 ] 2>/dev/null; then
  no "ac7: an unconfigured run posted artifacts"
else
  ok "ac7: an unconfigured run still behaves exactly as it did"
fi

gate_done
