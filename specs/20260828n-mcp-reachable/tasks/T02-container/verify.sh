#!/usr/bin/env bash
# T02 — the container is handed the credential by name, and is handed nothing when there is nothing.
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'rm -rf "$T"' EXIT
. "$ROOT/specs/20260828n-mcp-reachable/lib/fixtures.sh"

EXEC="$ROOT/scripts/exec-container.sh"
[ -f "$EXEC" ] || { no "ac9: scripts/exec-container.sh does not exist"; gate_done; }

# The binding builds a `docker run` invocation. There is no docker in this container, so the gate
# substitutes a recorder on PATH: exec-container.sh's argv IS the contract under test, and running
# it for real would only add a dependency that cannot be satisfied where the loop lives.
mkdir -p "$T/bin"
cat > "$T/bin/docker" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$DOCKER_ARGV_OUT"
exit 0
SH
chmod +x "$T/bin/docker"

run_binding() {
  DOCKER_ARGV_OUT="$T/argv.txt" PATH="$T/bin:$PATH" ROOT="$T/work" \
    gate_timeout 60 bash "$EXEC" "probe prompt" >"$T/binding.out" 2>&1
  BRC=$?
}
mkdir -p "$T/work"

# ac9a — set in the loop, present in the container, and passed BY NAME. `-e NAME` takes the value
# from the daemon's caller; `-e NAME=value` bakes the secret into an argv that `ps` can read.
MCP_HOMELAB_API_KEY="container-fixture-key-7b31" run_binding
if [ ! -s "$T/argv.txt" ]; then
  no "ac9a: the binding produced no docker invocation (exit $BRC): $(head -3 "$T/binding.out" | tr '\n' ' ')"
elif ! grep -qx 'MCP_HOMELAB_API_KEY' "$T/argv.txt"; then
  no "ac9a: MCP_HOMELAB_API_KEY is not passed into the container. -e args were: $(grep -A1 -x -- '-e' "$T/argv.txt" | grep -v -- '-e\|--' | tr '\n' ' ')"
elif grep -q 'MCP_HOMELAB_API_KEY=' "$T/argv.txt"; then
  no "ac9a: the key is passed as -e NAME=value, so its value is visible in the process table — pass it by name"
else
  ok "ac9a: MCP_HOMELAB_API_KEY reaches the container, passed by name"
fi

# ac9b — the value must never be an argument, whatever the spelling.
if grep -qF 'container-fixture-key-7b31' "$T/argv.txt" 2>/dev/null || grep -qF 'container-fixture-key-7b31' "$T/binding.out" 2>/dev/null; then
  no "ac9b: the credential's value appeared in the docker argv or the binding's output"
else
  ok "ac9b: the credential's value never appears in argv or output"
fi

# ac9c — unset in the loop means UNSET in the container, never the empty string. An empty key is
# not a missing key: it produces a 401, then an OAuth fallback, then an HTML 404 that reads as
# "the server is down". That is the whole reason this spec exists, so it must not be manufactured
# by the binding itself.
( unset MCP_HOMELAB_API_KEY; DOCKER_ARGV_OUT="$T/argv2.txt" PATH="$T/bin:$PATH" ROOT="$T/work" \
    gate_timeout 60 bash "$EXEC" "probe prompt" >"$T/binding2.out" 2>&1 )
if [ ! -s "$T/argv2.txt" ]; then
  no "ac9c: the binding produced no docker invocation with the variable unset: $(head -3 "$T/binding2.out" | tr '\n' ' ')"
elif grep -qx 'MCP_HOMELAB_API_KEY' "$T/argv2.txt" || grep -q 'MCP_HOMELAB_API_KEY=' "$T/argv2.txt"; then
  no "ac9c: the variable is unset in the loop but was still handed to the container — an empty credential is worse than an absent one"
else
  ok "ac9c: unset in the loop is unset in the container, not empty"
fi

# ac9d — one name. A synonym anywhere is the first of the three faults this spec records.
if grep -rn 'MCP_HOMELAB_KEY\b' "$ROOT/scripts" "$ROOT/docker" 2>/dev/null | grep -v 'MCP_HOMELAB_API_KEY' | grep -q .; then
  no "ac9d: the synonym MCP_HOMELAB_KEY appears under scripts/ or docker/ — two names for one secret is the fault being fixed: $(grep -rn 'MCP_HOMELAB_KEY\b' "$ROOT/scripts" "$ROOT/docker" 2>/dev/null | grep -v 'MCP_HOMELAB_API_KEY' | head -2 | tr '\n' ' ')"
else
  ok "ac9d: only MCP_HOMELAB_API_KEY is used; no synonym"
fi

gate_done
