#!/usr/bin/env bash
# specs/20260828c-strategy-file-extension/verify.sh — the deterministic gate for "a strategy file
# stops looking like a secrets file".
#
# BEHAVIOURAL where it can be: run-loop.sh is invoked for real, so resolution is measured rather
# than grepped. The one thing this gate CANNOT do is prove the executor's permission guard is
# satisfied — that needs a model call. What it can do, and what outlives the rename, is assert
# that no strategy file carries an extension from the secret-bearing set at all.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

LOOPS="$R/scripts/loops"
RUNLOOP="$R/scripts/run-loop.sh"

[ -r "$RUNLOOP" ] || { echo "  FAIL  scope: run-loop.sh missing" >&2; exit 1; }
bash -n "$RUNLOOP" 2>/dev/null || { echo "  FAIL  scope: run-loop.sh is not valid bash" >&2; exit 1; }
ok "scope: run-loop.sh exists and parses"

_stray="$(find "$R/specs/20260828c-strategy-file-extension" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence \
          2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

# ── AC-1 · the extension, and the guard that outlives this change ──────────────────────────
# The measured rule (2026-08-28 fixture): the executor's guard matches `env` as a dotted
# component ANYWHERE in the name — cand.env.sh was blocked while cand.sh, .bash, .conf,
# .strategy, .loop and .ini were all read. So the check is on the whole filename, not just the
# final extension, and it covers the neighbouring secret-bearing names too.
_bad=""
for f in "$LOOPS"/*; do
  [ -f "$f" ] || continue
  b="$(basename "$f")"
  case ".$b." in
    *.env.*|*.envrc.*|*.pem.*|*.key.*|*.secret.*|*.credentials.*) _bad="$_bad $b" ;;
  esac
done
if [ -n "$_bad" ]; then
  pend "ac1: a strategy file still carries a secret-bearing name —$_bad"
else
  ok "ac1: no file under scripts/loops/ carries a secret-bearing name"
fi

_conf=0; for f in "$LOOPS"/*.conf; do [ -f "$f" ] && _conf=$((_conf + 1)); done
[ "$_conf" -ge 5 ] && ok "ac1: all five strategies are .conf ($_conf found)" \
                   || pend "ac1: only $_conf .conf strategies present, expected 5"

# ── AC-2 · --list still names every strategy ───────────────────────────────────────────────
LIST="$(bash "$RUNLOOP" --list 2>&1 || true)"
_missing=""
for s in build-codex build-container build-converge build-then-judge judge-refine; do
  printf '%s' "$LIST" | grep -q "$s" || _missing="$_missing $s"
done
if [ -z "$_missing" ]; then
  ok "ac2: --list names all five strategies"
else
  pend "ac2: --list is missing —$_missing"
fi
printf '%s' "$LIST" | grep -q '\.conf' \
  && no "ac2: --list prints the extension; it strips it today and must keep stripping it" \
  || ok "ac2: --list still prints bare strategy names, extension stripped"

# ── AC-3 · resolution, measured by invoking it ─────────────────────────────────────────────
# A known strategy with a bogus spec dir must get PAST strategy resolution and fail on the spec.
# An unknown strategy must fail AT resolution. The pair is what makes either meaningful: if the
# first message were also "unknown strategy", the check would prove nothing.
OUT_KNOWN="$(bash "$RUNLOOP" build-converge "$T/nope" 2>&1 || true)"
OUT_UNKNOWN="$(bash "$RUNLOOP" definitely-not-a-strategy "$T/nope" 2>&1 || true)"

printf '%s' "$OUT_UNKNOWN" | grep -q "unknown strategy" \
  && ok "control: an unknown strategy still fails at resolution with the same message" \
  || no "control: an unknown strategy did not report 'unknown strategy' — ac3 below proves nothing"

if printf '%s' "$OUT_KNOWN" | grep -q "unknown strategy"; then
  pend "ac3: build-converge does not resolve (still reported as unknown)"
elif printf '%s' "$OUT_KNOWN" | grep -q "needs spec.md"; then
  ok "ac3: a known strategy resolves and fails later, on the spec dir — resolution works"
else
  pend "ac3: build-converge resolution is unclear from run-loop.sh's output"
fi

# ── AC-4 · no tracked file still calls a strategy <name>.env ───────────────────────────────
# `.evidence/` is EXCLUDED on purpose: index-*.md/jsonl are generated records of runs that
# really did source a file called build-converge.env. Rewriting them would falsify history to
# satisfy a rename, and the next regeneration would put the old string back anyway.
_refs="$(cd "$R" && git grep -lE "(build-codex|build-container|build-converge|build-then-judge|judge-refine)\.env" \
         -- . ':!specs/20260828c-strategy-file-extension' ':!.evidence' 2>/dev/null)"
# NO `head`. This list IS the work order: it reaches the executor through ralph-build.sh's
# retry feedback, and the tree is reset between attempts, so a truncated list hands the next
# attempt a different partial TODO every time and it never sees the whole job. Measured on this
# spec: attempt 1 was told about 3 files, attempt 2 about a different 3, out of 9 that needed
# changing. That is not the executor failing to learn — it is the gate never showing it the job.
if [ -n "$_refs" ]; then
  pend "ac4: strategy still referenced as <name>.env in — $(printf '%s' "$_refs" | tr '\n' ' ')"
else
  ok "ac4: no tracked file refers to a strategy as <name>.env"
fi

# ── AC-5 · they are still sourceable shell ─────────────────────────────────────────────────
_badsh=""
for f in "$LOOPS"/*.conf; do
  [ -f "$f" ] || continue
  bash -n "$f" 2>/dev/null || _badsh="$_badsh $(basename "$f")"
done
if [ "$_conf" = 0 ]; then
  pend "ac5: strategy files are sourceable shell"
elif [ -n "$_badsh" ]; then
  no "ac5: not valid shell —$_badsh (run-loop.sh sources these with .)"
else
  ok "ac5: every .conf strategy is bash -n clean and still sourceable"
fi

# ── AC-6 · the contract's prose matches the contract ───────────────────────────────────────
if grep -qE 'scripts/loops/<name>\.env' "$RUNLOOP" 2>/dev/null; then
  pend "ac6: run-loop.sh's header comment still states the .env contract"
else
  ok "ac6: run-loop.sh's header comment no longer states the old extension"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
