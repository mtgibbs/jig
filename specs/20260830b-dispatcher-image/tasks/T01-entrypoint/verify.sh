#!/usr/bin/env bash
# T1 — the entrypoint that gives HARNESS_CLONE_PAT a mechanism.
#
# Behavioural: the entrypoint is COPIED into a sandbox next to a stub run-task.sh and executed
# with HOME redirected, so the gate exercises the real script and touches neither the developer's
# ~/.git-credentials nor their ~/.gitconfig. That redirection is the reason this gate can assert
# on a credential file at all; without it the only safe assertion is a grep of the source, and a
# grep cannot tell "writes the file" from "mentions the filename in a comment".
#
# The sentinel is a fixed literal, never a real token. If it ever appears in output, the leak is
# the finding.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

EP="$ROOT/scripts/entrypoint.sh"
[ -f "$EP" ] || { no "ac0: scripts/entrypoint.sh does not exist — nothing consumes HARNESS_CLONE_PAT yet"; gate_done; }

SENTINEL='SENTINEL-PAT-b2e7'
mode_of() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }

setup() {
  rm -rf "$T/bin" "$T/home"; mkdir -p "$T/bin" "$T/home"
  cp "$EP" "$T/bin/entrypoint.sh"; chmod +x "$T/bin/entrypoint.sh"
  cat > "$T/bin/run-task.sh" <<'STUB'
#!/usr/bin/env bash
echo "RUNTASK-CALLED argv=[$*]"
STUB
  chmod +x "$T/bin/run-task.sh"
}

# with_pat / without_pat — run the entrypoint, capture stdout+stderr together.
with_pat()    { setup; ( HOME="$T/home" HARNESS_CLONE_PAT="$SENTINEL" bash "$T/bin/entrypoint.sh" "$@" ) 2>&1; }
without_pat() { setup; ( HOME="$T/home" unset HARNESS_CLONE_PAT; bash "$T/bin/entrypoint.sh" "$@" ) 2>&1; }

# ── ac1: the credential file is written, and written tight ───────────────────────────────────
out="$(with_pat specs/fx --repo proj)"
CF="$T/home/.git-credentials"
if [ ! -f "$CF" ]; then
  no "ac1: HARNESS_CLONE_PAT was set and no ~/.git-credentials was written. run-task.sh clones a plain https URL and relies on this file existing; without it a private clone fails as an AUTH error inside a Job with no shell attached"
elif ! grep -q "$SENTINEL" "$CF"; then
  no "ac1: ~/.git-credentials exists but does not contain the credential — the helper will answer with nothing, which fails identically to no file at all"
elif [ "$(mode_of "$CF")" != "600" ]; then
  no "ac1: ~/.git-credentials is mode $(mode_of "$CF"), not 600. Set the umask BEFORE the redirect — a chmod after the write leaves a window where the token is world-readable, and the window is not theoretical in an image whose other processes are the model's"
else
  ok "ac1: the credential file is written at mode 600 and carries the credential"
fi

# ── ac2: the helper is actually configured ───────────────────────────────────────────────────
if ! git config --file "$T/home/.gitconfig" --get credential.helper 2>/dev/null | grep -q 'store'; then
  no "ac2: credential.helper=store was not configured. The file alone does nothing — git only reads ~/.git-credentials through the store helper, so writing one without the other is a clone that still fails and a gate that still passes"
else
  ok "ac2: the store credential helper is configured"
fi

# ── ac3: the value never appears in the output ───────────────────────────────────────────────
if echo "$out" | grep -q "$SENTINEL"; then
  no "ac3: the credential appeared in the entrypoint's own output. The container transcript ships to the coordinator, so a token printed here leaves the machine"
else
  ok "ac3: the credential appears nowhere in stdout or stderr"
fi

# ── ac4: the argument contract survives ──────────────────────────────────────────────────────
# THE TRAP: `exec "$@"` plus a CMD makes `docker run <img> specs/fx --repo proj` try to EXECUTE
# specs/fx. Every existing invocation breaks and the error names neither the entrypoint nor CMD.
if ! echo "$out" | grep -q 'RUNTASK-CALLED'; then
  no "ac4: run-task.sh was never reached. If the entrypoint execs \"\$@\" and relies on CMD, the first argument is treated as the program — which is how every documented invocation of this image breaks at once"
elif ! echo "$out" | grep -q 'argv=\[specs/fx --repo proj\]'; then
  no "ac4: the arguments reached run-task.sh altered. Got: [$(echo "$out" | grep RUNTASK-CALLED)] — expected argv=[specs/fx --repo proj]"
else
  ok "ac4: the entrypoint execs run-task.sh beside itself with the arguments unchanged"
fi

# ── ac5: unset is a complete no-op ───────────────────────────────────────────────────────────
out2="$(without_pat specs/fx --repo proj)"
if [ -f "$T/home/.git-credentials" ]; then
  no "ac5: a credential file was written with HARNESS_CLONE_PAT unset. A laptop run and a plain docker run must be byte-identical to today; writing an empty credential turns 'no credential configured' into an auth failure"
elif [ -f "$T/home/.gitconfig" ] && git config --file "$T/home/.gitconfig" --get credential.helper >/dev/null 2>&1; then
  no "ac5: git was reconfigured with HARNESS_CLONE_PAT unset — the unconfigured path must change nothing"
elif ! echo "$out2" | grep -q 'RUNTASK-CALLED'; then
  no "ac5: with no credential the entrypoint did not reach run-task.sh at all. Absent is not an error: most runs of this image will never set the variable"
elif [ -n "$(echo "$out2" | grep -v 'RUNTASK-CALLED')" ]; then
  no "ac5: the unconfigured path emitted output of its own: [$(echo "$out2" | grep -v RUNTASK-CALLED | head -1)]. Silence is the contract"
else
  ok "ac5: with no credential the entrypoint is a complete no-op and still execs run-task.sh"
fi

# ── ac6: the value is never handed to a command as an argument ───────────────────────────────
# Source-level, and deliberately so: argv is readable from /proc for the life of the process, and
# a behavioural check cannot see a child's argv after it has exited.
if grep -nE '^[^#]*\b(git|curl|echo|printf)\b[^|>]*\$\{?HARNESS_CLONE_PAT' "$EP" | grep -qv 'printf.*>' ; then
  no "ac6: the credential is passed to a command as an argument ($(grep -nE '^[^#]*\$\{?HARNESS_CLONE_PAT' "$EP" | head -1)). Redirect it into the file instead; argv is world-readable from /proc"
elif grep -qE '^[[:space:]]*set[[:space:]]+-[a-z]*x' "$EP"; then
  no "ac6: the entrypoint enables trace mode, which prints every expansion of the credential"
else
  ok "ac6: the credential reaches the file by redirection, never through argv, and trace mode is off"
fi

gate_done
