#!/usr/bin/env bash
# Gate for 20260831b-scrub-monolithic-gates. Single-task spec, so this is a single
# spec-level gate with NO pend anywhere — with one task there is no later work to defer
# to (§3). ac1/ac2 run the real ralph-build.sh against mktemp fixtures with a stub
# executor whose marker file proves whether the refusal fired before the executor ran.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"     # physical path — the macOS /var→/private/var lesson
R="$(cd "$T/../.." && pwd -P)"
RB="$R/scripts/ralph-build.sh"
TPL="$R/specs/TEMPLATE.md"
AMD="$R/specs/amendments.md"
RUNDOC="$R/docs/runs/2026-08-31-the-watched-run.md"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX_DIRS=""
cleanup(){ for d in $_FX_DIRS; do rm -rf "$d" "$d.marker"; done; }
trap cleanup EXIT

# mk_fx <ntasks> <per_task 0|1> — build a fixture repo, print its physical path.
# Per-task gates exit 1 (task never satisfied, executor always invoked); the monolithic
# fixture gate exits 0 (so an un-refused run terminates quickly and cleanly).
mk_fx() {
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"
  _FX_DIRS="$_FX_DIRS $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs/fx"
  echo '# fx spec' > "$d/specs/fx/spec.md"
  : > "$d/specs/fx/tasks.txt"
  local i
  for i in $(seq 1 "$1"); do echo "T$i: do thing $i" >> "$d/specs/fx/tasks.txt"; done
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/specs/fx/verify.sh"
  if [ "$2" = "1" ]; then
    for i in $(seq 1 "$1"); do
      mkdir -p "$d/specs/fx/tasks/T0${i}-thing"
      printf '#!/usr/bin/env bash\nexit 1\n' > "$d/specs/fx/tasks/T0${i}-thing/verify.sh"
    done
  fi
  git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null
  printf '%s' "$d"
}

# Stub executor: drops the marker proving it was invoked, changes a file so the attempt
# is not a no-op, and prints enough transcript to clear the stillborn-log floor. The
# marker lives OUTSIDE the repo (STUB_MARKER): the loop's failure path runs
# `git clean -fd`, which deletes an in-repo marker and reads as "never ran".
STUB="$(mktemp)"; _FX_DIRS="$_FX_DIRS $STUB"
cat > "$STUB" <<'EOS'
#!/usr/bin/env bash
: "${ROOT:?}" "${STUB_MARKER:?}"
touch "$STUB_MARKER"
echo "stub change" >> "$ROOT/stub.txt"
printf 'stub transcript line %d\n' $(seq 1 40)
exit 0
EOS

# run_fx <dir> [env VAR=val ...] — run the real loop against the fixture, bounded.
run_fx() {
  local d="$1"; shift
  ( cd "$d" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN -u RALPH_ALLOW_MONOLITHIC \
      "$@" STUB_MARKER="$d.marker" RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
      RALPH_EXEC_CMD="bash $STUB" bash "$RB" specs/fx 2>&1 )
}

# ── ac1: multi-task + monolithic + no hatch → refused, exit 3, before any executor ──
FX1="$(mk_fx 2 0)"
out1="$(run_fx "$FX1")"; rc1=$?
[ "$rc1" -eq 3 ] \
  && ok "ac1: multi-task monolithic spec refused with exit 3" \
  || no "ac1: expected exit 3, got $rc1 — $(printf '%s' "$out1" | head -3 | tr '\n' ' ')"
printf '%s' "$out1" | grep -qi 'per-task\|20260828i' \
  && ok "ac1: the refusal names the convention" \
  || no "ac1: refusal message does not name per-task gates / 20260828i"
[ ! -f "$FX1.marker" ] \
  && ok "ac1: refused BEFORE any executor ran (no marker)" \
  || no "ac1: the stub executor ran despite the refusal"

# ── ac2: the hatch is DEAD (20260831p, by direction: a spec that does not match the
# convention is kicked out, no override) — and single-task monolithic stays untouched ──
FX2="$(mk_fx 2 0)"
out2="$(run_fx "$FX2" RALPH_ALLOW_MONOLITHIC=1)"; rc2=$?
[ "$rc2" -eq 3 ] \
  && ok "ac2: RALPH_ALLOW_MONOLITHIC=1 no longer opens anything (still exit 3)" \
  || no "ac2: the removed hatch still opens (rc=$rc2 with the env set)"
[ ! -f "$FX2.marker" ] \
  && ok "ac2: no executor ran under the dead hatch" \
  || no "ac2: the executor ran — the hatch is back"

FX3="$(mk_fx 1 0)"
out3s="$(run_fx "$FX3" 2>&1)"; rc3=$?
# Since 20260831h a single-task spec with a green gate SKIPS instead of dispatching —
# either the marker (dispatched) or the skip line proves the run was not refused.
{ [ "$rc3" -ne 3 ] && { [ -f "$FX3.marker" ] || printf '%s' "$out3s" | grep -q 'skipped (gate already passed)'; }; } \
  && ok "ac2: single-task monolithic spec is untouched (rc=$rc3)" \
  || no "ac2: single-task monolithic spec was refused (rc=$rc3)"

FX4="$(mk_fx 2 1)"
run_fx "$FX4" >/dev/null 2>&1; rc4=$?
[ "$rc4" -ne 3 ] && [ -f "$FX4.marker" ] \
  && ok "ac2: per-task spec is untouched (rc=$rc4)" \
  || no "ac2: per-task spec was refused (rc=$rc4)"

# ── ac3: the edited loop still parses ──
bash -n "$RB" \
  && ok "ac3: ralph-build.sh passes bash -n" \
  || no "ac3: bash -n fails on ralph-build.sh"

# ── ac4: the TEMPLATE teaches the per-task layout and the pend preamble is gone ──
grep -q 'tasks/T<NN>-<slug>/verify.sh' "$TPL" \
  && ok "ac4: TEMPLATE documents the per-task layout path" \
  || no "ac4: TEMPLATE does not name tasks/T<NN>-<slug>/verify.sh"
grep -qi 'cumulative' "$TPL" \
  && ok "ac4: TEMPLATE documents cumulative gates" \
  || no "ac4: TEMPLATE does not say the gates run cumulatively"
grep -q 'pend.*banned\|banned.*pend\|no `pend` in task gates\|MUST NOT appear in a task gate' "$TPL" \
  && ok "ac4: TEMPLATE bans pend from task gates" \
  || no "ac4: TEMPLATE does not ban pend from task gates"
# Absence assertion; its positive control is the red-before-green record — this exact
# phrase is IN the template before the edit (evidence/red-before-green.txt shows this
# check failing), so the probe demonstrably fires on the pre-edit file.
grep -q 'do NOT write a two-verdict gate' "$TPL" \
  && no "ac4: the pend-preamble copy block is still in the TEMPLATE" \
  || ok "ac4: the pend-preamble copy block is gone"

# ── ac5: the layout-agnostic gate craft survived the rewrite ──
for probe in 'TRAP A' 'TRAP B' 'A-PRIME' 'ONE-QUESTION TEST'; do
  grep -q "$probe" "$TPL" \
    && ok "ac5: TEMPLATE retains '$probe'" \
    || no "ac5: TEMPLATE lost '$probe'"
done

# ── ac6: the law and the record ──
grep -qi 'monolithic.*deprecated\|deprecat.*monolithic' "$AMD" \
  && ok "ac6: amendments.md carries the deprecation" \
  || no "ac6: no deprecation amendment in amendments.md"
grep -q '20260828i' "$RUNDOC" \
  && ok "ac6: the run doc correction cites 20260828i" \
  || no "ac6: run doc postscript not corrected (no 20260828i citation)"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
