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

# MODE is read per invocation so one fixture yields three different endings.
cat > "$T/mock.sh" <<'MOCK'
#!/usr/bin/env bash
cd "${ROOT:?}" || exit 1
case "${MOCK_MODE:-pass}" in
  pass)      printf 'a\n' > a.txt ;;                      # gate goes green
  noop)      : ;;                                         # changes nothing
  stillborn) exit 7 ;;                                    # nonzero, no output
esac
exit 0
MOCK
chmod +x "$T/mock.sh"

runloop(){ # runloop <mode> ; leaves records under $T/ev
  rm -rf "$T/ev"; git -C "$P" checkout -q -- . 2>/dev/null; rm -f "$P/a.txt"
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
  o="$(field "$f" .outcome)"
  case "$o" in
    noop) ok "ac2: a no-op attempt records outcome=noop" ;;
    "")   pend "ac2: a no-op attempt records no outcome" ;;
    *)    no "ac2: a no-op attempt recorded outcome='$o', expected 'noop'" ;;
  esac
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
elif grep -qE 'outcome[^)]*\)[^)]*(passed|noop)' "$NEST" 2>/dev/null \
     || grep -qE '\.outcome.*==.*"(passed|noop)"|IN\("passed"' "$NEST" 2>/dev/null; then
  # NOT a bare grep for "stillborn": that word already appears once in that file (in prose),
  # so the first draft of this AC passed before the work existed. The marker has to be a
  # construct only a value assertion would contain.
  ok "ac6: evidence-replayable's gate now asserts the outcome's VALUE, not just its key"
else
  pend "ac6: evidence-replayable's gate still only checks has(\"outcome\")"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
