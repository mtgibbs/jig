#!/usr/bin/env bash
# specs/exec-container/verify.sh — the deterministic gate for the containerised binding.
#
# BEHAVIOURAL. There is no docker in this container (spec §5), so the gate puts a MOCK runtime
# first on PATH, runs the binding, and asserts the exact argv it produced. That proves the
# contract without proving the image — and the image's acceptance is a runbook with an owner,
# not a pend nobody here can ever clear (a pend that cannot be cleared would fail the final task
# forever under specs/last-task-strict, and a gate that cannot pass is a broken control).
#
# The mock records each argument into its OWN file, not one line each: the prompt fixture
# contains a newline on purpose, and a line-based capture would silently split it and then
# "prove" byte-for-byte survival against a corrupted sample.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

BIND="$R/scripts/exec-container.sh"
DOCKERFILE="$R/docker/loop-executor.Dockerfile"
STRAT="$R/scripts/loops/build-container.env"
DOC="$R/docs/loop-container.md"
REF="$R/scripts/exec-qwen.sh"

[ -r "$REF" ] || { echo "  FAIL  scope: exec-qwen.sh missing — the contract's reference is gone" >&2; exit 1; }
ok "scope: the binding contract's reference (exec-qwen.sh) is present"

_stray="$(find "$R/specs/exec-container" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence \
          2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$T/x"; chmod +x "$T/x" 2>/dev/null
"$T/x" 2>/dev/null || { echo "  FAIL  ENV: TMPDIR is noexec — re-run with TMPDIR=<exec-able dir>" >&2
                        echo "VERIFY: ENV" >&2; exit 2; }

# The mock runtime. One file per argument, so a newline inside an argument cannot be mistaken
# for an argument boundary.
mkmock() {  # mkmock <name>
  mkdir -p "$T/bin"
  cat > "$T/bin/$1" <<'MOCK'
#!/usr/bin/env bash
d="${MOCK_ARGV_DIR:?}"; rm -rf "$d"; mkdir -p "$d"
n=0; for a in "$@"; do n=$((n + 1)); printf '%s' "$a" > "$d/$n"; done
printf '%s' "$n" > "$d/count"
printf '%s' "$(basename "$0")" > "$d/runtime"
exit 0
MOCK
  chmod +x "$T/bin/$1"
}
mkmock docker; mkmock podman

WT="$T/worktree"; mkdir -p "$WT"
# Starts with -n, carries a backslash, and spans two lines: echo mangles all three.
PROMPT='-n line one\ttab
line two'

run_bind() {  # run_bind [env assignments...] -> ARGV_DIR populated
  MOCK_ARGV_DIR="$T/argv" PATH="$T/bin:$PATH" ROOT="$WT" \
    env "$@" bash "$BIND" "$PROMPT" >/dev/null 2>&1
  ARGC="$(cat "$T/argv/count" 2>/dev/null || echo 0)"
}
argat(){ cat "$T/argv/$1" 2>/dev/null; }
has_arg(){ # has_arg <exact-string>
  local i=1; while [ "$i" -le "${ARGC:-0}" ]; do
    [ "$(argat "$i")" = "$1" ] && return 0; i=$((i + 1)); done; return 1
}
has_pair(){ # has_pair <flag> <value>
  local i=1; while [ "$i" -le "${ARGC:-0}" ]; do
    if [ "$(argat "$i")" = "$1" ]; then
      [ "$(argat $((i + 1)))" = "$2" ] && return 0
    fi; i=$((i + 1)); done; return 1
}

if [ ! -f "$BIND" ]; then
  pend "ac1: exec-container.sh runs the runtime"
  pend "ac2: --rm, the mount, -w, -e ROOT"
  pend "ac3: --user is the invoking uid"
  pend "ac4: the prompt survives byte-for-byte as the last argument"
  pend "ac5: image, network and runtime are overridable"
  pend "ac6: the binding stays thin"
else
  ARGC=0; run_bind
  if [ "${ARGC:-0}" -lt 2 ]; then
    no "ac1: the binding did not invoke the runtime (argc=${ARGC:-0})"
  else
    ok "ac1: the binding invokes the runtime once, with $ARGC arguments"
    [ "$(cat "$T/argv/runtime" 2>/dev/null)" = "docker" ] \
      && ok "ac1: it defaults to docker" || no "ac1: default runtime is '$(cat "$T/argv/runtime" 2>/dev/null)'"

    [ "$(argat 1)" = "run" ] && ok "ac2: the first argument is 'run'" \
                             || no "ac2: the first argument is '$(argat 1)', not 'run'"
    has_arg "--rm" && ok "ac2: --rm — the worker does not leak containers" \
                   || no "ac2: --rm is absent; an ephemeral worker that leaks containers is not ephemeral"
    has_pair "-v" "$WT:$WT" && ok "ac2: the worktree is mounted at the SAME absolute path" \
                            || no "ac2: no '-v $WT:$WT'; a path in the prompt would mean two different things"
    has_pair "-w" "$WT" && ok "ac2: -w puts the executor where the loop is" \
                        || no "ac2: no '-w $WT'"
    has_pair "-e" "ROOT=$WT" && ok "ac2: ROOT is passed through" \
                             || no "ac2: no '-e ROOT=$WT' — the contract's own variable is missing"

    has_pair "--user" "$(id -u):$(id -g)" \
      && ok "ac3: --user is the invoking uid, so the loop can commit what the container writes" \
      || no "ac3: no '--user $(id -u):$(id -g)' — files would land as another uid"

    _last="$(argat "$ARGC")"
    if [ "$_last" = "$PROMPT" ]; then
      ok "ac4: the prompt is the last argument and survived byte-for-byte (leading -n, backslash, newline)"
    else
      no "ac4: the last argument is not the prompt verbatim"
    fi
    case "$_last" in -n*) ok "control: the fixture prompt really does start with -n, which echo would eat" ;;
                     *)   no "control: the fixture lost its leading -n before the assertion ran" ;; esac

    ARGC=0; run_bind LOOP_IMAGE=example.test/img:v9
    has_arg "example.test/img:v9" && ok "ac5: LOOP_IMAGE overrides the image" \
                                  || no "ac5: LOOP_IMAGE did not reach the runtime"
    ARGC=0; run_bind LOOP_NETWORK=nettest
    has_pair "--network" "nettest" && ok "ac5: LOOP_NETWORK overrides the network" \
                                   || no "ac5: LOOP_NETWORK did not reach the runtime"
    ARGC=0; run_bind LOOP_RUNTIME=podman
    [ "$(cat "$T/argv/runtime" 2>/dev/null)" = "podman" ] \
      && ok "ac5: LOOP_RUNTIME selects podman, so the binding is not docker-only" \
      || no "ac5: LOOP_RUNTIME=podman still ran '$(cat "$T/argv/runtime" 2>/dev/null)'"

    # Thinness, per specs/executor-binding §3/§7. Comments stripped so a sentence about a gate
    # is not a gate.
    _body="$(sed 's/#.*//' "$BIND")"
    if printf '%s' "$_body" | grep -qE 'VERIFY|RETRIES|log_(prompt|gate|patch|meta)|while |for .*attempt'; then
      no "ac6: the binding contains loop logic — retry/gate/evidence belong to ralph-build.sh"
    else
      ok "ac6: no retry, gate or evidence logic — the binding stayed thin"
    fi
    [ "$(printf '%s' "$_body" | grep -c '^[[:space:]]*exec ')" = 1 ] \
      && ok "ac6: exactly one exec, same shape as exec-qwen.sh" \
      || no "ac6: expected exactly one 'exec' line"
  fi
fi

# ── T2 · the image ─────────────────────────────────────────────────────────────────────────
if [ ! -f "$DOCKERFILE" ]; then
  pend "ac7: the Dockerfile builds for both architectures"
  pend "ac8: no baked-in USER"
else
  _df="$(sed 's/^[[:space:]]*#.*//' "$DOCKERFILE")"
  printf '%s' "$_df" | grep -q -- '--platform' \
    && no "ac7: --platform is written into the Dockerfile; that pins one architecture at build time" \
    || ok "ac7: no --platform — the architecture is buildx's business, not the Dockerfile's"
  printf '%s' "$_df" | grep -qiE '^FROM .*(amd64|arm64|aarch64|x86_64)' \
    && no "ac7: the base image tag is architecture-qualified" \
    || ok "ac7: the base image tag is architecture-neutral"
  # A DOWNLOAD, not the word "curl". Installing curl as an apt package is architecture-neutral —
  # apt resolves the arch itself — and the first draft of this check failed a correct Dockerfile
  # for containing the string. What needs the guard is a fetch of a specific artifact, so the
  # trigger is a URL in a RUN line.
  if printf '%s' "$_df" | grep -qiE '^[[:space:]]*RUN .*https?://|\.deb|releases/download'; then
    printf '%s' "$_df" | grep -q 'dpkg --print-architecture' \
      && ok "ac7: an architecture-specific download resolves the arch at build time" \
      || no "ac7: it fetches an artifact by URL without resolving the architecture — a literal that breaks on one of the two targets"
  else
    ok "ac7: nothing is fetched by URL, so there is no architecture literal to get wrong"
  fi
  printf '%s' "$_df" | grep -qE '^USER ' \
    && no "ac8: a baked-in USER fights the --user the binding passes at run time" \
    || ok "ac8: no baked-in USER — the invoking uid wins"
  printf '%s' "$_df" | grep -qE '^ENTRYPOINT' \
    && ok "ac8: an ENTRYPOINT exists to receive the prompt" \
    || no "ac8: no ENTRYPOINT — the prompt has nothing to reach"
fi

# ── T3 · the strategy ──────────────────────────────────────────────────────────────────────
if [ ! -f "$STRAT" ]; then
  pend "ac9: the build-container strategy selects this binding"
else
  . "$STRAT" 2>/dev/null
  case "${RALPH_EXEC_CMD:-}" in
    *exec-container.sh) ok "ac9: the strategy points RALPH_EXEC_CMD at exec-container.sh" ;;
    *) no "ac9: RALPH_EXEC_CMD is '${RALPH_EXEC_CMD:-}', not exec-container.sh" ;;
  esac
  [ "${STRATEGY_PHASES:-}" = "build" ] \
    && ok "ac9: one build phase, same as build-converge" \
    || no "ac9: STRATEGY_PHASES is '${STRATEGY_PHASES:-}', expected 'build'"
  [ -n "${STRATEGY_DESC:-}" ] && ok "ac9: the strategy describes itself (run-loop.sh --list)" \
                             || no "ac9: STRATEGY_DESC is empty"
fi

# ── T4 · the runbook for what no gate here can check ───────────────────────────────────────
if [ ! -f "$DOC" ]; then
  pend "ac10: the runbook records the acceptance this repo cannot run"
else
  _n=0
  grep -q 'buildx' "$DOC" && _n=$((_n + 1))
  grep -q 'linux/amd64' "$DOC" && grep -q 'linux/arm64' "$DOC" && _n=$((_n + 1))
  grep -qi 'docker' "$DOC" && grep -qiE 'binding' "$DOC" && _n=$((_n + 1))
  [ "$_n" = 3 ] \
    && ok "ac10: the runbook carries the buildx invocation, both platforms, and the binding-parity acceptance" \
    || no "ac10: the runbook is missing part of the acceptance it exists to carry ($_n/3)"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
