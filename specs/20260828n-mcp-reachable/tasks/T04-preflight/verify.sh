#!/usr/bin/env bash
# T04 — the preflight asks the server, and a spec that declares nothing is untouched.
#
# LAST TASK. It edits scripts/run-loop.sh, which is the script bash is streaming by byte offset,
# so a nonzero exit immediately after this task is expected rather than a failure — re-invoke the
# loop, never resume it (specs/20260825a-evidence-convention §6b).
set -u
ROOT="$(git rev-parse --show-toplevel)"
. "$ROOT/specs/lib/assert.sh"
gate_tmpdir
trap 'fixture_stop 2>/dev/null; rm -rf "$T"' EXIT
. "$ROOT/specs/20260828n-mcp-reachable/lib/fixtures.sh"

SECRET="preflight-fixture-key-9d40"

# mkspec <dir> <mcp-line-or-empty> — a two-line spec whose only interesting property is its header.
mkspec() {
  mkdir -p "$1"
  { echo "# Spec: fixture"; echo; echo "Tools: bash"
    [ -n "${2:-}" ] && echo "$2"
    echo "Permissions: read"; echo; echo "## 1. Why"; echo "fixture"; } > "$1/spec.md"
  echo "T1: do nothing." > "$1/tasks.txt"
  printf '#!/usr/bin/env bash\necho "  PASS  fixture"\necho "---"\necho "VERIFY: PASS"\n' > "$1/verify.sh"
  chmod +x "$1/verify.sh"
}

# runpre <specdir> [env...] — run run-loop.sh far enough to reach the preflight. RALPH_EXEC_CMD
# names a binding that does not exist, so the run cannot proceed past preflight into real work;
# what is under test is the preflight's verdict and its exit code, not a whole loop.
runpre() {
  local sd="$1"; shift
  PRE_OUT="$( cd "$T" && env "$@" RALPH_EXEC_CMD="$T/exec-qwen.sh" MAX_ROUNDS=1 \
      gate_timeout 90 bash "$ROOT/scripts/run-loop.sh" build-converge "$sd" 2>&1 )"
  PRE_RC=$?
}
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/exec-qwen.sh"; chmod +x "$T/exec-qwen.sh"

# ac8 — THE portability assertion, and the one most easily broken by a helpful addition. Asserted
# against a CONTROL: the same fixture through origin/main's run-loop.sh, diffed with per-run values
# stripped. Grepping for phrases I imagined would miss a probe that announced itself differently.
mkspec "$T/nomcp" "MCP: none"
runpre "$T/nomcp"; NOMCP_RC=$PRE_RC; printf '%s\n' "$PRE_OUT" > "$T/nomcp.out"
mkdir -p "$T/ctl"
git -C "$ROOT" show origin/main:scripts/run-loop.sh > "$T/ctl/run-loop.sh" 2>/dev/null
if [ ! -s "$T/ctl/run-loop.sh" ]; then
  no "ac8: could not fetch origin/main's run-loop.sh for the control — the comparison did not run"
else
  CTL_OUT="$( cd "$T" && env RALPH_EXEC_CMD="$T/exec-qwen.sh" MAX_ROUNDS=1 \
      gate_timeout 90 bash "$T/ctl/run-loop.sh" build-converge "$T/nomcp" 2>&1 )"; CTL_RC=$?
  printf '%s\n' "$CTL_OUT" > "$T/ctl.out"
  norm() { sed -e 's/\b[0-9a-f]\{4,\}\b//g' -e 's/[0-9]\+//g' -e 's#/tmp/[^ ]*##g' -e "s#$T##g" "$1" | grep -av '^$'; }
  if [ "$NOMCP_RC" != "$CTL_RC" ]; then
    no "ac8: an MCP:none spec exits $NOMCP_RC where main exits $CTL_RC — declaring none must change nothing"
  elif ! diff -q <(norm "$T/nomcp.out") <(norm "$T/ctl.out") >/dev/null 2>&1; then
    no "ac8: an MCP:none run differs from the same run on main: $(diff <(norm "$T/nomcp.out") <(norm "$T/ctl.out") | head -4 | tr '\n' ' ' | cut -c1-260)"
  else
    ok "ac8: a spec declaring none is line-for-line the run it is today"
  fi
fi

# ac8b — the same guarantee for a spec with NO MCP field at all. Absent and explicit-none are
# different values (spec-manifest §3.2) and it is easy to handle one and not the other.
mkspec "$T/nofield" ""
runpre "$T/nofield"
if [ "$PRE_RC" = 3 ]; then
  no "ac8b: a spec with no MCP field was aborted by the preflight — absent means 'declares nothing', never 'declares broken'"
else
  ok "ac8b: a spec with no MCP field is not probed"
fi

# ac7 — a declared server that cannot be proved stops the run BEFORE task 1, with exit 3 and a
# named class. Exit 3 is load-bearing: readers already key on it as "the container needs attention,
# not another retry".
fixture_start unauthorized
mkconfig "$T/exec-qwen.json" homelab "$FIX_URL" MCP_FIXTURE_KEY
mkspec "$T/withmcp" "MCP: homelab"
runpre "$T/withmcp" MCP_FIXTURE_KEY="$SECRET"
if [ "$PRE_RC" != 3 ]; then
  no "ac7: an unprovable MCP exited $PRE_RC, not 3 — the preflight's verdict code is what tells a reader this is not retryable. Output: $(printf '%s' "$PRE_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
elif ! printf '%s' "$PRE_OUT" | grep -qi 'homelab'; then
  no "ac7: the abort did not name which server failed: $(printf '%s' "$PRE_OUT" | head -2 | tr '\n' ' ')"
elif ! printf '%s' "$PRE_OUT" | grep -qi 'unauthorized'; then
  no "ac7: the abort did not carry the class — 'MCP unavailable' hands back the same undifferentiated answer this spec exists to replace: $(printf '%s' "$PRE_OUT" | head -2 | tr '\n' ' ')"
else
  ok "ac7: an unprovable MCP aborts before task 1 with exit 3, naming the server and its class"
fi

# ac7b — and it aborts BEFORE task 1, not during it. A preflight that runs after the first task has
# started has not prevented the burn it exists to prevent.
if printf '%s' "$PRE_OUT" | grep -qi 'T1\|task 1\|attempt'; then
  no "ac7b: the run reached task 1 before aborting — the whole value is refusing to start"
else
  ok "ac7b: nothing ran before the abort"
fi

# ac7c — green is still reachable through the preflight: a working server must let the run proceed,
# or the preflight has simply banned every MCP-declaring spec.
fixture_stop
fixture_start ok
mkconfig "$T/exec-qwen.json" homelab "$FIX_URL" MCP_FIXTURE_KEY
runpre "$T/withmcp" MCP_FIXTURE_KEY="$SECRET"
if [ "$PRE_RC" = 3 ]; then
  no "ac7c: a WORKING MCP server was still refused by the preflight — the gate cannot pass: $(printf '%s' "$PRE_OUT" | head -3 | tr '\n' ' ' | cut -c1-240)"
else
  ok "ac7c: a working MCP server passes the preflight and the run proceeds"
fi
fixture_stop

gate_done
