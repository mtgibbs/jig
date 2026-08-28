#!/usr/bin/env bash
# specs/20260828d-image-ci/verify.sh — the deterministic gate for "the images this repo defines
# are actually published".
#
# STRUCTURAL, and honest about it. A gate here cannot prove the workflow RUNS — that needs GitHub
# Actions, which happens only after merge (spec §5). What it can prove is that the workflow is
# well-formed and correct in its references, which is every failure mode reachable without a
# runner: invalid YAML, a Dockerfile path that does not exist, a missing platform, a mutable tag,
# an over-broad permission, a version file that is empty.
#
# The assertions read the PARSED yaml, not the text. A grep for "linux/arm64" passes on a comment.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

WF="$R/.github/workflows/build-images.yml"
VF="$R/docker/loop-executor.VERSION"
DOC="$R/docs/loop-container.md"

python3 -c "import yaml" 2>/dev/null || { echo "  FAIL  ENV: pyyaml unavailable; this gate parses YAML" >&2
                                          echo "VERIFY: ENV" >&2; exit 2; }
ok "scope: pyyaml is available to parse the workflow"

_stray="$(find "$R/specs/20260828d-image-ci" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence \
          2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

# ── T1 · the version file ──────────────────────────────────────────────────────────────────
if [ ! -f "$VF" ]; then
  pend "ac1: docker/loop-executor.VERSION exists"
else
  v="$(tr -d ' \t\r\n' < "$VF")"
  case "$v" in
    v*)            no "ac1: version is '$v' — no 'v' prefix; review-hub's VERSION is a bare semver and an ImagePolicy reads both" ;;
    *.*.*)         ok "ac1: version file holds a bare semver ($v)" ;;
    "")            no "ac1: version file is empty — the tag would be 'ghcr.io/mtgibbs/loop-executor:'" ;;
    *)             no "ac1: version is '$v', not a bare semver" ;;
  esac
  [ "$(grep -c . "$VF")" = 1 ] && ok "ac1: it is exactly one line" \
                               || no "ac1: version file has $(grep -c . "$VF") non-empty lines, expected 1"
fi

# ── T2 · the workflow, read as parsed YAML ─────────────────────────────────────────────────
if [ ! -f "$WF" ]; then
  pend "ac2: the workflow is valid YAML"
  pend "ac3: it builds both platforms and pushes to GHCR"
  pend "ac4: permissions are least-privilege"
  pend "ac5: the image set is a matrix"
  pend "ac6: it is path-filtered"
  pend "ac7: every referenced Dockerfile exists"
else
  REPORT="$(python3 - "$WF" "$R" <<'PY' 2>&1
import sys, yaml, os
wf, root = sys.argv[1], sys.argv[2]
try:
    d = yaml.safe_load(open(wf))
except Exception as e:
    print("PARSE_FAIL", e); sys.exit(0)
print("PARSE_OK")

# `on:` is parsed by YAML 1.1 as the boolean True — a classic trap when reading workflows
# programmatically. Accept either key.
on = d.get("on", d.get(True)) or {}
push = (on.get("push") or {}) if isinstance(on, dict) else {}
paths = push.get("paths") or []
print("PATHS", "|".join(paths))
print("BRANCHES", "|".join(push.get("branches") or []))

perms = d.get("permissions") or {}
print("PERMS", ";".join(f"{k}={v}" for k, v in sorted(perms.items())))

jobs = d.get("jobs") or {}
for jn, j in jobs.items():
    mat = ((j.get("strategy") or {}).get("matrix") or {})
    # a matrix is either `include:` or a bare list-valued key
    entries = mat.get("include") or []
    if not entries:
        for k, v in mat.items():
            if isinstance(v, list):
                entries = [{k: x} for x in v]
                break
    print("MATRIX_ENTRIES", len(entries))
    for e in entries:
        for val in e.values():
            if isinstance(val, str) and val.endswith("Dockerfile") or (isinstance(val,str) and "Dockerfile" in val):
                print("DOCKERFILE", val, "EXISTS" if os.path.isfile(os.path.join(root, val)) else "MISSING")
    for s in (j.get("steps") or []):
        u = s.get("uses") or ""
        if u: print("USES", u.split("@")[0])
        w = s.get("with") or {}
        for key in ("platforms", "tags", "push", "registry", "file"):
            if key in w: print("WITH", key, str(w[key]).replace("\n", " "))
PY
)"
  get(){ printf '%s\n' "$REPORT" | grep "^$1" | head -1; }

  if printf '%s' "$REPORT" | grep -q "^PARSE_OK"; then
    ok "ac2: the workflow is valid YAML"
  else
    no "ac2: the workflow does not parse — $(get PARSE_FAIL)"
  fi

  _plat="$(printf '%s\n' "$REPORT" | grep '^WITH platforms' | head -1)"
  case "$_plat" in
    *linux/amd64*linux/arm64*|*linux/arm64*linux/amd64*) ok "ac3: builds linux/amd64 AND linux/arm64 — the workers are Pis" ;;
    "") pend "ac3: no platforms declared on the build step" ;;
    *)  no "ac3: platforms is '${_plat#WITH platforms }' — both architectures are required" ;;
  esac

  printf '%s\n' "$REPORT" | grep -q '^WITH push True' \
    && ok "ac3: push is enabled" || no "ac3: the build step does not push"
  printf '%s\n' "$REPORT" | grep -q '^WITH tags.*ghcr\.io/mtgibbs/loop-executor' \
    && ok "ac3: tags target ghcr.io/mtgibbs/loop-executor" \
    || no "ac3: tags do not target ghcr.io/mtgibbs/loop-executor — $(get 'WITH tags')"
  if printf '%s\n' "$REPORT" | grep -qE '^WITH tags.*:latest'; then
    no "ac3: tags include :latest — a mutable tag gives Flux nothing to compare (spec §4)"
  else
    ok "ac3: no mutable :latest tag"
  fi

  _perms="$(get PERMS)"
  case "$_perms" in
    *packages=write*) ok "ac4: packages: write is granted" ;;
    *) no "ac4: packages: write is missing — GHCR push needs it ($_perms)" ;;
  esac
  case "$_perms" in
    *contents=write*|*"=write-all"*) no "ac4: over-broad permissions ($_perms) — contents should be read" ;;
    *contents=read*) ok "ac4: contents is read-only — least privilege" ;;
    *) no "ac4: contents permission not declared ($_perms)" ;;
  esac

  _n="$(get MATRIX_ENTRIES | awk '{print $2}')"
  [ "${_n:-0}" -ge 1 ] && ok "ac5: the image set is a matrix ($_n entry) — a second image is one row" \
                       || pend "ac5: no matrix; adding an image would mean a second workflow"

  _pf="$(get PATHS)"
  case "$_pf" in
    *docker/*) ok "ac6: path-filtered on docker/ — an unrelated commit does not rebuild" ;;
    "") pend "ac6: no paths filter — every push to main would rebuild" ;;
    *) no "ac6: paths filter does not cover docker/ — '$_pf'" ;;
  esac
  case "$_pf" in
    *build-images.yml*) ok "ac6: the filter includes the workflow itself, so editing it rebuilds" ;;
    *) no "ac6: the filter omits the workflow's own path — a fix to it would not take effect" ;;
  esac

  _df="$(printf '%s\n' "$REPORT" | grep '^DOCKERFILE' | head -3)"
  if [ -z "$_df" ]; then
    pend "ac7: no Dockerfile referenced from the matrix"
  elif printf '%s' "$_df" | grep -q MISSING; then
    no "ac7: the workflow references a Dockerfile that does not exist — $_df"
  else
    ok "ac7: every referenced Dockerfile exists on disk"
  fi

  # ac10 — the tag must be DERIVED from the matrix, not hardcoded. ac3 above only checks the tag
  # points at loop-executor, which is equally true of a hardcoded string; a second matrix row
  # would then push to the FIRST image's name and silently defeat outcome 4. Measured: the first
  # implementation did exactly this and ac3 passed it.
  _tags="$(printf '%s\n' "$REPORT" | grep '^WITH tags' | head -1)"
  case "$_tags" in
    *'matrix.image'*) ok "ac10: the tag is derived from matrix.image — a second row publishes its own name" ;;
    "")               pend "ac10: the tag is derived from the matrix" ;;
    *)                no "ac10: the image name is hardcoded in tags — a second matrix row would push to the first image's name" ;;
  esac

  for a in checkout setup-qemu-action setup-buildx-action login-action build-push-action; do
    printf '%s\n' "$REPORT" | grep -q "^USES .*$a" \
      || no "ac8: the workflow never uses $a — qemu in particular is what makes arm64 buildable on an amd64 runner"
  done
  printf '%s\n' "$REPORT" | grep -q "^USES .*setup-qemu-action" \
    && ok "ac8: qemu, buildx, login and build-push are all present"
fi

# ── T3 · the docs tell the truth about how the image is built ──────────────────────────────
if [ ! -r "$DOC" ]; then
  no "ac9: docs/loop-container.md is missing"
elif grep -q "build-images.yml" "$DOC" 2>/dev/null; then
  grep -q "buildx" "$DOC" \
    && ok "ac9: the doc names CI as the path and KEEPS the manual command as the fallback" \
    || no "ac9: the manual buildx command was deleted — it is the only way to verify a change locally"
else
  pend "ac9: docs/loop-container.md still presents the manual build as the procedure"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
