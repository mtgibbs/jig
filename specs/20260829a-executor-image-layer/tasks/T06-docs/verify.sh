#!/usr/bin/env bash
# T6 — bringing your own executor is written down, including what this does not provide.
#
# Finds the doc by CONTENT, not by a filename this gate invented: whether the guide is a new
# file or folded into an existing one is the author's call. Absence is a FAIL, never a skip — a
# per-task gate has nothing to defer to.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829a-executor-image-layer/lib/fixtures.sh"

# Scope the search to docs/. The spec itself says every one of these things, so a tree-wide grep
# would be satisfied by specs/20260829a-executor-image-layer/spec.md — a gate passing on its own
# spec is Trap A-prime, and it has happened in this repo before (harness-egress-allowlist, #184).
DOC="$(grep -rl 'harness-base' "$ROOT/docs" 2>/dev/null | head -1)"

# Every read below goes through content()/hasc(), never a bare grep on the file. A mutation
# header's WHY line describes the very absence being checked for, and a bare grep matches it —
# measured on this task's own corpus before the helper existed. See lib/fixtures.sh.
has() { [ -n "$DOC" ] && hasc "$DOC" "$1"; }

if [ -z "$DOC" ]; then
  no "ac1: no file under docs/ mentions harness-base. Searched: $(ls "$ROOT/docs"/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"
elif ! content "$DOC" | grep -qE '^\s*FROM\s+\S*harness-base'; then
  no "ac1: $(basename "$DOC") names harness-base but carries no FROM harness-base example. A worked example is what people actually copy; prose describing one is not"
elif ! has 'exec-' || ! content "$DOC" | grep -qE '\.conf|STRATEGY_PHASES'; then
  no "ac1: the example does not show BOTH halves of the extension point — the exec-*.sh binding and the strategy conf. An image with a CLI and no binding runs nothing"
elif ! hasc "$DOC" 'loop|strateg|binding' || ! content "$DOC" | grep -qE '^\|'; then
  no "ac1: $(basename "$DOC") has no table naming the three layers. Which layer a reader is changing is the one thing that decides whether they need a PR here"
else
  ok "ac1: the three layers and a copy-pasteable FROM harness-base example are documented"
fi

if [ -z "$DOC" ]; then
  no "ac2: no doc to check for the credential boundary"
elif ! hasc "$DOC" 'no credential|ships no|never ships|no secret|no token'; then
  no "ac2: $(basename "$DOC") does not say the harness ships NO credentials. A reader who assumes the base provides auth goes looking for a key that was never there, and the base is public now"
elif ! hasc "$DOC" 'operator|derived image|your own|yours'; then
  no "ac2: it says no credentials ship but not WHOSE job auth is. 'Not here' without 'there' leaves the reader stuck"
else
  ok "ac2: the credential boundary is stated, with an owner"
fi

if [ -z "$DOC" ]; then
  no "ac3: no doc to check for the container contrast"
elif ! has 'exec-container'; then
  no "ac3: $(basename "$DOC") never mentions exec-container.sh. Two different things are called 'container' here — a binding that runs the loop on the HOST and sends prompts into one, and a Job where the loop is already inside one. A reader who conflates them writes docker-in-docker"
elif ! hasc "$DOC" 'host|in-pod|inside the pod|already in'; then
  no "ac3: exec-container.sh is mentioned but not CONTRASTED with the in-pod binding. Naming both is not the same as saying how they differ"
else
  ok "ac3: exec-container.sh and the in-pod binding are explicitly contrasted"
fi

if [ -z "$DOC" ]; then
  no "ac4: no doc to check for the boundary"
else
  missing=""
  hasc "$DOC" 'job (body|spec)|no job|kubernetes job' || missing="$missing job-body"
  hasc "$DOC" 'egress|push|pull request|pr'           || missing="$missing code-egress"
  hasc "$DOC" 'credential provision|provisioning'     || missing="$missing cred-provisioning"
  if [ -n "$missing" ]; then
    no "ac4: $(basename "$DOC") does not record what this deliberately does NOT provide — missing:$missing. A reader who thinks the image is a working fleet worker discovers otherwise in a pod that is already being deleted"
  else
    ok "ac4: the boundary — no Job body, no code egress, no credential provisioning — is recorded"
  fi
fi

RM="$ROOT/scripts/loops/README.md"
if [ ! -f "$RM" ]; then
  no "ac5: scripts/loops/README.md is missing"
elif ! content "$RM" | grep -q 'STRATEGY_TOOLS'; then
  no "ac5: loops/README.md does not document STRATEGY_TOOLS, so the contract a strategy author reads is out of date with the one run-loop.sh enforces"
elif ! content "$RM" | grep -qE '\.harness'; then
  no "ac5: loops/README.md does not document the consumer search path. A strategy author reading only this file cannot learn that a repo may ship its own"
else
  ok "ac5: the conf contract documents STRATEGY_TOOLS and both search paths"
fi

gate_done
