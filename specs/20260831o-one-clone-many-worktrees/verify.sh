#!/usr/bin/env bash
# Gate for 20260831o-one-clone-many-worktrees. Single-task spec: one gate, no pend.
# Drives the REAL run-task.sh: local bare repo as the remote, baked harness dir (no .git —
# run-task's no-fetch path, so this gate never touches the checkout or the network), a
# consumer strategy with no tool preflight, stub executor. Pins the shape issue #63 paid
# for in orphaned commits: ONE clone, worktrees per run, `git worktree list` the inventory.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../.." && pwd -P)"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"
cleanup(){ rm -rf "$W"; }
trap cleanup EXIT

# ── the baked harness: scripts only, no .git ──
mkdir -p "$W/harness"
cp -R "$R/scripts" "$W/harness/scripts"

# ── the fixture remote: two specs + a consumer strategy, pushed to a bare repo ──
SRC="$W/src"
mkdir -p "$SRC"
git -C "$SRC" init -q -b main
git -C "$SRC" config user.email fx@fx.invalid
git -C "$SRC" config user.name fx
mkdir -p "$SRC/.harness/loops"
printf 'STRATEGY_DESC="fixture strategy, no tools"\nSTRATEGY_PHASES="build"\n' > "$SRC/.harness/loops/fx.conf"
printf '.evidence/runs/\n' > "$SRC/.gitignore"
for s in fxa fxb; do
  mkdir -p "$SRC/specs/$s/tasks/T01-thing"
  echo "# $s" > "$SRC/specs/$s/spec.md"
  echo "T1: write done into ok-$s.txt" > "$SRC/specs/$s/tasks.txt"
  gate="grep -q done \"\$(git rev-parse --show-toplevel)/ok-$s.txt\" 2>/dev/null || { echo \"  FAIL  fx: ok-$s.txt missing\" >&2; exit 1; }; echo \"  PASS  fx: ok-$s.txt present\"; exit 0"
  printf '#!/usr/bin/env bash\n%s\n' "$gate" > "$SRC/specs/$s/tasks/T01-thing/verify.sh"
  printf '#!/usr/bin/env bash\n%s\n' "$gate" > "$SRC/specs/$s/verify.sh"
done
git -C "$SRC" add -A && git -C "$SRC" commit -qm fx >/dev/null
git clone -q --bare "$SRC" "$W/remote.git"

# ── the stub executor: satisfies whichever spec's task it is handed ──
STUB="$W/stub.sh"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
: "${ROOT:?}"
case "$1" in
  *ok-fxa*) echo done > "$ROOT/ok-fxa.txt" ;;
  *ok-fxb*) echo done > "$ROOT/ok-fxb.txt" ;;
esac
printf 'stub transcript line %d\n' $(seq 1 40)
exit 0
EOF
chmod +x "$STUB"

WS="$W/ws"
run_task() { # <spec>
  ( cd "$W" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN -u RALPH_ALLOW_MONOLITHIC \
      HARNESS_WORKSPACE="$WS" HARNESS_DIR="$W/harness" \
      HARNESS_REPO_URL="$W/remote.git" TMPDIR="$W/tmp" \
      RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=120 RALPH_EXEC_CMD="bash $STUB" \
      bash "$W/harness/scripts/run-task.sh" "specs/$1" --repo fxrepo --strategy fx 2>&1 )
}
mkdir -p "$W/tmp"

clones() { find "$WS" -maxdepth 2 -name .git -type d 2>/dev/null | wc -l | tr -d ' '; }

# ── ac1: run A — one clone, task dir is a worktree ──
outA="$(run_task fxa)"; rcA=$?
[ "$rcA" -eq 0 ] \
  && ok "ac1: run A completed (rc=0)" \
  || no "ac1: run A failed (rc=$rcA) — $(printf '%s' "$outA" | grep -E 'FAIL|refus|error|✗' | head -2 | tr '\n' ' ')"
[ -d "$WS/fxrepo/.git" ] \
  && ok "ac1: the canonical clone exists at \$WORKSPACE/fxrepo" \
  || no "ac1: no clone at $WS/fxrepo"
[ -f "$WS/fxrepo-fxa/.git" ] \
  && ok "ac1: the task dir is a WORKTREE (.git is a file)" \
  || no "ac1: fxrepo-fxa/.git is not a worktree pointer — a clone-per-run regression"
[ "$(clones)" = 1 ] \
  && ok "ac1: exactly one full clone in the workspace" \
  || no "ac1: $(clones) full clones after one run"

# ── ac2: run B — still one clone ──
outB="$(run_task fxb)"; rcB=$?
[ "$rcB" -eq 0 ] || no "ac2: run B failed (rc=$rcB) — $(printf '%s' "$outB" | grep -E 'FAIL|refus|error|✗' | head -2 | tr '\n' ' ')"
[ "$(clones)" = 1 ] \
  && ok "ac2: a second spec reuses the one clone (still exactly one)" \
  || no "ac2: $(clones) full clones after two runs — the 11-clone pile is back"
[ -f "$WS/fxrepo-fxb/.git" ] \
  && ok "ac2: run B's dir is a worktree too" \
  || no "ac2: fxrepo-fxb is not a worktree"

# ── ac3: `git worktree list` is the inventory ──
wl="$(git -C "$WS/fxrepo" worktree list 2>/dev/null)"
printf '%s' "$wl" | grep -q 'fxrepo-fxa' && printf '%s' "$wl" | grep -q 'fxrepo-fxb' \
  && ok "ac3: git worktree list names both run dirs (the inventory)" \
  || no "ac3: worktree list is not the inventory: $(printf '%s' "$wl" | tr '\n' ' ')"

# ── ac4: re-running a spec works (remove --force + prune + -B) ──
outA2="$(run_task fxa)"; rcA2=$?
[ "$rcA2" -eq 0 ] \
  && ok "ac4: re-running spec A succeeds (not runnable-exactly-once)" \
  || no "ac4: re-run failed (rc=$rcA2) — $(printf '%s' "$outA2" | grep -E 'FAIL|already|error' | head -2 | tr '\n' ' ')"
[ "$(clones)" = 1 ] || no "ac4: the re-run grew a clone ($(clones))"

# ── ac5: the runs were real — each worktree carries its task commit ──
for s in fxa fxb; do
  n="$(git -C "$WS/fxrepo-$s" rev-list --count HEAD 2>/dev/null || echo 0)"
  [ "$n" -ge 2 ] \
    && ok "ac5: $s's worktree holds the loop's commit ($n commits)" \
    || no "ac5: $s's worktree has $n commits — the run was vacuous"
done

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
