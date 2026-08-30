#!/usr/bin/env bash
# T3 — the dispatcher image.
#
# TEXT-TIER, and the limit is stated rather than papered over: there is no docker in the container
# these gates run in, so nothing here proves the image builds, that the pinned kubectl runs on
# arm64, or that it finds the in-cluster ServiceAccount token. Those are CI and deploy-time checks
# (see the spec's §11). What text CAN prove is every property whose absence is silent: a baked
# credential, a root user, a ledger that a restart forgets, an unverified download.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"

gate_tmpdir
DF="$ROOT/docker/dispatcher.Dockerfile"
VF="$ROOT/docker/dispatcher.VERSION"
[ -f "$DF" ] || { no "ac0: docker/dispatcher.Dockerfile does not exist — dispatcher.py and api.py are still in no image"; gate_done; }

# body — the Dockerfile with comment lines stripped, so a property mentioned in prose is never
# mistaken for a property declared in an instruction.
body() { grep -vE '^[[:space:]]*#' "$DF"; }

# ── ac1: it carries the two modules ──────────────────────────────────────────────────────────
if ! body | grep -qE '^COPY[[:space:]]+scripts/dispatch/dispatcher\.py' ; then
  no "ac1: dispatcher.py is not COPY'd into the image"
elif ! body | grep -qE '^COPY[[:space:]]+scripts/dispatch/api\.py' ; then
  no "ac1: api.py is not COPY'd into the image"
else
  ok "ac1: the image carries dispatcher.py and api.py"
fi

# ── ac2: kubectl is pinned AND verified ──────────────────────────────────────────────────────
if ! body | grep -q 'kubectl'; then
  no "ac2: no kubectl is installed. launch() shells out to it; without it every dispatch fails at the one call the image exists to make"
elif ! body | grep -qE 'KUBECTL_VERSION=v?[0-9]+\.[0-9]+\.[0-9]+'; then
  no "ac2: kubectl is not pinned to a literal version — 'latest' in the component that creates compute is a different image every rebuild"
elif ! body | grep -qE 'sha256sum[[:space:]]+-c|sha256sum[[:space:]]+--check'; then
  no "ac2: the kubectl download is not checksum-verified. An unverified curl-and-install in the one component whose job is to create Kubernetes objects passes a smoke test on the day you write it"
elif [ "$(body | grep -coE '\b[0-9a-f]{64}\b')" -lt 2 ]; then
  no "ac2: fewer than two SHA256 literals present, but CI builds linux/amd64 AND linux/arm64 — one checksum cannot verify both, and the arch that is not covered is the Pi"
else
  ok "ac2: kubectl is pinned by version and verified by checksum, per architecture"
fi

# ── ac3: no credential is declared ───────────────────────────────────────────────────────────
bad="$(body | grep -E '^(ENV|ARG)[[:space:]]' | grep -iE '(TOKEN|SECRET|PAT|KEY)[[:space:]]*=' || true)"
if [ -n "$bad" ]; then
  no "ac3: the image declares a credential-shaped variable: [$(echo "$bad" | head -1)]. api.py exits 1 when HARNESS_API_TOKEN is unset — a default here converts that refusal into a dispatcher taking unauthenticated requests to create compute"
else
  ok "ac3: the image declares no token, secret, PAT or key"
fi

# ── ac4: non-root ────────────────────────────────────────────────────────────────────────────
if ! body | grep -qE '^USER[[:space:]]+10001'; then
  no "ac4: the image does not run as uid 10001 (found: [$(body | grep -E '^USER' | tail -1)]). The coordinator runs non-root; the component that can create Jobs has less reason to be root, not more"
else
  ok "ac4: the image runs as non-root uid 10001"
fi

# ── ac5: dedupe state survives a restart ─────────────────────────────────────────────────────
vol="$(body | grep -E '^VOLUME' | tr -d '[]", ' | sed 's/^VOLUME//')"
led="$(body | grep -oE 'HARNESS_LEDGER_PATH=[^ ]*' | head -1 | cut -d= -f2)"
reg="$(body | grep -oE 'HARNESS_REGISTRY_PATH=[^ ]*' | head -1 | cut -d= -f2)"
if [ -z "$vol" ]; then
  no "ac5: no VOLUME is declared. already_seen()/record_seen() are what stop a redelivered webhook launching a second Job for work already running — state in the image layer is state a restart forgets, and the symptom is duplicate runs, not an error"
elif [ -z "$led" ] || [ -z "$reg" ]; then
  no "ac5: HARNESS_LEDGER_PATH and HARNESS_REGISTRY_PATH are not both defaulted (ledger=[$led] registry=[$reg]) — api.py reads both from the environment and treats empty as 'no ledger'"
elif [ "${led#$vol}" = "$led" ] || [ "${reg#$vol}" = "$reg" ]; then
  no "ac5: the ledger/registry defaults are not under the declared VOLUME $vol (ledger=[$led] registry=[$reg]) — a mount at $vol would leave the real state in the container layer"
else
  ok "ac5: the ledger and registry default under the declared VOLUME, so dedupe survives a restart"
fi

# ── ac6: it does not derive from harness-base ────────────────────────────────────────────────
if body | grep -qiE '^FROM[[:space:]]+.*harness-base'; then
  no "ac6: the dispatcher derives FROM harness-base, which bakes the loop, the harness scripts and a node runtime into the one component permitted to create compute"
else
  ok "ac6: the dispatcher does not derive from harness-base"
fi

# ── ac7: the entrypoint actually starts something ────────────────────────────────────────────
# api.py defined serve() and had no __main__: `python3 api.py` exited 0 having done nothing. In an
# image that is the worst shape available — a container that starts, serves nothing, looks healthy.
API="$ROOT/scripts/dispatch/api.py"
ep="$(body | grep -E '^(ENTRYPOINT|CMD)' | head -1)"
if [ -z "$ep" ]; then
  no "ac7: the image declares no ENTRYPOINT or CMD"
elif ! grep -q '__main__' "$API"; then
  no "ac7: api.py still has no __main__ block, so running it defines serve() and exits 0 — a container that starts, does nothing, and reports healthy"
elif ! grep -A4 '__main__' "$API" | grep -q 'serve('; then
  no "ac7: api.py's __main__ block does not call serve()"
else
  ok "ac7: the entrypoint reaches an api.py that actually serves"
fi

# ── ac8: the version file CI reads ───────────────────────────────────────────────────────────
if [ ! -f "$VF" ]; then
  no "ac8: docker/dispatcher.VERSION is missing — the CI job tags from it, and an absent file tags the image ':'"
elif ! grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' "$VF"; then
  no "ac8: docker/dispatcher.VERSION is not a bare semver (got [$(head -1 "$VF")]) — the other three VERSION files are, and the tag is taken verbatim"
else
  ok "ac8: docker/dispatcher.VERSION carries a bare semver"
fi

gate_done
