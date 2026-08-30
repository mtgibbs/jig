#!/usr/bin/env bash
# T2 — the credential contract is written down as NAMES, and the identities are separated.
#
# Finds the doc by CONTENT rather than by a filename this gate invented. Absence is a FAIL, never
# a skip: a per-task gate has nothing to defer to.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"

# Scoped to docs/. This spec says every one of these things itself, so a tree-wide grep would be
# satisfied by spec.md — a gate passing on its own spec, which has happened in this repo before.
DOC="$(grep -rl 'HARNESS_WORKER_SECRET' "$ROOT/docs" 2>/dev/null | head -1)"

# A mutation header's WHY: line describes the very absence being checked for, and a bare grep
# matches it. Every read below goes through content().
content() { grep -vE '^[[:space:]]*(#|<!--)[[:space:]]*(MUTANT|TARGET|WHY):' "$1" 2>/dev/null; }
hasc()    { content "$1" | grep -qiE -- "$2"; }
has()     { [ -n "$DOC" ] && hasc "$DOC" "$1"; }

if [ -z "$DOC" ]; then
  no "ac7: no file under docs/ names HARNESS_WORKER_SECRET. Searched: $(ls "$ROOT/docs"/*.md 2>/dev/null | xargs -n1 basename 2>/dev/null | tr '\n' ' ')"
else
  missing=""
  has 'HARNESS_REPORT_URL'   || missing="$missing HARNESS_REPORT_URL"
  has 'HARNESS_REPORT_TOKEN' || missing="$missing HARNESS_REPORT_TOKEN"
  has 'PAT|GITHUB'           || missing="$missing the-git-credential"
  if [ -n "$missing" ]; then
    no "ac7: $(basename "$DOC") does not name the variables a worker expects — missing:$missing. The contract IS the set of names; a reader who cannot see it has to read the dispatcher to configure a worker"
  else
    ok "ac7: the variables a worker expects are named"
  fi
fi

if [ -z "$DOC" ]; then
  no "ac8: no doc to check for the delivery contexts"
elif ! has 'envFrom'; then
  no "ac8: $(basename "$DOC") never mentions envFrom, so the k8s delivery path is undocumented"
elif ! hasc "$DOC" 'docker run|--env-file|env-file'; then
  no "ac8: the local-container path is missing. Three contexts supply the same names three ways, and a reader who sees only the Kubernetes one concludes the fleet is a prerequisite"
elif ! hasc "$DOC" 'no kubernetes|without kubernetes|not rendered|needs no'; then
  no "ac8: it lists the contexts but never says a local run needs NO Kubernetes concept. That is the portability property this design is arranged around, and it has to be stated rather than inferred"
else
  ok "ac8: the three delivery contexts are documented, and a local run needs no Kubernetes concept"
fi

if [ -z "$DOC" ]; then
  no "ac9: no doc to check for the identity separation"
elif ! hasc "$DOC" 'outcome pat'; then
  no "ac9: $(basename "$DOC") does not name the outcome PAT. Cloning and landing are separate identities, and the one that can write is the one worth naming"
elif ! hasc "$DOC" 'never launch|cannot launch|not launch|no compute'; then
  no "ac9: the outcome PAT is named but its BOUND is not. 'A PAT for pushing' without 'and it may never launch compute' leaves the reader free to reuse the dispatch token"
elif ! content "$DOC" | grep -qE '^\|'; then
  no "ac9: the three identities are described in prose but not tabulated. Which identity may do what is exactly the thing a reader scans for"
else
  ok "ac9: the three identities are recorded, with the outcome PAT's bound stated"
fi

gate_done
