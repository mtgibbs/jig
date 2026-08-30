#!/usr/bin/env bash
# T1 — the loop ships in a base image with no model CLI, and the executor image is a thin layer.
#
# IDS ARE TWO-DIGIT ON PURPOSE. gate-selftest.sh kills a mutant by grepping the gate output for
# `FAIL.*<id>`, which is a SUBSTRING match — so with single digits a mutant declaring `ac1` is
# reported KILLED whenever `ac10` fails, and the author is told an assertion is strong when it
# was never exercised. Padding removes the alias. The same hazard exists in every gate here that
# reaches ten assertions; this one is the first that does.
#
# Map to the spec: ac01-ac06 are AC-1..AC-6; ac07 is AC-6b, ac08 AC-6c, ac09 AC-6d, ac10 AC-6e.
#
# Docker-free by design. CI builds two architectures; a gate that shells out to `docker build` is
# neither deterministic nor offline, which is the same reason docs/loop-container.md exists as a
# runbook rather than as criteria. Every assertion here reads the INSTRUCTION lines of a
# Dockerfile or the structure of the workflow — never a comment, never prose.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829a-executor-image-layer/lib/fixtures.sh"

# ac10 runs a real loop, so this gate now needs a workspace. Guarded the way the others are:
# a temp dir that cannot execute is an environment fault, not a failing assertion.
gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac00: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

BASE="$ROOT/docker/harness-base.Dockerfile"
DERIVED="$ROOT/docker/loop-executor-opencode.Dockerfile"
OLD_DERIVED="$ROOT/docker/loop-executor.Dockerfile"
WF="$ROOT/.github/workflows/build-images.yml"
EC="$ROOT/scripts/exec-container.sh"
BV="$ROOT/docker/harness-base.VERSION"

# ── ac1: the base carries the loop ───────────────────────────────────────────────────────────
# Assert on the COPY set, not on "the file mentions scripts". A Dockerfile that says
# `# copies scripts/` in a comment and copies nothing would satisfy the lazy form.
if [ ! -f "$BASE" ]; then
  no "ac01: docker/harness-base.Dockerfile does not exist — the base image is the whole seam"
elif ! nonempty_strip "$BASE"; then
  no "ac01: harness-base.Dockerfile has no instruction lines at all (only comments?) — every content check below would pass for free"
else
  missing=""
  instr "$BASE" 'COPY[[:space:]].*scripts'    || missing="$missing scripts/"
  instr "$BASE" 'COPY[[:space:]].*specs/lib'  || missing="$missing specs/lib/"
  if [ -n "$missing" ]; then
    no "ac01: harness-base.Dockerfile has no COPY instruction bringing in:$missing. A base image without the loop is the current loop-executor with a new name"
  else
    ok "ac01: the base COPYs the loop and the assertion vocabulary"
  fi
fi

# ── ac2: the base carries NO model CLI ───────────────────────────────────────────────────────
# An ABSENCE assertion, so it is worthless without the nonempty_strip guard above and without a
# mutant that plants an install. Scoped to instruction lines: the file's own header comment will
# say the words "opencode" and "claude" while explaining why they are not here.
if [ ! -f "$BASE" ]; then
  no "ac02: no harness-base.Dockerfile to check for a CLI"
elif ! nonempty_strip "$BASE"; then
  no "ac02: harness-base.Dockerfile has no instruction lines — the absence check cannot mean anything"
else
  planted=""
  for cli in opencode codex claude gemini; do
    instr "$BASE" "(npm[[:space:]]+install|pip[[:space:]]+install|pipx|curl.*install).*$cli" \
      && planted="$planted $cli"
  done
  if [ -n "$planted" ]; then
    no "ac02: harness-base.Dockerfile installs a model CLI:$planted. The base having no CLI is what lets someone else write FROM harness-base — an opinionated base is the fork it replaces"
  else
    ok "ac02: the base installs no model CLI"
  fi
fi

# ── ac3: the derived image is thin ───────────────────────────────────────────────────────────
if [ ! -f "$DERIVED" ]; then
  no "ac03: docker/loop-executor-opencode.Dockerfile is missing. After the split the BASE is what executes loops, so the generic name belongs to it; loop-executor-codex and loop-executor-claude are the point and they cannot all be 'loop-executor'"
elif [ -f "$OLD_DERIVED" ]; then
  no "ac03: both docker/loop-executor.Dockerfile and the renamed loop-executor-opencode.Dockerfile exist. A rename that leaves the old file behind is a copy, and CI will build whichever the matrix still names"
elif ! nonempty_strip "$DERIVED"; then
  no "ac03: loop-executor.Dockerfile has no instruction lines"
elif ! instr "$DERIVED" '^FROM[[:space:]]+.*harness-base'; then
  no "ac03: loop-executor.Dockerfile does not begin FROM the base — it is still a standalone image, which is the shape this task exists to remove. FROM line: $(strip_comments "$DERIVED" | grep -i '^FROM' | head -1)"
elif instr "$DERIVED" 'apt-get[[:space:]]+install'; then
  no "ac03: loop-executor.Dockerfile still apt-get installs. Those packages belong in the base; installing them twice means the next executor image re-solves them a third time"
elif instr "$DERIVED" 'COPY[[:space:]].*(scripts|specs/lib)'; then
  no "ac03: loop-executor.Dockerfile copies the harness itself. It inherits it from the base; a second copy is the drift this whole spec is about"
else
  ok "ac03: the derived image is FROM the base and adds only its CLI"
fi

# ── ac4: PATH and ENTRYPOINT ─────────────────────────────────────────────────────────────────
if [ ! -f "$BASE" ]; then
  no "ac04: no harness-base.Dockerfile to check for PATH/ENTRYPOINT"
else
  if ! instr "$BASE" 'ENV[[:space:]].*PATH.*scripts' && ! instr "$BASE" 'ENV[[:space:]]+PATH'; then
    no "ac04: harness-base.Dockerfile never puts the harness scripts on PATH, so run-task.sh and run-loop.sh are only reachable by absolute path"
  elif ! instr "$BASE" 'ENTRYPOINT.*run-task\.sh'; then
    no "ac04: the base ENTRYPOINT is not run-task.sh. Found: $(strip_comments "$BASE" | grep -i '^ENTRYPOINT' | head -1). The entrypoint IS the contract a derived image inherits"
  elif ! instr "$BASE" 'ENTRYPOINT.*tini'; then
    no "ac04: the ENTRYPOINT does not wrap tini. The current loop-executor wraps opencode in tini for signal handling and zombie reaping; a Job that cannot be terminated cleanly is worse in a pod than on a laptop"
  else
    ok "ac04: PATH carries the harness scripts and ENTRYPOINT is run-task.sh under tini"
  fi
fi

# ── ac5: CI builds the base first, and says so ───────────────────────────────────────────────
# Structural, not textual: `needs:` is the assertion, because a third matrix row that merely
# NAMES harness-base would satisfy any grep for the string while still racing.
if [ ! -f "$WF" ]; then
  no "ac05: .github/workflows/build-images.yml is missing"
elif ! grep -q 'harness-base' "$WF"; then
  no "ac05: the workflow never builds harness-base, so the base image only ever exists on someone's laptop"
elif [ ! -f "$BV" ]; then
  no "ac05: docker/harness-base.VERSION does not exist — the workflow reads the tag from a version file and would tag the image ':'"
elif ! grep -qE '^[[:space:]]*needs:' "$WF"; then
  no "ac05: the workflow declares no needs: edge. A matrix runs its entries in PARALLEL, so a base row and a derived row race and the derived build pulls a tag still being built — intermittently, only when both change in one push, which is the worst kind to leave implicit"
else
  ok "ac05: harness-base is built from its VERSION file, ahead of the derived image via needs:"
fi

# ── ac6: the container binding points at a tag that exists ───────────────────────────────────
# The one live defect this task fixes: CI has only ever pushed the VERSION tag, so
# ghcr.io/mtgibbs/loop-executor:latest has never existed, and exec-container.sh defaults to it.
if [ ! -f "$EC" ]; then
  no "ac06: scripts/exec-container.sh is missing"
elif instr "$EC" 'LOOP_IMAGE:-[^"}]*:latest'; then
  no "ac06: exec-container.sh still defaults LOOP_IMAGE to a :latest tag that CI has never pushed. The default of the containerised binding must be an image that exists"
elif instr "$EC" 'LOOP_IMAGE:-[^"}]*/loop-executor:'; then
  no "ac06: exec-container.sh still defaults to the OLD image name. The tag may be real and the repository is not the one CI now publishes — an image that exists and an image CI publishes are two different things"
elif ! instr "$EC" 'LOOP_IMAGE'; then
  no "ac06: exec-container.sh no longer honours LOOP_IMAGE at all — the override is the seam, do not remove it while fixing the default"
else
  ok "ac06: exec-container.sh defaults to a tag CI publishes"
fi

# ── ac07: the base is rebuilt when its CONTENTS change ───────────────────────────────────────
# Baking the harness into an image makes the trigger load-bearing. `paths: docker/**` alone means
# a change to scripts/ never rebuilds the base, the image silently pins an old harness, and local
# and fleet run files with the same names at different revisions — cliff 1, quietly.
if [ ! -f "$WF" ]; then
  no "ac07: no workflow to check rebuild triggers"
else
  _miss=""
  grep -qE "^[[:space:]]*-[[:space:]]*'?scripts/" "$WF"   || _miss="$_miss scripts/**"
  grep -qE "^[[:space:]]*-[[:space:]]*'?specs/lib/" "$WF" || _miss="$_miss specs/lib/**"
  if [ -n "$_miss" ]; then
    no "ac07: the workflow does not rebuild on:$_miss — the base bakes those paths, so a harness change would ship only to laptops and the image would keep an older loop with no sign it had"
  else
    ok "ac07: a change to the baked harness rebuilds the base"
  fi
fi

# ── ac08: the default binding drives opencode, and acquires no credential ────────────────────
XQ="$ROOT/scripts/exec-qwen.sh"
if [ ! -f "$XQ" ]; then
  no "ac08: scripts/exec-qwen.sh is missing"
elif ! nonempty_strip "$XQ"; then
  no "ac08: exec-qwen.sh has no instruction lines"
elif instr "$XQ" '(^|[[:space:]])oc([[:space:]]|$)'; then
  no "ac08: the default binding still execs \`oc\` — a private laptop shim that is not in this repo and not in the image. The derived image installs opencode and its own default cannot run"
elif ! instr "$XQ" 'opencode'; then
  no "ac08: the default binding invokes neither oc nor opencode. Whatever it runs, the image does not declare it"
elif instr "$XQ" '(op[[:space:]]+read|security[[:space:]]+find-generic-password|1[Pp]assword|Keychain)'; then
  no "ac08: the binding acquires a credential itself. That is the operator's — Keychain or 1Password on a laptop, envFrom a Secret in a Job — and a binding that reaches for one works on exactly one machine"
else
  ok "ac08: the default binding execs opencode and takes its provider config from the environment"
fi

# ── ac09: CI proves the image RUNS, not that the Dockerfile looks layered ────────────────────
# The gates above assert text. Text cannot tell a layered Dockerfile from a runnable one — which
# is this gate's own version of "green is not proof". The proof needs Docker, so it lives in CI,
# not here: a loop gate that shells out to `docker build` is neither deterministic nor offline.
if [ ! -f "$WF" ]; then
  no "ac09: no workflow to check for a smoke job"
elif ! grep -qiE '^[[:space:]]*smoke|smoke:' "$WF"; then
  no "ac09: the workflow has no smoke job. Every assertion above reads Dockerfile TEXT, and a Dockerfile that layers correctly and produces an image that cannot run a task look identical from here"
elif ! grep -q 'run-task.sh' "$WF"; then
  no "ac09: the smoke job never invokes run-task.sh, so it proves the image builds and nothing about whether it can execute a task"
else
  ok "ac09: CI runs a fixture task through the built image"
fi

# ── ac10: a node-less image says the codesheet is off ────────────────────────────────────────
# Structural, and it took three attempts to make it discriminate. Worth recording, because the
# first two are the two ways this repo keeps getting checks wrong.
#
#   1. `grep -qE 'else|echo|>&2'` over the eight lines after the guard. It matched
#      `echo "codesheet: injected …"` — the SUCCESS branch — and passed on a tree where no
#      announcement exists. Trap A: the needle was already in the haystack.
#   2. Behavioural: run the loop twice with node off PATH, once against a patched control.
#      Correct, and 41s per gate run — over gate-selftest's 30s bound, so every mutant in this
#      task's corpus came back HUNG. A check the tooling cannot afford to run is a check that
#      stops being run.
#
# So: parse the guard's own if/else/fi block and require the ELSE branch to say something about
# node or the sheet. That is narrow enough to reject an announcement wired anywhere else — which
# is exactly what this task's ac10 mutant does, hanging it on RALPH_SHEET instead of on node.
RB="$ROOT/scripts/ralph-build.sh"
if [ ! -f "$RB" ]; then
  no "ac10: scripts/ralph-build.sh is missing"
else
  _v="$(python3 - "$RB" <<'PYA'
import sys, re
src = open(sys.argv[1]).read().split("\n")
code = [re.sub(r"\s*#.*$", "", l) for l in src]
gi = next((i for i, l in enumerate(code)
           if "RALPH_SHEET" in l and "command -v node" in l and l.rstrip().endswith("then")), None)
if gi is None:
    print("NOGUARD"); raise SystemExit
depth, els, body = 0, None, []
for i in range(gi, len(code)):
    l = code[i].strip()
    if l.startswith("if ") or l == "if":
        depth += 1
    elif l == "fi" or l.startswith("fi "):
        depth -= 1
        if depth == 0:
            break
    elif depth == 1 and (l == "else" or l.startswith("else")):
        els = i
        continue
    if els is not None and depth == 1:
        body.append(l)
if els is None:
    print("NOELSE")
elif re.search(r"(echo|printf).*(node|sheet)", " ".join(body), re.I):
    print("OK")
else:
    print("ELSE-SAYS-NOTHING")
PYA
)"
  case "$_v" in
    OK)       ok "ac10: the codesheet guard's else branch announces that node is missing" ;;
    NOGUARD)  no "ac10: could not find the codesheet's node guard in ralph-build.sh — this check is not measuring what it claims and must be re-anchored before it is trusted" ;;
    NOELSE)   no "ac10: the codesheet guard has no else branch, so an absent node turns the sheet off SILENTLY. The base ships no node, making that the default in any derived image that does not add it — and the only symptom is a token count nobody is comparing" ;;
    *)        no "ac10: the guard has an else branch that says nothing about node or the sheet. An announcement wired to some other condition does not fire in the case that matters" ;;
  esac
fi

gate_done
