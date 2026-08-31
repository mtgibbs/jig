#!/usr/bin/env bash
# T4 — the image is published, and the documented contract points at code that exists.
#
# An image no CI builds is a Dockerfile. A contract naming a variable nothing reads is prose. This
# gate closes both, and asserts the one thing that makes the docs TRUE rather than aspirational:
# that harness-base's ENTRYPOINT actually reaches entrypoint.sh.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"

gate_tmpdir
WF="$ROOT/.github/workflows/build-images.yml"
DOC="$ROOT/docs/executors.md"
BASE="$ROOT/docker/harness-base.Dockerfile"
[ -f "$WF" ] || { no "ac0: .github/workflows/build-images.yml is missing"; gate_done; }

# job — the harness-dispatcher job block, from its key to the next top-level job key.
job() { awk '/^  harness-dispatcher:/{f=1} f&&/^  [a-z-]+:/&&!/^  harness-dispatcher:/{exit} f' "$WF"; }

# ── ac1: CI builds it, from the right file, tagged from the right version ────────────────────
if ! grep -qE '^  harness-dispatcher:' "$WF"; then
  no "ac1: build-images.yml has no harness-dispatcher job. dispatcher.py and api.py stay in no image, and a Dockerfile nothing builds is indistinguishable from no Dockerfile"
elif ! job | grep -q 'docker/dispatcher.Dockerfile'; then
  no "ac1: the harness-dispatcher job does not build docker/dispatcher.Dockerfile"
elif ! job | grep -q 'docker/dispatcher.VERSION'; then
  no "ac1: the harness-dispatcher job does not tag from docker/dispatcher.VERSION — the other three images all do, and an absent version-file tags the image ':'"
elif ! job | grep -q 'ghcr.io/mtgibbs/'; then
  no "ac1: the job does not push to ghcr.io/mtgibbs/"
else
  ok "ac1: CI builds harness-dispatcher from its Dockerfile and VERSION"
fi

# ── ac2: both architectures ──────────────────────────────────────────────────────────────────
# The cluster is arm64. An amd64-only image fails at pull time on the Pi, and the message is about
# a manifest rather than about an architecture.
if ! job | grep -q 'linux/amd64,linux/arm64'; then
  no "ac2: the job does not build linux/amd64,linux/arm64 — the fleet runs on Pi 5s, and an amd64-only image fails at pull with a message about a manifest"
else
  ok "ac2: the image is built for amd64 and arm64"
fi

# ── ac3: how a PRIVATE image is pulled is written down where it bites ────────────────────────
# This assertion originally required the opposite: that the workflow tell the reader to run
# `gh api ... -f visibility=public`. Every image here is private and pulls fine via
# ghcr-pull-secret, so the check was enforcing advice to widen access to every image the repo
# builds. A gate can enshrine a wrong belief as effectively as it can catch a bug — this one did,
# and it went green the whole time.
if grep -q 'visibility=public' "$WF"; then
  no "ac3: the workflow still advises making a package public. These images are private and pull with ghcr-pull-secret; publishing them is a widening of access dressed up as a fix for ImagePullBackOff"
elif ! grep -qi 'ghcr-pull-secret' "$WF"; then
  no "ac3: nothing records HOW a private image gets pulled. An ImagePullBackOff sends the next reader looking for a visibility setting unless the pull secret is named where the image is built"
else
  ok "ac3: the workflow names the pull secret rather than telling anyone to publish the image"
fi

# ── ac4: it does not depend on harness-base ──────────────────────────────────────────────────
if job | grep -qE '^[[:space:]]*needs:.*harness-base'; then
  no "ac4: the dispatcher job needs harness-base, implying a derivation that does not exist — it is FROM python:3.12-slim, and the false dependency serialises CI for nothing"
else
  ok "ac4: the dispatcher job stands alone, as its base image does"
fi

# ── ac5: the docs point at the mechanism ─────────────────────────────────────────────────────
if ! grep -q 'HARNESS_CLONE_PAT' "$DOC"; then
  no "ac5: docs/executors.md does not name HARNESS_CLONE_PAT at all"
elif ! grep -q 'entrypoint.sh' "$DOC"; then
  no "ac5: docs/executors.md never mentions entrypoint.sh. The contract table would still be naming a variable with no code behind it, which is the gap this spec closes"
else
  ok "ac5: docs/executors.md points HARNESS_CLONE_PAT at the script that consumes it"
fi

# ── ac6: and the docs are TRUE — the base actually routes through it ─────────────────────────
if ! grep -qE '^ENTRYPOINT.*entrypoint\.sh' "$BASE"; then
  no "ac6: harness-base's ENTRYPOINT does not reach entrypoint.sh (found: [$(grep -E '^ENTRYPOINT' "$BASE")]). Every word of ac5's documentation is then false: the script exists, ships in the image, and never runs"
elif ! grep -qE '^COPY[[:space:]]+scripts/' "$BASE"; then
  no "ac6: harness-base no longer copies scripts/, so the entrypoint it points at is not in the image"
else
  ok "ac6: harness-base's entrypoint reaches the script the docs describe"
fi

gate_done
