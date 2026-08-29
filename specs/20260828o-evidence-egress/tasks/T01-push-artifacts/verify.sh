#!/usr/bin/env bash
# T1 — the artifacts leave the worker as they are written.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260828o-evidence-egress/lib/fixtures.sh"

# gate_tmpdir SETS T as a side effect and prints nothing. `T="$(gate_tmpdir)"` runs it in a
# subshell, discards that assignment and leaves T empty — after which every fixture path becomes
# an absolute one like /off, every write fails, and ac1 compares two files that do not exist and
# finds them identical. A gate that measures nothing and reports PASS is the worst outcome
# available, so the workspace is checked before any assertion runs.
gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

# ac1 — with nothing configured, the run is what it is today.
#
# The control is main's ralph-log.sh, not a recorded transcript: the unconfigured path must stay
# identical no matter what the configured path grows into, so the comparison has to be re-measured
# against main every time rather than frozen. Paths and pids differ per run and are normalised
# away; anything else differing is a regression in the portability bar.
# Normalise what cannot be stable between two runs, and nothing else. Commit SHAs differ every
# run; so does the ORDER of the loop's commit summary, because both fixture commits land inside
# the same second and git breaks that tie arbitrarily. Measured: this comparison failed main
# against main until both were handled, which would have failed correct work on every attempt.
# Sorting is applied after normalisation so a genuine difference in WHAT the run said still shows
# up — only the order of same-second commits is discarded.
norm() {
  sed -E 's#/tmp/[^ ]*#PATH#g; s#^[0-9a-f]{3,40} #SHA #; s#\b[0-9]{3,}\b#N#g' "$1" | sort
}

mkexec_loud
mkloop_logged "$T/off"; runloop_logged "$T/off"
off_rc="$RC"

mkdir -p "$T/ctl"
mkloop_logged "$T/ctl"
git -C "$ROOT" show origin/main:scripts/ralph-log.sh > "$T/ctl/scripts/ralph-log.sh" 2>/dev/null
runloop_logged "$T/ctl"

if [ ! -s "$T/ctl/scripts/ralph-log.sh" ]; then
  no "ac1: could not fetch main's ralph-log.sh for the control — the comparison did not run"
elif ! diff -q <(norm "$T/off.out") <(norm "$T/ctl.out") >/dev/null 2>&1; then
  no "ac1: an unconfigured run differs from the same run on main's ralph-log.sh: $(diff <(norm "$T/off.out") <(norm "$T/ctl.out") | head -4 | tr '\n' ' ' | cut -c1-300)"
elif [ "$off_rc" != 0 ]; then
  no "ac1: the unconfigured run exited $off_rc. Loop said: $(loopout off)"
else
  ok "ac1: with nothing configured the run is line-for-line the run it is today"
fi

# ac2 — a PASSING attempt ships prompt, gate, patch and meta.
coord_start
mkexec_loud; mkloop_logged "$T/on"
runloop_logged "$T/on" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN"
on_rc="$RC"
missing=""
for k in prompt gate patch meta; do
  [ "$(arts "$k")" -gt 0 ] 2>/dev/null || missing="$missing $k"
done
if [ "$on_rc" != 0 ]; then
  no "ac2: the run exited $on_rc with a coordinator configured. Loop said: $(loopout on)"
elif [ -n "$missing" ]; then
  no "ac2: a passing attempt shipped no$missing. Kinds that did arrive: [$(grep -o '/artifacts/[a-z]*' "$T/coord.log" | sort -u | tr '\n' ' ')]"
else
  ok "ac2: a passing attempt ships its prompt, gate output, patch and metadata"
fi

# ac3 — the path names the run, the task and the attempt, and the task is the SHORT label.
#
# Keyed on the PROMPT kind, which every attempt writes: keying a path check on an artifact that
# only some attempts produce would make this assertion skip rather than fail.
p="$(artpaths prompt | head -1)"
if [ -z "$p" ]; then
  no "ac3: no prompt artifact arrived, so the path could not be checked"
elif ! printf '%s' "$p" | grep -qE '^/runs/[^/]+/[^/]+/attempts/T[0-9x]+/[0-9]+/artifacts/prompt$'; then
  no "ac3: the artifact path is not /runs/{key}/attempts/{T<n>}/{attempt}/artifacts/{kind} — got '$p'. The task segment must be the short label log_task produces, not the task's prose"
else
  ok "ac3: artifacts are keyed by run, task and attempt, with the short task label"
fi

# ac4 — the bearer token travels, and only as a header.
auths="$(artauth prompt)"
if [ -z "$auths" ]; then
  no "ac4: no prompt artifact was posted at all, so no header could be checked — this assertion must not pass on an absent feature"
elif ! printf '%s\n' "$auths" | grep -q '^Bearer '; then
  no "ac4: an artifact post carried no Authorization: Bearer header. The coordinator received auth=[$(printf '%s' "$auths" | head -3 | tr '\n' ' ')] — a malformed or empty value means the flag was built as a string and word-split, not that the token is missing"
else
  ok "ac4: every artifact post carries the bearer token, as a header"
fi
coord_stop

# ac5 — an artifact that was never written is never announced.
#
# A passing run writes no .diff at all: log_failure runs only on failure. A push wired to fire
# unconditionally would announce one anyway, and a reader would open an artifact that does not
# exist. This is the assertion that separates "push after a successful write" from "push".
d_posts="$(arts diff)"
d_files="$(find "$T/on/.evidence/runs" -name '*.diff' 2>/dev/null | wc -l)"
if [ "$d_files" != 0 ]; then
  no "ac5: the passing fixture unexpectedly wrote $d_files .diff files, so this assertion did not test what it claims"
elif [ "$d_posts" != 0 ]; then
  no "ac5: $d_posts diff artifacts were posted for a run that wrote none — the push fires regardless of whether the write happened"
else
  ok "ac5: a kind whose file was never written is never posted"
fi

# ac6 — a FAILING attempt ships its diff. This is the artifact a reader most wants and the one
# that only exists on the failing path, so it needs its own run rather than an assertion bolted
# onto the passing one.
coord_start
mkexec_fail; mkloop_logged "$T/bad"
runloop_logged "$T/bad" HARNESS_REPORT_URL="$COORD_URL" HARNESS_REPORT_TOKEN="$TOKEN"
if [ "$(find "$T/bad/.evidence/runs" -name '*.diff' 2>/dev/null | wc -l)" = 0 ]; then
  no "ac6: the failing fixture wrote no .diff, so the assertion could not run — the fixture is wrong, not the implementation"
elif [ "$(arts diff)" -lt 1 ] 2>/dev/null; then
  no "ac6: a failing attempt wrote a .diff but shipped none. Kinds that arrived: [$(grep -o '/artifacts/[a-z]*' "$T/coord.log" | sort -u | tr '\n' ' ')]"
else
  ok "ac6: a failing attempt ships the diff of what it changed"
fi
coord_stop

# ac7 — an absent coordinator must not fail, stall, or say anything alarming.
mkexec_loud; mkloop_logged "$T/dead"
start="$(date +%s)"
runloop_logged "$T/dead" HARNESS_REPORT_URL="http://127.0.0.1:1"
el=$(( $(date +%s) - start ))
if [ "$RC" != 0 ]; then
  no "ac7: an unreachable coordinator failed the run (exit $RC). Loop said: $(loopout dead)"
elif [ "$el" -gt 150 ]; then
  no "ac7: an unreachable coordinator stalled the run for ${el}s — every call must be bounded"
elif grep -qiE 'curl:|urlopen|connection refused|traceback' "$T/dead.out"; then
  no "ac7: the run printed a transport error a reader would mistake for a loop failure: $(grep -iE 'curl:|urlopen|connection refused|traceback' "$T/dead.out" | head -2 | tr '\n' ' ' | cut -c1-200)"
else
  ok "ac7: an unreachable coordinator neither fails, stalls nor complains"
fi

# ac8 — the token leaks nowhere: not into the output, not into the evidence tree, and not into a
# URL. The URL case belongs HERE and not with the header assertion: a token moved from the header
# into a query string still authenticates, so the header check keeps passing while the secret is
# now written to the coordinator's access log and to every recorded path. Measured — a mutant
# doing exactly that tripped three OTHER assertions and never reached this one until the check
# was moved.
if grep -rq "$TOKEN" "$T/on.out" "$T/on/.evidence" 2>/dev/null; then
  no "ac8: the token leaked into the run's output or evidence: $(grep -rl "$TOKEN" "$T/on.out" "$T/on/.evidence" 2>/dev/null | head -2 | tr '\n' ' ')"
elif allpaths | grep -q "$TOKEN"; then
  no "ac8: the token appears in the request URL — it belongs in the Authorization header only, or it lands in the coordinator's access log. Offending path: $(allpaths | grep "$TOKEN" | head -1 | cut -c1-120)"
else
  ok "ac8: the token never appears in the output, the evidence, or a URL"
fi

gate_done
