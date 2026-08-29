#!/usr/bin/env bash
# T1 — the loop ships in a base image with no model CLI, and the executor image is a thin layer.
#
# Docker-free by design. CI builds two architectures; a gate that shells out to `docker build` is
# neither deterministic nor offline, which is the same reason docs/loop-container.md exists as a
# runbook rather than as criteria. Every assertion here reads the INSTRUCTION lines of a
# Dockerfile or the structure of the workflow — never a comment, never prose.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829a-executor-image-layer/lib/fixtures.sh"

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
  no "ac1: docker/harness-base.Dockerfile does not exist — the base image is the whole seam"
elif ! nonempty_strip "$BASE"; then
  no "ac1: harness-base.Dockerfile has no instruction lines at all (only comments?) — every content check below would pass for free"
else
  missing=""
  instr "$BASE" 'COPY[[:space:]].*scripts'    || missing="$missing scripts/"
  instr "$BASE" 'COPY[[:space:]].*specs/lib'  || missing="$missing specs/lib/"
  if [ -n "$missing" ]; then
    no "ac1: harness-base.Dockerfile has no COPY instruction bringing in:$missing. A base image without the loop is the current loop-executor with a new name"
  else
    ok "ac1: the base COPYs the loop and the assertion vocabulary"
  fi
fi

# ── ac2: the base carries NO model CLI ───────────────────────────────────────────────────────
# An ABSENCE assertion, so it is worthless without the nonempty_strip guard above and without a
# mutant that plants an install. Scoped to instruction lines: the file's own header comment will
# say the words "opencode" and "claude" while explaining why they are not here.
if [ ! -f "$BASE" ]; then
  no "ac2: no harness-base.Dockerfile to check for a CLI"
elif ! nonempty_strip "$BASE"; then
  no "ac2: harness-base.Dockerfile has no instruction lines — the absence check cannot mean anything"
else
  planted=""
  for cli in opencode codex claude gemini; do
    instr "$BASE" "(npm[[:space:]]+install|pip[[:space:]]+install|pipx|curl.*install).*$cli" \
      && planted="$planted $cli"
  done
  if [ -n "$planted" ]; then
    no "ac2: harness-base.Dockerfile installs a model CLI:$planted. The base having no CLI is what lets someone else write FROM harness-base — an opinionated base is the fork it replaces"
  else
    ok "ac2: the base installs no model CLI"
  fi
fi

# ── ac3: the derived image is thin ───────────────────────────────────────────────────────────
if [ ! -f "$DERIVED" ]; then
  no "ac3: docker/loop-executor-opencode.Dockerfile is missing. After the split the BASE is what executes loops, so the generic name belongs to it; loop-executor-codex and loop-executor-claude are the point and they cannot all be 'loop-executor'"
elif [ -f "$OLD_DERIVED" ]; then
  no "ac3: both docker/loop-executor.Dockerfile and the renamed loop-executor-opencode.Dockerfile exist. A rename that leaves the old file behind is a copy, and CI will build whichever the matrix still names"
elif ! nonempty_strip "$DERIVED"; then
  no "ac3: loop-executor.Dockerfile has no instruction lines"
elif ! instr "$DERIVED" '^FROM[[:space:]]+.*harness-base'; then
  no "ac3: loop-executor.Dockerfile does not begin FROM the base — it is still a standalone image, which is the shape this task exists to remove. FROM line: $(strip_comments "$DERIVED" | grep -i '^FROM' | head -1)"
elif instr "$DERIVED" 'apt-get[[:space:]]+install'; then
  no "ac3: loop-executor.Dockerfile still apt-get installs. Those packages belong in the base; installing them twice means the next executor image re-solves them a third time"
elif instr "$DERIVED" 'COPY[[:space:]].*(scripts|specs/lib)'; then
  no "ac3: loop-executor.Dockerfile copies the harness itself. It inherits it from the base; a second copy is the drift this whole spec is about"
else
  ok "ac3: the derived image is FROM the base and adds only its CLI"
fi

# ── ac4: PATH and ENTRYPOINT ─────────────────────────────────────────────────────────────────
if [ ! -f "$BASE" ]; then
  no "ac4: no harness-base.Dockerfile to check for PATH/ENTRYPOINT"
else
  if ! instr "$BASE" 'ENV[[:space:]].*PATH.*scripts' && ! instr "$BASE" 'ENV[[:space:]]+PATH'; then
    no "ac4: harness-base.Dockerfile never puts the harness scripts on PATH, so run-task.sh and run-loop.sh are only reachable by absolute path"
  elif ! instr "$BASE" 'ENTRYPOINT.*run-task\.sh'; then
    no "ac4: the base ENTRYPOINT is not run-task.sh. Found: $(strip_comments "$BASE" | grep -i '^ENTRYPOINT' | head -1). The entrypoint IS the contract a derived image inherits"
  elif ! instr "$BASE" 'ENTRYPOINT.*tini'; then
    no "ac4: the ENTRYPOINT does not wrap tini. The current loop-executor wraps opencode in tini for signal handling and zombie reaping; a Job that cannot be terminated cleanly is worse in a pod than on a laptop"
  else
    ok "ac4: PATH carries the harness scripts and ENTRYPOINT is run-task.sh under tini"
  fi
fi

# ── ac5: CI builds the base first, and says so ───────────────────────────────────────────────
# Structural, not textual: `needs:` is the assertion, because a third matrix row that merely
# NAMES harness-base would satisfy any grep for the string while still racing.
if [ ! -f "$WF" ]; then
  no "ac5: .github/workflows/build-images.yml is missing"
elif ! grep -q 'harness-base' "$WF"; then
  no "ac5: the workflow never builds harness-base, so the base image only ever exists on someone's laptop"
elif [ ! -f "$BV" ]; then
  no "ac5: docker/harness-base.VERSION does not exist — the workflow reads the tag from a version file and would tag the image ':'"
elif ! grep -qE '^[[:space:]]*needs:' "$WF"; then
  no "ac5: the workflow declares no needs: edge. A matrix runs its entries in PARALLEL, so a base row and a derived row race and the derived build pulls a tag still being built — intermittently, only when both change in one push, which is the worst kind to leave implicit"
else
  ok "ac5: harness-base is built from its VERSION file, ahead of the derived image via needs:"
fi

# ── ac6: the container binding points at a tag that exists ───────────────────────────────────
# The one live defect this task fixes: CI has only ever pushed the VERSION tag, so
# ghcr.io/mtgibbs/loop-executor:latest has never existed, and exec-container.sh defaults to it.
if [ ! -f "$EC" ]; then
  no "ac6: scripts/exec-container.sh is missing"
elif instr "$EC" 'LOOP_IMAGE:-[^"}]*:latest'; then
  no "ac6: exec-container.sh still defaults LOOP_IMAGE to a :latest tag that CI has never pushed. The default of the containerised binding must be an image that exists"
elif instr "$EC" 'LOOP_IMAGE:-[^"}]*/loop-executor:'; then
  no "ac6: exec-container.sh still defaults to the OLD image name. The tag may be real and the repository is not the one CI now publishes — an image that exists and an image CI publishes are two different things"
elif ! instr "$EC" 'LOOP_IMAGE'; then
  no "ac6: exec-container.sh no longer honours LOOP_IMAGE at all — the override is the seam, do not remove it while fixing the default"
else
  ok "ac6: exec-container.sh defaults to a tag CI publishes"
fi

gate_done
