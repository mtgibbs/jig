#!/usr/bin/env bash
# T2 — a consumer repo brings its own strategy and binding, and vendors no harness file.
#
# BEHAVIOURAL, not textual. Every assertion here RUNS run-loop.sh against a fixture repo and
# reads what it did. A text gate on this task is the Trap A case in its purest form: the words
# `.harness`, `HARNESS_REPO_ROOT` and `assert.sh` all appear in this spec, in the loops README
# and in run-loop.sh's own comments, so a grep passes with the resolver absent.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
. "$ROOT/specs/20260829a-executor-image-layer/lib/fixtures.sh"

gate_tmpdir
if [ -z "${T:-}" ] || [ ! -d "$T" ] || ! touch "$T/.w" 2>/dev/null; then
  echo "  FAIL  ac0: no usable workspace (T='${T:-}') — the gate could not run" >&2
  echo "VERIFY: FAIL"; exit 1
fi

RL="$ROOT/scripts/run-loop.sh"
[ -f "$RL" ] || { no "ac0: scripts/run-loop.sh is missing entirely"; gate_done; }

# ── the fixture: a consumer repo that carries specs and .harness, and NO harness scripts ─────
# The whole point of the task is that this repo works without vendoring anything, so the fixture
# must not contain a scripts/ directory. If it did, every assertion below could be satisfied by
# the copy rather than by the resolver.
mkrepo "$T/consumer"
mkspec "$T/consumer" fx
mkdir -p "$T/consumer/.harness/loops"
cat > "$T/consumer/.harness/stub.sh" <<'STUB'
#!/usr/bin/env bash
echo "STUB-RAN spec=$1 root=[${HARNESS_REPO_ROOT:-UNSET}]"
STUB
chmod +x "$T/consumer/.harness/stub.sh"
cat > "$T/consumer/.harness/loops/mine.conf" <<'CONF'
STRATEGY_DESC="consumer strategy"
STRATEGY_PHASES="build"
export BUILD_CMD="${HARNESS_REPO_ROOT:-/nonexistent}/.harness/stub.sh"
CONF
# A conf that SHADOWS a built-in name, to prove precedence rather than mere discovery.
sed 's/consumer strategy/shadowing build-converge/' "$T/consumer/.harness/loops/mine.conf" \
  > "$T/consumer/.harness/loops/build-converge.conf"

# Every fixture invocation is BOUNDED and given a safe default BUILD_CMD.
#
# BUILD_CMD in the environment covers the case this gate exists to detect: when the resolver is
# absent, `build-converge` falls through to the BUILT-IN conf, which sets no BUILD_CMD and so
# runs the real ralph-build.sh — an executor call that waits. The gate would then hang rather
# than fail, and the author would read a timeout as a broken fixture. The consumer conf sets
# BUILD_CMD itself and still wins, which is what ac2 measures.
SAFE="$T/safe.sh"
printf '#!/usr/bin/env bash\necho "BUILTIN-PATH spec=$1"\n' > "$SAFE"; chmod +x "$SAFE"

run_fx() {
  ( cd "$T/consumer" && SCRIPT_DIR="$ROOT/scripts" BUILD_CMD="$SAFE" \
      bounded 20 bash "$RL" "$@" ) 2>&1
}

# ── ac1: the consumer conf is preferred over a built-in of the same name ─────────────────────
out="$(run_fx build-converge specs/fx)"
if echo "$out" | grep -q 'unknown strategy'; then
  no "ac1: run-loop.sh does not look in \$HARNESS_REPO_ROOT/.harness/loops at all — it reported 'unknown strategy' for a conf sitting in the consumer repo"
elif ! echo "$out" | grep -q 'shadowing build-converge'; then
  no "ac1: run-loop.sh found A build-converge but not the consumer's — the built-in won. Precedence is the point: a repo must be able to override a strategy name, not merely add one. Saw: $(echo "$out" | grep -i 'strategy:' | head -1)"
else
  ok "ac1: the consumer conf is preferred over the built-in of the same name"
fi

# ── ac2: HARNESS_REPO_ROOT is exported BEFORE the conf is sourced ────────────────────────────
# The conf above interpolates ${HARNESS_REPO_ROOT} into BUILD_CMD at SOURCE time. Export it
# afterwards and BUILD_CMD points at /nonexistent — the stub never runs. This is the specific
# bug a consumer conf hits first, because ralph-build.sh (not run-loop.sh) is what exports ROOT
# and it has not run yet at that point.
out="$(run_fx mine specs/fx)"
if ! echo "$out" | grep -q 'STUB-RAN'; then
  no "ac2: the consumer's BUILD_CMD never ran, so \$HARNESS_REPO_ROOT was unset or empty when the conf was sourced. Output: $(echo "$out" | tail -2 | tr '\n' ' ')"
elif echo "$out" | grep -q 'root=\[\]' || echo "$out" | grep -q 'root=\[UNSET\]'; then
  no "ac2: HARNESS_REPO_ROOT reached the phase but was empty — it must be exported before the conf is sourced, not after"
else
  ok "ac2: HARNESS_REPO_ROOT is exported before the conf is sourced"
fi

# ── ac3: no .harness/ means today's behaviour, unchanged ─────────────────────────────────────
# POSITIVE CONTROL for an absence assertion: ac1 above proved the probe can see a consumer conf,
# so "the built-in ran" here is a real reading and not a broken lookup.
mkrepo "$T/plain"
mkspec "$T/plain" fx
out="$( cd "$T/plain" && SCRIPT_DIR="$ROOT/scripts" BUILD_CMD="$SAFE" bounded 20 bash "$RL" --list 2>&1 )"
if ! echo "$out" | grep -q 'build-converge'; then
  no "ac3: a repo with no .harness/ can no longer see the built-in strategies. The search path must be additive — every repo that exists today is this case"
elif echo "$out" | grep -qi 'error\|no such'; then
  no "ac3: a repo with no .harness/ produced an error. An absent consumer directory is not a misconfiguration"
else
  ok "ac3: a repo with no .harness/ resolves the built-ins exactly as today"
fi

# ── ac4: --list shows both locations and hides a shadowed built-in ───────────────────────────
out="$(run_fx --list)"
n_bc="$(echo "$out" | grep -c 'build-converge' || true)"
if ! echo "$out" | grep -q 'mine'; then
  no "ac4: --list does not show the consumer's own strategies, so a reader cannot discover what this repo added"
elif [ "$n_bc" -gt 1 ]; then
  no "ac4: --list prints build-converge $n_bc times — both the shadowed built-in and the consumer's. Listing both tells the reader the opposite of what will run"
elif ! echo "$out" | grep -qiE 'consumer|repo|\.harness|built-?in|local'; then
  no "ac4: --list does not mark WHICH location each strategy came from, so a shadowed name is indistinguishable from a built-in one"
else
  ok "ac4: --list covers both locations, marks them, and hides the shadowed built-in"
fi

# ── ac5: an unknown strategy names both searched paths ───────────────────────────────────────
out="$(run_fx definitely-not-a-strategy specs/fx)"
if echo "$out" | grep -q 'STUB-RAN'; then
  no "ac5: an unknown strategy still ran something"
elif ! echo "$out" | grep -q '\.harness'; then
  no "ac5: the not-found message does not name the consumer path that was searched, so someone whose conf is in the wrong place is told only that the harness does not know the name"
elif ! echo "$out" | grep -qE 'loops'; then
  no "ac5: the not-found message does not name the built-in path either"
else
  ok "ac5: an unknown strategy names both paths that were searched"
fi

# ── ac6: a gate resolves assert.sh from HARNESS_HOME, falling back to ROOT ───────────────────
# The consumer repo carries NO specs/lib. A gate written the old way dies on a missing file;
# resolved correctly it finds the harness's copy. The fallback half is proved by this repo's own
# gates, which have no HARNESS_HOME set and still pass.
mkdir -p "$T/consumer/specs/fx/tasks/T01-x"
cat > "$T/consumer/specs/fx/tasks/T01-x/verify.sh" <<'CG'
#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "${HARNESS_HOME:-$ROOT}/specs/lib/assert.sh" 2>/dev/null || . "$ROOT/specs/lib/assert.sh"
ok "consumer gate reached its vocabulary"
gate_done
CG
out="$( cd "$T/consumer" && HARNESS_HOME="$ROOT" bounded 20 bash specs/fx/tasks/T01-x/verify.sh 2>&1 )"
if ! echo "$out" | grep -q 'VERIFY: PASS'; then
  no "ac6: a consumer gate cannot reach assert.sh through HARNESS_HOME — so every repo using this harness must still vendor specs/lib/assert.sh, which then drifts. Output: $(echo "$out" | tail -1)"
else
  ok "ac6: assert.sh resolves from HARNESS_HOME with a \$ROOT fallback"
fi

gate_done
