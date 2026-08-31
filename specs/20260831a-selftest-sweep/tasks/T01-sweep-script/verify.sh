#!/usr/bin/env bash
# T1 — the sweep script's own gate. Per-task shape (20260828i): this task's criteria ONLY,
# no pend anywhere — the script either exists and behaves or this gate is red.
# Ids are two-digit: gate-selftest matches `FAIL.*<id>` as a substring.
#
# Behavioral checks run the REAL tools inside mktemp fixture repos (physical paths — a
# non-git CWD resolves logically on macOS and the prefix strip misses otherwise, 20260830f).
# ac04's surviving-mutant fixture is the positive control that the sweep's red path exists.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
. "$ROOT/specs/lib/assert.sh"

SWEEP="$ROOT/scripts/selftest-sweep.sh"
gate_tmpdir
T="$(cd "$T" && pwd -P)"
trap 'rm -rf "$T"' EXIT

# build_fixture <dir> <mutant-content> — a minimal repo with the real tools and ONE corpus.
# Mutant content "MUT" is caught by the fixture gate (killed); anything else survives.
build_fixture(){
  mkdir -p "$1/scripts" "$1/specs/fxspec/tasks/T01/mutants" "$1/.evidence"
  cp "$ROOT/scripts/gate-selftest.sh" "$ROOT/scripts/mutant-ledger.py" "$ROOT/scripts/bound.sh" "$1/scripts/"
  cp "$SWEEP" "$1/scripts/" 2>/dev/null
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

# ── ac01 · the script exists, is executable, and parses ────────────────────────────────────
if [ ! -f "$SWEEP" ]; then
  no "ac01: scripts/selftest-sweep.sh does not exist"
else
  [ -x "$SWEEP" ] && ok "ac01: scripts/selftest-sweep.sh is executable" \
                  || no "ac01: scripts/selftest-sweep.sh is not executable (chmod +x)"
  bash -n "$SWEEP" 2>/dev/null && ok "ac01: bash -n parses clean" \
                               || no "ac01: bash -n reports a syntax error"
fi

# ── ac02 · --dry-run lists exactly the real corpora and writes nothing ─────────────────────
if [ -f "$SWEEP" ] && bash -n "$SWEEP" 2>/dev/null; then
  ( cd "$ROOT" && bash "$SWEEP" --dry-run ) > "$T/dry.out" 2>&1
  grep '^would run: ' "$T/dry.out" | sed 's/^would run: //' | sort > "$T/dry.list"
  find "$ROOT/specs" -type d -name mutants -path '*/tasks/*' 2>/dev/null \
    | while read -r d; do dirname "$d"; done | sed "s|^$ROOT/||" | sort > "$T/find.list"
  _n="$(wc -l < "$T/find.list" | tr -d ' ')"
  if [ "$_n" -lt 6 ]; then
    no "ac02: control — the independent find sees only $_n corpora (>=6 committed); the comparison is degenerate"
  elif cmp -s "$T/dry.list" "$T/find.list"; then
    ok "ac02: --dry-run lists exactly the $_n real corpora (independent find agrees)"
  else
    no "ac02: --dry-run's list differs from an independent find — $(comm -3 "$T/dry.list" "$T/find.list" | head -3 | tr '\n' ' ')"
  fi
  grep -q '^summary:' "$T/dry.out" \
    && no "ac02: --dry-run ran the tool (a 'summary:' line leaked) — dry means dry" \
    || ok "ac02: --dry-run invoked no tool"
  build_fixture "$T/dryfx" "MUT"
  _b="$(find "$T/dryfx" -type f | sort)"
  ( cd "$T/dryfx" && bash scripts/selftest-sweep.sh --dry-run ) >/dev/null 2>&1
  _a="$(find "$T/dryfx" -type f | sort)"
  [ "$_b" = "$_a" ] && ok "ac02: --dry-run is write-free (fixture tree unchanged)" \
                    || no "ac02: --dry-run wrote files in the fixture"
else
  no "ac02: unmeasurable — the script is missing or does not parse"
fi

# ── ac03 · a clean sweep records rows, regenerates the ledger, exits 0 ─────────────────────
if [ -f "$SWEEP" ] && bash -n "$SWEEP" 2>/dev/null; then
  build_fixture "$T/clean" "MUT"
  ( cd "$T/clean" && bash scripts/selftest-sweep.sh ) > "$T/clean.out" 2>&1
  _rc=$?
  [ "$_rc" = 0 ] && ok "ac03: clean fixture sweep exits 0" \
                 || no "ac03: clean fixture sweep exited $_rc — $(tail -2 "$T/clean.out" | tr '\n' ' ')"
  [ -s "$T/clean/.evidence/selftest-fxspec.jsonl" ] \
    && ok "ac03: rows landed in the fixture's .evidence (selftest-fxspec.jsonl)" \
    || no "ac03: no selftest-fxspec.jsonl — SELFTEST_EVID did not reach the tool"
  [ -s "$T/clean/.evidence/mutant-ledger.md" ] && [ -s "$T/clean/.evidence/mutant-ledger.html" ] \
    && ok "ac03: the ledger regenerated (md + html)" \
    || no "ac03: mutant-ledger.{md,html} missing after a sweep"
  grep -q '^== specs/fxspec/tasks/T01$' "$T/clean.out" \
    && ok "ac03: the per-corpus banner is printed (== specs/fxspec/tasks/T01)" \
    || no "ac03: missing '== specs/fxspec/tasks/T01' banner"
  _stray="$(find "$T/clean" -type f -newer "$T/clean/t.txt" 2>/dev/null | grep -v '/.evidence/' | grep -v '/scripts/' | grep -v '/specs/' | head -3)"
  [ -z "$_stray" ] && ok "ac03: nothing written outside .evidence" \
                   || no "ac03: the sweep wrote outside .evidence — $_stray"
else
  no "ac03: unmeasurable — the script is missing or does not parse"
fi

# ── ac04 · a survivor still gets a ledger, and the exit code goes red (positive control) ───
if [ -f "$SWEEP" ] && bash -n "$SWEEP" 2>/dev/null; then
  build_fixture "$T/red" "sneaky"
  ( cd "$T/red" && bash scripts/selftest-sweep.sh ) > "$T/red.out" 2>&1
  _rc=$?
  [ "$_rc" != 0 ] && ok "ac04: positive control — a surviving mutant makes the sweep exit non-zero ($_rc)" \
                  || no "ac04: positive control FAILED — the sweep exited 0 over a survivor; its red path does not exist"
  [ -s "$T/red/.evidence/mutant-ledger.md" ] \
    && ok "ac04: the ledger still regenerated on a red sweep (the record matters most when it is bad)" \
    || no "ac04: a red corpus aborted the sweep before the ledger step"
  grep -q 'SURVIVOR' "$T/red/.evidence/mutant-ledger.md" 2>/dev/null \
    && ok "ac04: the red ledger names the SURVIVOR" \
    || no "ac04: the regenerated ledger does not carry the survivor"
else
  no "ac04: unmeasurable — the script is missing or does not parse"
fi

gate_done
