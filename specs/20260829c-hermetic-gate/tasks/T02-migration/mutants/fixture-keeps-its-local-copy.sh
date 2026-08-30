# MUTANT: ac01
# TARGET: specs/20260829a-executor-image-layer/lib/fixtures.sh
# WHY: keeps its local unset while the central reset also exists. Every gate passes, nothing is
# WHY: broken, and the class stays open: two mechanisms for one rule, which is the state this
# WHY: spec was written to end.
# fixtures.sh — helpers shared by this spec's per-task gates.
#
# Deliberately small. The heavy fixture in this repo is
# specs/20260828m-worker-channel/lib/fixtures.sh, which stands up a two-task repo carrying the
# real scripts/ and runs a loop against it. Nothing here needs a running loop: every assertion
# in this spec is about the TEXT of a Dockerfile, a workflow, a resolver or a doc, plus two
# small git fixtures for run-task.sh's clone paths. Sourcing that file would drag a whole
# executor stub in for nothing.

# The harness's OWN configuration is unset for every gate sourcing this file, and it is not
# housekeeping. T02 and T03 drive the real run-loop.sh; HARNESS_REPORT_URL is set in every harness
# container, so a gate run inherits it and the fixture loops POST TO THE PRODUCTION COORDINATOR.
# Measured 2026-08-29: one pass over this spec's six gates put eight rows keyed `spec=fx` on the
# live fleet board, where they are indistinguishable from real runs and share the oldest-first
# eviction in harness#46 — so fixture rows can evict the record of an actual run.
#
# RALPH_FORCE_ALL/_FROM go too: a gate that inherits them from the shell that launched it cannot
# skip anything inside its fixtures, which on 2026-08-29 made four assertions in another spec
# unable to pass whatever the executor wrote and one pass for the wrong reason. Unset, never a
# sentinel — a sentinel URL is still a URL and something eventually POSTs to it.
#
# 20260829a-hermetic-gate moves this into specs/lib/assert.sh so it holds for every gate in the
# repo rather than for the ones whose author remembered.
unset HARNESS_REPORT_URL HARNESS_REPORT_TOKEN RALPH_FORCE_ALL RALPH_FORCE_FROM RALPH_SATISFIED_TIMEOUT

# strip_comments <file> — the file's instruction lines only, comments and blanks removed.
#
# THE reason this exists. Every string worth grepping in this spec — harness-base, opencode,
# STRATEGY_TOOLS, HARNESS_DIR, run-task.sh — appears in prose and in comments inside this very
# repo, including in the file being checked. A grep that sees comments passes with the feature
# absent, which is Trap A exactly. Every content assertion below runs through this.
strip_comments() {
  sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$1" 2>/dev/null
}

# instr <file> <regex> — does an INSTRUCTION line (not a comment) match?
instr() {
  strip_comments "$1" | grep -qE "$2"
}

# nonempty_strip <file> — proves strip_comments did not eat the whole file.
#
# Trap A-prime: a scope that is written but inert looks exactly like one that works. If
# strip_comments returns nothing — wrong path, unreadable file, a sed that consumed everything —
# then every `instr ... ` absence assertion is satisfied for free. Call this before trusting one.
nonempty_strip() {
  [ -n "$(strip_comments "$1" | head -1)" ]
}

# mkrepo <dir> — a throwaway git repo with one commit, on a non-main branch.
#
# run-loop.sh refuses to run on main (constitution worktree rule), so a fixture repo checked out
# on main tests the refusal and nothing else.
mkrepo() {
  local d="$1"
  mkdir -p "$d"
  git -C "$d" init -q -b main .
  git -C "$d" config user.email t@t
  git -C "$d" config user.name t
  : > "$d/.keep"
  git -C "$d" add -A
  git -C "$d" commit -qm init
  git -C "$d" checkout -q -b fixture/work
}

# mkspec <repo-dir> <name> — the minimum a spec dir needs to get past run-loop.sh's preflight.
mkspec() {
  local d="$1/specs/$2"
  mkdir -p "$d"
  printf '# Spec: %s\n\n- **Tools:** none\n- **MCP:** none\n' "$2" > "$d/spec.md"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/verify.sh"
  printf 'T1: do the thing.\n' > "$d/tasks.txt"
}

# bounded <seconds> <cmd...> — run with a hard wall-clock bound, portably.
#
# NOT `timeout`. macOS ships neither `timeout` nor `gtimeout`, and this gate is authored on one.
# `perl -e alarm` is present on both platforms and needs no coreutils.
#
# The stronger claim this comment used to make — that scripts/gate-selftest.sh cannot run on macOS
# at all, so every mutant returns WRONG-REASON — was true when written and was FIXED by #51, which
# merged forty-six minutes before this spec did. gate-selftest now bounds the gate with `bound`
# from scripts/bound.sh. Corrected because the claim discourages running the repo's own mutation
# tool, which does work: this spec's T01 and T06 corpora were run through it, 12 mutants, 12
# killed, no survivors and no wrong-reason.
#
# The bound is not tidiness. A fixture that resolves the WRONG strategy runs the real
# build-converge, which invokes ralph-build.sh, which calls an executor and waits. Unbounded,
# the gate does not fail — it hangs, and a hang and a failure are two states a check must tell
# apart (specs/amendments.md).
bounded() {
  local secs="$1"; shift
  perl -e 'alarm shift; exec @ARGV or exit 127' "$secs" "$@"
}

# content <file> — the artifact's real content, with any mutation header removed.
#
# FOUND THE HARD WAY, 2026-08-29, writing this spec's own corpus. A mutant declares its defect in
# `# WHY:` lines. When the gate greps the target file for a token, the WHY line SAYING THE TOKEN
# IS ABSENT satisfies the grep, and the gate passes on an artifact that genuinely lacks it. Two
# of six doc mutants came back WRONG-REASON for exactly this, and both looked like weak
# assertions when the assertions were correct.
#
#   # WHY: never mentions the .harness search path      <- the gate's grep for '.harness' matches
#
# It is Trap A with the needle planted by the tooling itself, and it applies to any gate that
# reads a target's text. A MUTANT: / TARGET: / WHY: line is the tool's metadata, never the
# artifact's content, so dropping it is correct for every reader — not a special case for tests.
# The deeper fix belongs in scripts/gate-selftest.sh, which should strip the header when it
# installs the mutant; see this spec's evidence/.
content() {
  grep -vE '^[[:space:]]*#[[:space:]]*(MUTANT|TARGET|WHY):' "$1" 2>/dev/null
}

# hasc <file> <regex> — case-insensitive match against CONTENT, never against a mutation header.
hasc() { content "$1" | grep -qiE -- "$2"; }
