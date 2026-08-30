#!/usr/bin/env bash
# specs/20260828e-record-fields/verify.sh — the deterministic gate for "the attempt record says
# what happened and how long it took".
#
# BEHAVIOURAL. It drives the real ralph-build.sh against a fixture spec with a mock executor
# scripted to produce each ending in turn — a pass, a no-op, and a stillborn — then reads the
# records that came out. Asserting on ralph-build's SOURCE would pass on a comment; the claim is
# about what the loop writes, so the gate reads what the loop wrote.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

BUILD="$R/scripts/ralph-build.sh"
NEST="$R/specs/20260826a-evidence-replayable/verify.sh"
bash -n "$BUILD" 2>/dev/null || { echo "  FAIL  scope: ralph-build.sh is not valid bash" >&2; exit 1; }
ok "scope: ralph-build.sh parses"

_stray="$(find "$R/specs/20260828e-record-fields" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence 2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$T/x"; chmod +x "$T/x" 2>/dev/null
"$T/x" 2>/dev/null || { echo "  FAIL  ENV: TMPDIR is noexec" >&2; echo "VERIFY: ENV" >&2; exit 2; }

# ── FIXTURE: one task, and a mock executor whose behaviour is scripted per attempt ─────────
P="$T/proj"; mkdir -p "$P/specs/demo"
git -C "$P" init -q 2>/dev/null; git -C "$P" config user.email g@e; git -C "$P" config user.name g
git -C "$P" checkout -q -b work 2>/dev/null
printf '# demo\n' > "$P/specs/demo/spec.md"
printf 'T1: make a.txt\n' > "$P/specs/demo/tasks.txt"
cat > "$P/specs/demo/verify.sh" <<'FIX'
#!/usr/bin/env bash
[ -f a.txt ] && { echo "  PASS  ac1"; exit 0; }
echo "  FAIL  ac1: no a.txt" >&2; exit 1
FIX
chmod +x "$P/specs/demo/verify.sh"
git -C "$P" add -A 2>/dev/null; git -C "$P" commit -qm base 2>/dev/null
BASE="$(git -C "$P" rev-parse HEAD 2>/dev/null)"

# MODE is read per invocation so one fixture yields three different endings.
cat > "$T/mock.sh" <<'MOCK'
#!/usr/bin/env bash
cd "${ROOT:?}" || exit 1
case "${MOCK_MODE:-pass}" in
  pass)      printf 'a\n' > a.txt ;;                      # gate goes green
  noop)      : ;;                                         # changes nothing
  stillborn) exit 7 ;;                                    # nonzero, no output
  reject)    printf 'x\n' > junk.txt ;;                    # changes something the gate rejects
esac
exit 0
MOCK
chmod +x "$T/mock.sh"

runloop(){ # runloop <mode> ; leaves records under $T/ev
  # HARD reset to the base commit, not checkout+rm. The `pass` mode COMMITS a.txt, so deleting
  # the file afterwards leaves a staged deletion — a dirty tree — and the no-op branch never
  # fires because the attempt did change something. The first draft of this gate did exactly
  # that and reported a no-op attempt as `failed`, which looked like a defect in ralph-build.
  rm -rf "$T/ev"
  git -C "$P" reset -q --hard "$BASE" 2>/dev/null; git -C "$P" clean -qfd 2>/dev/null
  ( cd "$P" && ROOT="$P" RALPH_EXEC_CMD="$T/mock.sh" MOCK_MODE="$1" RALPH_RETRIES=0 \
      RALPH_AGENT=gate RALPH_LOG_DIR="$T/ev" RALPH_STATUS_DIR="$T/st" RALPH_BUS_DISABLE=1 \
      bash "$BUILD" "$P/specs/demo" ) >/dev/null 2>&1
}
recs(){ find "$T/ev" -name 'T*-attempt*.json' 2>/dev/null; }
field(){ jq -r "$2 // empty" "$1" 2>/dev/null; }

# ── AC-1/AC-3/AC-4 · a passing attempt ─────────────────────────────────────────────────────
runloop pass
f="$(recs | head -1)"
if [ -z "$f" ]; then
  no "harness: a passing attempt produced no record at all — nothing below can be measured"
else
  o="$(field "$f" .outcome)"
  case "$o" in
    passed) ok "ac1: a passing attempt records outcome=passed" ;;
    "")     pend "ac1: outcome is empty on a passing attempt" ;;
    *)      no "ac1: outcome is '$o' on a passing attempt, expected 'passed'" ;;
  esac
  d="$(field "$f" .duration_s)"
  case "$d" in
    ""|null) pend "ac4: duration_s is null on an attempt that ran" ;;
    *[!0-9]*) no "ac4: duration_s is '$d', not a non-negative integer" ;;
    *)       ok "ac4: duration_s is a non-negative integer ($d)" ;;
  esac
  s="$(field "$f" .started)"; e="$(field "$f" .ended)"
  # `${LOG_STARTED:-0}` means an unset clock records 0, and 0 >= 0 satisfies a naive ordering
  # check — so the first draft of this AC passed on the very records it exists to reject.
  # A real stamp is a unix second, i.e. comfortably greater than zero.
  if [ "${s:-0}" -gt 1000000000 ] 2>/dev/null && [ "${e:-0}" -ge "${s:-0}" ] 2>/dev/null; then
    ok "ac3: started/ended are real unix seconds and ended is not before started"
  else
    pend "ac3: started/ended are '$s'/'$e' — an unset clock records 0, not a timestamp"
  fi
fi

# ── AC-2 · a no-op attempt must leave a record AT ALL ──────────────────────────────────────
runloop noop
f="$(recs | head -1)"
if [ -z "$f" ]; then
  pend "ac2: a no-op attempt leaves no record — the noop outcome is unreachable"
else
  # Keyed on T3's artefact, not T2's. Until the no-op branch has its OWN log_meta call, a no-op
  # falls through to the exhausted-attempts site and is recorded there as `failed` — which is
  # correct for the code that exists. Asserting `noop` before that call site exists makes T2
  # unpassable, which is the same defect as ac7 in specs/20260828b-index-nested-runs: a pend must
  # key on the artefact of the task that SATISFIES it, not one that merely precedes it. Second
  # occurrence in one night; the rule is easier to write down than to apply.
  _sites="$(sed 's/#.*//' "$BUILD" | grep -c 'log_meta ')"
  o="$(field "$f" .outcome)"
  if [ "${_sites:-0}" -lt 5 ]; then
    pend "ac2: the no-op branch has no log_meta call yet ($_sites sites, need 5)"
  else
    case "$o" in
      noop) ok "ac2: a no-op attempt records outcome=noop" ;;
      "")   pend "ac2: a no-op attempt records no outcome" ;;
      *)    no "ac2: a no-op attempt recorded outcome='$o', expected 'noop'" ;;
    esac
  fi
fi

# ── AC-5 · the stillborn path ──────────────────────────────────────────────────────────────
runloop stillborn
f="$(recs | head -1)"
if [ -z "$f" ]; then
  pend "ac5: the stillborn abort leaves no record"
else
  o="$(field "$f" .outcome)"
  case "$o" in
    stillborn) ok "ac5: a stillborn attempt records outcome=stillborn" ;;
    "")        pend "ac5: the stillborn abort records no outcome" ;;
    *)         no "ac5: stillborn attempt recorded outcome='$o'" ;;
  esac
fi

# ── AC-7 · a gate-rejected attempt is recorded at all ──────────────────────────────────────
# The gap that let a dead call site through: pass, no-op and stillborn each have their own
# ending, so a gate whose ACs cover only those three stays green while `failed` is unrecordable.
# Mock passes nothing the fixture gate accepts, so every attempt runs and is rejected.
runloop reject
f="$(recs | head -1)"
if [ -z "$f" ]; then
  pend "ac7: a gate-rejected attempt leaves no record at all"
else
  o="$(field "$f" .outcome)"
  case "$o" in
    failed) ok "ac7: a gate-rejected attempt records outcome=failed" ;;
    "")     pend "ac7: a gate-rejected attempt records no outcome" ;;
    *)      no "ac7: a gate-rejected attempt recorded outcome='$o', expected 'failed'" ;;
  esac
fi

# ── CONTROL · the declared set is closed ───────────────────────────────────────────────────
# An invented value is worse than an empty one: the consumer (ADR-001 D6) maps anything outside
# the set to `failed`, so a typo silently marks good runs bad.
_bad=""
for f in $(recs); do
  o="$(field "$f" .outcome)"
  case "$o" in passed|failed|noop|stillborn|"") ;; *) _bad="$_bad $o" ;; esac
done
[ -n "$_bad" ] && no "control: an outcome outside the declared set —$_bad" \
               || ok "control: every recorded outcome is inside the declared set"

# ── AC-6 · the detector that let this ship now asserts values ──────────────────────────────
if [ ! -r "$NEST" ]; then
  no "ac6: specs/20260826a-evidence-replayable/verify.sh is missing"
elif grep -q "passed|failed|noop|stillborn" "$NEST" 2>/dev/null; then
  # NOT a bare grep for "stillborn": that word already appears once in that file (in prose),
  # so the first draft of this AC passed before the work existed. The marker has to be a
  # construct only a value assertion would contain.
  ok "ac6: evidence-replayable's gate now asserts the outcome's VALUE, not just its key"
else
  pend "ac6: evidence-replayable's gate still only checks has(\"outcome\")"
fi

# ── ac8 · a gate that goes green but a commit that does not land is NOT a pass ─────────────
#
# The one ending no fixture in this repo could reach, because every fixture sets a git identity
# and no image in this repo provides one. Before the fix, `git commit … || true` swallowed the
# failure, `outcome=passed` had ALREADY been written, the loop continued, and the next task's
# failure path (`git checkout -- .`) deleted work that had genuinely gone green.
#
# The fixture removes every source of an identity — local, global, system and the env — so the
# commit fails for the reason a container fails, not for a reason invented here.
git -C "$P" config --unset user.email 2>/dev/null || true
git -C "$P" config --unset user.name  2>/dev/null || true
mkdir -p "$T/nohome"
rm -rf "$T/ev8"
git -C "$P" reset -q --hard "$BASE" 2>/dev/null; git -C "$P" clean -qfd 2>/dev/null
_h8="$(git -C "$P" rev-parse HEAD 2>/dev/null)"
( cd "$P" && HOME="$T/nohome" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null \
    GIT_AUTHOR_NAME= GIT_AUTHOR_EMAIL= GIT_COMMITTER_NAME= GIT_COMMITTER_EMAIL= EMAIL= \
    ROOT="$P" RALPH_EXEC_CMD="$T/mock.sh" MOCK_MODE=pass RALPH_RETRIES=0 \
    RALPH_AGENT=gate RALPH_LOG_DIR="$T/ev8" RALPH_STATUS_DIR="$T/st8" RALPH_BUS_DISABLE=1 \
    bash "$BUILD" "$P/specs/demo" ) > "$T/out8" 2>&1
_rc8=$?
_h8b="$(git -C "$P" rev-parse HEAD 2>/dev/null)"
_o8="$(for f in $(find "$T/ev8" -name 'T*-attempt*.json' 2>/dev/null); do jq -r '.outcome // empty' "$f" 2>/dev/null; done | tr '\n' ' ')"

if [ "$_h8" != "$_h8b" ]; then
  # The control. If a commit DID land, the identity leaked in from somewhere and this whole
  # assertion is measuring nothing — which is indistinguishable from a pass unless it is said.
  no "ac8: the fixture committed anyway (HEAD moved) — an identity reached it, so this check did not exercise the failure it exists to cover"
elif [ "$_rc8" = 0 ]; then
  no "ac8: the commit did not land and the loop still exited 0. It reports success for a task whose work is only in the working tree, and the next task's reset deletes it"
elif printf '%s' "$_o8" | grep -qw passed; then
  no "ac8: an attempt recorded outcome=passed with no commit behind it [$_o8]. The record is the durable claim; a green gate is not a saved change"
elif ! grep -qi 'commit' "$T/out8"; then
  no "ac8: the run stopped but never said the COMMIT was the problem. 'Gate failed' and 'gate passed, commit did not land' need different messages or the next reader retries the executor"
else
  ok "ac8: a green gate with no commit behind it aborts, says why, and records outcome=$_o8"
fi
git -C "$P" config user.email g@e; git -C "$P" config user.name g

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
