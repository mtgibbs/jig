#!/usr/bin/env bash
# 20260830b — the dispatcher ships as an image, and the worker it launches can clone.
#
# End-state only. The per-task gates under tasks/ hold the detail; this asks the four questions the
# spec's Outcomes ask, each of which spans more than one task.
#
# TIER: STATIC + SCRIPT. There is no docker here, so nothing below proves the image builds, that
# the pinned kubectl runs on arm64, or that kubectl finds the in-cluster ServiceAccount token. Those
# are CI and deploy-time checks, listed in §11 of the spec in the order to run them.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  end-0: no usable workspace (T='${T:-}')" >&2; echo "VERIFY: FAIL"; exit 1
fi

DF="$ROOT/docker/dispatcher.Dockerfile"
EP="$ROOT/scripts/entrypoint.sh"
BASE="$ROOT/docker/harness-base.Dockerfile"

# ── end-1: there is something to deploy ──────────────────────────────────────────────────────
# Outcome 1. pi-cluster has landed a namespace, a quota, RBAC and a ServiceAccount for a dispatcher
# that had no image. This is the assertion that the empty room now has an occupant.
if [ ! -f "$DF" ]; then
  no "end-1: no docker/dispatcher.Dockerfile — dispatcher.py and api.py remain in no image, and pi-cluster's harness-fleet namespace stays empty"
elif ! grep -qE '^  harness-dispatcher:' "$ROOT/.github/workflows/build-images.yml"; then
  no "end-1: the image is never built by CI, so no tag exists for a Deployment to pull"
elif ! grep -q '__main__' "$ROOT/scripts/dispatch/api.py"; then
  no "end-1: api.py has no entry point, so the image would start, define serve(), exit 0, and look healthy"
else
  ok "end-1: a harness-dispatcher image exists, is built by CI, and starts something"
fi

# ── end-2: the worker it launches can clone, and the token stays out of sight ────────────────
# Outcome 2. Behavioural: the real entrypoint, a stub run-task.sh, HOME redirected.
if [ ! -f "$EP" ]; then
  no "end-2: no scripts/entrypoint.sh — a dispatched worker cannot clone a private repo, and fails as an auth error rather than a missing-file one"
else
  mkdir -p "$T/e2/bin" "$T/e2/home"
  cp "$EP" "$T/e2/bin/entrypoint.sh"; chmod +x "$T/e2/bin/entrypoint.sh"
  printf '#!/usr/bin/env bash\necho "RUNTASK argv=[$*]"\n' > "$T/e2/bin/run-task.sh"
  chmod +x "$T/e2/bin/run-task.sh"
  S='SENTINEL-PAT-e2f0'
  o="$( HOME="$T/e2/home" HARNESS_CLONE_PAT="$S" bash "$T/e2/bin/entrypoint.sh" specs/fx --repo proj 2>&1 )"
  if [ ! -s "$T/e2/home/.git-credentials" ]; then
    no "end-2: with a credential supplied, no ~/.git-credentials was written"
  elif ! grep -q "$S" "$T/e2/home/.git-credentials"; then
    no "end-2: the credential file does not contain the credential"
  elif echo "$o" | grep -q "$S"; then
    no "end-2: the credential appeared in the output. The transcript ships to the coordinator, so it leaves the machine"
  elif ! echo "$o" | grep -q 'RUNTASK argv=\[specs/fx --repo proj\]'; then
    no "end-2: the arguments did not reach run-task.sh intact (got [$o])"
  else
    ok "end-2: a worker handed a credential can clone, and the value appears in no output"
  fi
fi

# ── end-3: a run that configures nothing is unchanged ────────────────────────────────────────
# Outcome 3, and the property the whole design is arranged around: the fleet is not a prerequisite
# for using the harness. A laptop and a plain docker run must be byte-identical to before.
if [ -f "$EP" ]; then
  mkdir -p "$T/e3/bin" "$T/e3/home"
  cp "$EP" "$T/e3/bin/entrypoint.sh"; chmod +x "$T/e3/bin/entrypoint.sh"
  printf '#!/usr/bin/env bash\necho "RUNTASK argv=[$*]"\n' > "$T/e3/bin/run-task.sh"
  chmod +x "$T/e3/bin/run-task.sh"
  o="$( HOME="$T/e3/home" env -u HARNESS_CLONE_PAT bash "$T/e3/bin/entrypoint.sh" specs/fx --repo proj 2>&1 )"
  if [ -e "$T/e3/home/.git-credentials" ] || [ -e "$T/e3/home/.gitconfig" ]; then
    no "end-3: an unconfigured run still touched the home directory. Kubernetes concepts must not leak into the laptop path"
  elif [ "$o" != "RUNTASK argv=[specs/fx --repo proj]" ]; then
    no "end-3: an unconfigured run is no longer byte-identical to before. Got [$o]"
  else
    ok "end-3: a run that configures nothing behaves exactly as it did before this spec"
  fi
fi

# ── end-4: a failed launch says which failure it was ─────────────────────────────────────────
# Outcome 4. In a Deployment this message is the whole diagnostic surface.
e4="$( cd "$ROOT/scripts/dispatch" && python3 -c "
import sys, io, contextlib; sys.path.insert(0, '.')
import dispatcher as d
e = io.StringIO()
with contextlib.redirect_stderr(e):
    rc = d.launch({'kind': 'Job'}, runner='/nonexistent/kubectl-xyz')
print('RC=%s ERR=%s' % (rc, e.getvalue().replace(chr(10), ' ')))
" 2>/dev/null )"
case "$e4" in
  RC=0*)                    no "end-4: a launch with no runner reported success — the dispatcher would record a run that was never created" ;;
  *kubectl-xyz*)            ok "end-4: a failed launch names what it could not execute" ;;
  RC=*)                     no "end-4: a failed launch produced no usable message ($e4). 'No kubectl' and 'the API server refused' are different incidents with different fixes" ;;
  *)                        no "end-4: the probe produced nothing readable ($e4)" ;;
esac

gate_done
