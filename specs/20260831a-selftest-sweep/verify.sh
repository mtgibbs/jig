#!/usr/bin/env bash
# specs/20260831a-selftest-sweep/verify.sh — the deterministic gate for "the selftest sweep —
# one command records every mutant corpus".
#
# THE THREE-VERDICT CONTRACT: ok / no / pend; STRICT=1 promotes every pend. ac1–ac4 anchor on
# scripts/selftest-sweep.sh (T1's deliverable) and pend while it does not exist; ac5 anchors on
# the README bullet (T2's) and pends independently — so T1 can go green before T2 exists.
#
# Trap discipline (TEMPLATE §11): the behavioral checks run the REAL tools inside mktemp
# fixture repos (physical paths — the tool resolves a non-git CWD logically on macOS and the
# prefix strip misses otherwise, see 20260830f). ac4's surviving-mutant fixture is the positive
# control that the sweep's red path exists: a sweep that cannot exit non-zero would pass every
# clean-corpus check ever written.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

SWEEP="$R/scripts/selftest-sweep.sh"
T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

# build_fixture <dir> <mutant-content>  — a minimal repo with the real tools and ONE corpus.
# Mutant content "MUT" is caught by the fixture gate (killed); anything else survives.
build_fixture(){
  mkdir -p "$1/scripts" "$1/specs/fxspec/tasks/T01/mutants" "$1/.evidence"
  cp "$R/scripts/gate-selftest.sh" "$R/scripts/mutant-ledger.py" "$R/scripts/bound.sh" "$1/scripts/"
  [ -f "$SWEEP" ] && cp "$SWEEP" "$1/scripts/"
  printf 'healthy\n' > "$1/t.txt"
  cat > "$1/specs/fxspec/tasks/T01/verify.sh" <<'GATE'
#!/usr/bin/env bash
if grep -q MUT ./t.txt 2>/dev/null; then echo "  FAIL  ac1: target is mutated" >&2; exit 1; fi
echo "  PASS  ac1: target healthy"; exit 0
GATE
  chmod +x "$1/specs/fxspec/tasks/T01/verify.sh"
  printf '# MUTANT: ac1\n# TARGET: t.txt\n# WHY: fixture mutation\n%s\n' "$2" \
    > "$1/specs/fxspec/tasks/T01/mutants/m1.txt"
}

# ── ac1 · the script exists, is executable, and parses ─────────────────────────────────────
if [ ! -f "$SWEEP" ]; then
  pend "ac1: scripts/selftest-sweep.sh"
else
  [ -x "$SWEEP" ] && ok "ac1: scripts/selftest-sweep.sh is executable" \
                  || no "ac1: scripts/selftest-sweep.sh is not executable (chmod +x)"
  bash -n "$SWEEP" 2>/dev/null && ok "ac1: bash -n parses clean" \
                               || no "ac1: bash -n reports a syntax error"
fi

# ── ac2 · --dry-run lists exactly the real corpora and writes nothing ──────────────────────
if [ -f "$SWEEP" ]; then
  ( cd "$R" && bash "$SWEEP" --dry-run ) > "$T/dry.out" 2>&1
  grep '^would run: ' "$T/dry.out" | sed 's/^would run: //' | sort > "$T/dry.list"
  find "$R/specs" -type d -name mutants -path '*/tasks/*' 2>/dev/null \
    | while read -r d; do dirname "$d"; done | sed "s|^$R/||" | sort > "$T/find.list"
  _n="$(wc -l < "$T/find.list" | tr -d ' ')"
  if [ "$_n" -lt 6 ]; then
    no "ac2: control — the independent find sees only $_n corpora (6 committed); the comparison is degenerate"
  elif cmp -s "$T/dry.list" "$T/find.list"; then
    ok "ac2: --dry-run lists exactly the $_n real corpora (independent find agrees)"
  else
    no "ac2: --dry-run's list differs from an independent find — $(comm -3 "$T/dry.list" "$T/find.list" | head -3 | tr '\n' ' ')"
  fi
  grep -q '^summary:' "$T/dry.out" \
    && no "ac2: --dry-run ran the tool (a 'summary:' line leaked) — dry means dry" \
    || ok "ac2: --dry-run invoked no tool"
  build_fixture "$T/dryfx" "MUT"
  _b="$(find "$T/dryfx" -type f | sort)"
  ( cd "$T/dryfx" && bash scripts/selftest-sweep.sh --dry-run ) >/dev/null 2>&1
  _a="$(find "$T/dryfx" -type f | sort)"
  [ "$_b" = "$_a" ] && ok "ac2: --dry-run is write-free (fixture tree unchanged)" \
                    || no "ac2: --dry-run wrote files in the fixture"
else
  pend "ac2: --dry-run contract"
fi

# ── ac3 · a clean sweep records rows, regenerates the ledger, exits 0 ──────────────────────
if [ -f "$SWEEP" ]; then
  build_fixture "$T/clean" "MUT"
  ( cd "$T/clean" && bash scripts/selftest-sweep.sh ) > "$T/clean.out" 2>&1
  _rc=$?
  [ "$_rc" = 0 ] && ok "ac3: clean fixture sweep exits 0" \
                 || no "ac3: clean fixture sweep exited $_rc — $(tail -2 "$T/clean.out" | tr '\n' ' ')"
  [ -s "$T/clean/.evidence/selftest-fxspec.jsonl" ] \
    && ok "ac3: rows landed in the fixture's .evidence (selftest-fxspec.jsonl)" \
    || no "ac3: no selftest-fxspec.jsonl — SELFTEST_EVID did not reach the tool"
  [ -s "$T/clean/.evidence/mutant-ledger.md" ] && [ -s "$T/clean/.evidence/mutant-ledger.html" ] \
    && ok "ac3: the ledger regenerated (md + html)" \
    || no "ac3: mutant-ledger.{md,html} missing after a sweep"
  grep -q '^== specs/fxspec/tasks/T01$' "$T/clean.out" \
    && ok "ac3: the per-corpus banner is printed (== specs/fxspec/tasks/T01)" \
    || no "ac3: missing '== specs/fxspec/tasks/T01' banner"
  _stray="$(find "$T/clean" -type f -newer "$T/clean/t.txt" 2>/dev/null | grep -v '/.evidence/' | grep -v '/scripts/' | grep -v '/specs/' | head -3)"
  [ -z "$_stray" ] && ok "ac3: nothing written outside .evidence" \
                   || no "ac3: the sweep wrote outside .evidence — $_stray"
else
  pend "ac3: clean-sweep behavior"
fi

# ── ac4 · a survivor still gets a ledger, and the exit code goes red (positive control) ────
if [ -f "$SWEEP" ]; then
  build_fixture "$T/red" "sneaky"
  ( cd "$T/red" && bash scripts/selftest-sweep.sh ) > "$T/red.out" 2>&1
  _rc=$?
  [ "$_rc" != 0 ] && ok "ac4: positive control — a surviving mutant makes the sweep exit non-zero ($_rc)" \
                  || no "ac4: positive control FAILED — the sweep exited 0 over a survivor; its red path does not exist"
  [ -s "$T/red/.evidence/mutant-ledger.md" ] \
    && ok "ac4: the ledger still regenerated on a red sweep (the record matters most when it is bad)" \
    || no "ac4: a red corpus aborted the sweep before the ledger step"
  grep -q 'SURVIVOR' "$T/red/.evidence/mutant-ledger.md" \
    && ok "ac4: the red ledger names the SURVIVOR" \
    || no "ac4: the regenerated ledger does not carry the survivor"
else
  pend "ac4: red-sweep behavior"
fi

# ── ac5 · the README documents the command ─────────────────────────────────────────────────
if grep -q 'selftest-sweep.sh' "$R/.evidence/README.md" 2>/dev/null; then
  grep -q 'dry-run' "$R/.evidence/README.md" \
    && ok "ac5: .evidence/README.md documents the sweep and its --dry-run" \
    || no "ac5: the README bullet omits --dry-run — copy §6 verbatim"
else
  pend "ac5: the .evidence/README.md bullet"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
