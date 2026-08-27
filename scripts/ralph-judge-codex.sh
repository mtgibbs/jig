#!/usr/bin/env bash
# ralph-judge-codex.sh — the JUDGE_CMD binding for ralph-judge.sh: Codex as intent judge.
#
# Per the judge-loop spec §3 (amended after the first-run triage #3), command bindings live
# HERE at the operator layer, never as defaults inside the loop. Pairing:
#   JUDGE_CMD=scripts/ralph-judge-codex.sh EXECUTOR_CMD=scripts/ralph-judge-exec-qwen.sh \
#     scripts/ralph-judge.sh specs/<feature>
#
# Mode 1: ralph-judge-codex.sh <spec-dir>                 -> findings JSONL on stdout, nothing else
# Mode 2: ralph-judge-codex.sh --check-resolution <json>  -> {"id":...,"resolved":bool} on stdout
#
# Codex runs read-only; its final message IS the payload (--output-last-message), the streamed
# transcript is discarded, and markdown fences are stripped defensively. ralph-judge's JSONL
# validation stays the real guard — this wrapper never repairs content, only unwraps it.
#
# ANCHORS ARE RESOLVED HERE, BY ABSOLUTE PATH, AND NAMED OUT LOUD. The prompt used to ask for
# `specs/constitution.md` and `specs/amendments.md` — paths relative to whatever repo the loop
# happened to be pointed at — with "skip silently if absent", under a rule that says "no anchor,
# no finding". Off pi-cluster that combination is a judge that quietly loses whole categories of
# finding and still reports clean, which is indistinguishable from a clean diff. Measured in
# notes-from-hearing: constitution.md present, amendments.md absent, judge-loop/spec.md absent —
# so it degraded PARTIALLY, which is harder to notice than not running at all.
#
# Now: this script knows where it lives, so the HARNESS anchors resolve from its own checkout
# and cannot go missing when the loop is aimed elsewhere; the PROJECT's own anchors resolve from
# the target repo and are genuinely optional. Only files verified to exist are named in the
# prompt, every resolution is reported on stderr (ralph-judge captures stdout only, so this
# lands in the run log), and a missing HARNESS constitution is fatal rather than quiet — that
# is a broken checkout, and a judge with no principles to cite must not return "nothing found".
#
# Verified 2026-08-27 in coding-harness-codex: `codex exec --sandbox read-only` reads absolute
# paths outside cwd — read-only restricts writes, not reads. That is what makes this work.
set -uo pipefail
command -v codex >/dev/null 2>&1 || { echo "ralph-judge-codex: codex CLI not on PATH" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HSPECS="$(cd "$SCRIPT_DIR/.." && pwd)/specs"
# Same shape as exec-qwen.sh: honour an exported ROOT, derive it if the caller did not set one.
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

ANCHORS=""; RESOLVED=""; ABSENT=""; SEEN=""
anchor(){  # anchor <path> <label>
  if [ ! -f "$1" ]; then ABSENT="$ABSENT $2"; return; fi
  # Judging the harness repo itself makes the harness anchors and the "project" anchors the
  # same files reached two ways. Naming a path twice just spends the judge's context reading
  # it twice, so dedupe on identity, not on the string.
  local real; real="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
  case " $SEEN " in *" $real "*) return;; esac
  SEEN="$SEEN $real"
  ANCHORS="$ANCHORS
- $real  — $2"
  RESOLVED="$RESOLVED $2"
}

HCONST="$HSPECS/constitution.md"
[ -f "$HCONST" ] || {
  echo "ralph-judge-codex: harness constitution missing at $HCONST — refusing to judge with no principles to cite (broken harness checkout)" >&2
  exit 2
}
anchor "$HCONST"                  "harness constitution"
anchor "$HSPECS/amendments.md"    "harness amendments"
anchor "$ROOT/specs/constitution.md" "project constitution"
anchor "$ROOT/specs/amendments.md"   "project amendments"

ROLE="$HSPECS/judge-loop/spec.md"
[ -f "$ROLE" ] && ROLE_CITE="$ROLE §§3-4,7-8" || { ROLE_CITE="(role brief unavailable)"; ABSENT="$ABSENT judge-loop-spec"; }

echo "ralph-judge-codex: anchors resolved:${RESOLVED:- none}${ABSENT:+ | ABSENT:$ABSENT}" >&2
OUT="$(mktemp "${TMPDIR:-/tmp}/rj-codex.XXXXXX")"
trap 'rm -f "$OUT"' EXIT

strip_fences(){ sed -e 's/^```[a-z]*$//' -e 's/^```$//' "$1" | sed '/^[[:space:]]*$/d'; }

if [ "${1:-}" = "--check-resolution" ]; then
  F="${2:?finding json required}"
  codex exec --sandbox read-only --output-last-message "$OUT" "You are the resolution checker in an automated judge loop, running in a git worktree.
FINDING (already applied to the worktree as uncommitted changes): $F
Run 'git diff' and read the touched file. Decide: does the applied change actually resolve THIS finding's problem (not merely change something)?
Your ENTIRE final message must be exactly one JSON object, no prose, no code fences:
{\"id\":\"<the finding id>\",\"resolved\":true} or {\"id\":\"<the finding id>\",\"resolved\":false}" >/dev/null 2>&1
  strip_fences "$OUT"
  exit 0
fi

SPEC_DIR="${1:?usage: ralph-judge-codex.sh <spec-dir>}"
codex exec --sandbox read-only --output-last-message "$OUT" "You are the JUDGE in ralph-judge (see $ROLE_CITE for your role). The deterministic gate is already green; your job is quality the gate cannot see. Review the solution for spec '$SPEC_DIR' against its INTENT.

Read: $SPEC_DIR/spec.md — its Touches/Scope sections name the solution files; read those files, and $SPEC_DIR/verify.sh.

Read these anchor documents too. Every path below has been verified to exist — read all of them, and do not substitute a relative path for any of them:$ANCHORS
An Accepted amendment carries the same weight as a founding principle. Where a project document and a harness document both apply, cite the one that actually governs the point.

Emit findings ONLY within the conservative v1 surface: localized comments, naming, clarity, and literal spec-fidelity corrections. Anything bigger (refactors, dead code, missing gate checks) must be kind=gate-gap (report-only). Every finding MUST cite a real spec section, constitution principle, or Accepted amendment heading as spec_anchor — no anchor, no finding. Never cite an amendment whose Status is not Accepted. Do not propose changes to behavior.

OUTPUT CONTRACT — your ENTIRE final message is 0..5 lines, each line one JSON object, NO prose, NO code fences, NO trailing commentary:
{\"id\":\"<kebab-slug>\",\"file\":\"<repo-relative path>\",\"line\":<integer >=1>,\"category\":\"clarity|naming|spec-fidelity|gate-gap\",\"spec_anchor\":\"<§ or principle>\",\"problem\":\"<one sentence>\",\"suggested_change\":\"<concrete, small, applyable instruction>\",\"kind\":\"mutate|gate-gap\"}
Fields exactly as listed, no extras. id must match ^[a-z0-9][a-z0-9-]*$. An empty message means: nothing worth changing." >/dev/null 2>&1
strip_fences "$OUT"
exit 0
