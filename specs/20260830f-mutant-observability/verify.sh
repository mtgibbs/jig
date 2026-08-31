#!/usr/bin/env bash
# specs/20260830f-mutant-observability/verify.sh — the deterministic gate for "mutant
# observability: the kill/survivor record, and the diff that shows what got through".
#
# THE THREE-VERDICT CONTRACT: ok / no / pend; STRICT=1 promotes every pend. The emission
# flag, the generator and the committed store read `pend` until built; a tool that emits
# wrong rows, a generator whose links dangle, or a committed ledger that no longer matches
# its store is `no` outright.
#
# Trap discipline (TEMPLATE §11): the central positive control is a FIXTURE CORPUS built in
# mktemp — one mutant the gate must kill, one it must accept (survivor), one that fails the
# wrong assertion — so every claim that the emission "tells states apart" is proven against
# all three states, not inferred from a clean corpus (which only ever shows KILLED). The
# hermetic-default check (no SELFTEST_EVID => no writes) is an absence assertion whose probe
# is the same fixture run WITH the flag set — if that run produces no rows, the absence
# check is reported meaningless rather than passed. 20260828k's end-1 ("a selftest run
# leaves the tree byte-identical") is why the default MUST stay write-free.
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

command -v jq >/dev/null 2>&1 || { echo "  FAIL  scope: jq required" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "  FAIL  scope: python3 required" >&2; exit 1; }

_stray="$(find "$R/specs/20260830f-mutant-observability" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name evidence 2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

# The ledger's per-mutant links are built CLIENT-SIDE from the embedded JSON payload, so a
# checker that only greps static hrefs goes inert while looking alive (Trap A-prime — and it
# did, on this gate's own first green run). The checker walks BOTH: static github links and
# every repo path the payload will render (target, and mutants/<name> where the corpus has a
# repo layout). Prints "<total> <dangling>".
cat > "$T/linkcheck.py" <<'PY'
import sys, re, os, json
html, root = open(sys.argv[1], encoding="utf-8").read(), sys.argv[2]
tot = bad = 0
def check(p):
    global tot, bad
    tot += 1
    if not os.path.exists(os.path.join(root, p)): bad += 1
for m in re.finditer(r'https://github\.com/[^/"]+/[^/"]+/(?:blob|tree)/main/([^"#]+)', html):
    check(m.group(1))
m = re.search(r'<script type="application/json" id="data">(.*?)</script>', html, re.S)
if m:
    for corp in json.loads(m.group(1)):
        for r in corp["rows"]:
            check(r["target"])
            if corp.get("base"): check(corp["base"] + "/mutants/" + r["mutant"])
print(f"{tot} {bad}")
PY

# ── the fixture corpus: three mutants, three distinct verdicts ─────────────────────────────
# Physical path on purpose: the tool resolves TASK_DIR with `pwd -P` but falls back to a
# LOGICAL $CWD when the fixture is not a git repo, and on macOS /var vs /private/var makes
# the prefix strip miss (the tool's own header documents the class).
FX="$(cd "$T" && pwd -P)/fx"
mkdir -p "$FX/task/mutants"
printf 'healthy\n' > "$FX/t.txt"
cat > "$FX/task/verify.sh" <<'GATE'
#!/usr/bin/env bash
if grep -q MUT ./t.txt 2>/dev/null; then echo "  FAIL  ac1: target is mutated" >&2; exit 1; fi
echo "  PASS  ac1: target healthy"; exit 0
GATE
chmod +x "$FX/task/verify.sh"
printf '# MUTANT: ac1\n# TARGET: t.txt\n# WHY: the mutation ac1 exists to catch\nMUT\n' \
  > "$FX/task/mutants/gets-killed.txt"
printf '# MUTANT: ac1\n# TARGET: t.txt\n# WHY: a change the gate cannot see at all\nsneaky\n' \
  > "$FX/task/mutants/survives.txt"
printf '# MUTANT: ac2\n# TARGET: t.txt\n# WHY: aimed at ac2 but only ac1 will fire\nMUT wrong aim\n' \
  > "$FX/task/mutants/wrong-aim.txt"

run_fixture(){ # $1 = evid dir or "" for unset — prints tool stdout; tool exit code ignored
  ( cd "$FX" && if [ -n "$1" ]; then SELFTEST_EVID="$1" bash "$R/scripts/gate-selftest.sh" "$FX/task"
                else env -u SELFTEST_EVID bash "$R/scripts/gate-selftest.sh" "$FX/task"; fi ) 2>&1
}

# ── AC1 · emission exists and tells the three states apart ─────────────────────────────────
mkdir -p "$T/evid"
_prose="$(run_fixture "$T/evid" || true)"
ROWS="$T/evid/selftest-task.jsonl"
if [ ! -s "$ROWS" ]; then
  pend "ac1: SELFTEST_EVID emission (no rows from the fixture run)"
  EMITTED=0
else
  EMITTED=1
  _v(){ jq -r "select(.mutant==\"$1\") | .verdict" "$ROWS" 2>/dev/null | head -1; }
  [ "$(_v gets-killed.txt)" = "KILLED" ] \
    && ok "ac1: the killed fixture mutant emits verdict KILLED" \
    || no "ac1: gets-killed.txt emitted '$(_v gets-killed.txt)', wanted KILLED"
  [ "$(_v survives.txt)" = "SURVIVOR" ] \
    && ok "ac1: the surviving fixture mutant emits verdict SURVIVOR — the record can say the bad thing" \
    || no "ac1: survives.txt emitted '$(_v survives.txt)', wanted SURVIVOR"
  [ "$(_v wrong-aim.txt)" = "WRONG-REASON" ] \
    && ok "ac1: the mis-aimed fixture mutant emits verdict WRONG-REASON" \
    || no "ac1: wrong-aim.txt emitted '$(_v wrong-aim.txt)', wanted WRONG-REASON"
  jq -e 'select(.mutant=="wrong-aim.txt") | .instead | index("ac1")' "$ROWS" >/dev/null 2>&1 \
    && ok "ac1: the wrong-reason row names the assertion that fired instead (ac1)" \
    || no "ac1: wrong-aim.txt's row does not carry instead=[..ac1..] — the one fact needed to fix a mis-aimed mutant"
fi

# ── AC2 · row schema, and prose/row agreement ──────────────────────────────────────────────
if [ "$EMITTED" = 1 ]; then
  _bad="$(jq -r 'select(.run_complete != true)
    | select((.ts and .run_id and .spec and .task and .mutant and .assertion and .target and .verdict and (.gate_rc != null) and (.diff != null) and (.why != null)) | not)
    | .mutant // "row-missing-mutant"' "$ROWS" | head -3 | tr '\n' ' ')"
  [ -z "$_bad" ] && ok "ac2: every mutant row carries the full schema (ts run_id spec task mutant assertion target verdict gate_rc why diff)" \
                 || no "ac2: rows missing required fields — $_bad"
  _mk="$(jq -r 'select(.run_complete == true) | [.killed,.survivor,.wrong_reason,.hung] | @tsv' "$ROWS" | tail -1)"
  _ms="$(printf '%s' "$_prose" | grep '^summary:' | tail -1 | sed 's/[a-z-]*=/ /g' | awk '{print $2"\t"$3"\t"$4"\t"$5}')"
  if [ -z "$_mk" ]; then
    no "ac2: no run_complete marker row — a partial run is indistinguishable from a finished one"
  elif [ "$_mk" = "$_ms" ]; then
    ok "ac2: the marker row's counts agree with the prose summary ($_mk)"
  else
    no "ac2: marker counts ($_mk) disagree with the prose summary ($_ms) — two records, one run, two stories"
  fi
else
  pend "ac2: row schema and marker (no emission yet)"
fi

# ── AC3 · the diff is captured, and it shows the mutation ──────────────────────────────────
if [ "$EMITTED" = 1 ]; then
  _nod="$(jq -r 'select(.run_complete != true) | select((.diff | length) == 0) | .mutant' "$ROWS" | head -3 | tr '\n' ' ')"
  [ -z "$_nod" ] && ok "ac3: every row carries a non-empty mutant-vs-target diff" \
                 || no "ac3: rows with empty diff — $_nod"
  jq -r 'select(.mutant=="gets-killed.txt") | .diff' "$ROWS" | grep -q '^+MUT' \
    && ok "ac3: the killed mutant's diff shows the mutation itself (+MUT)" \
    || no "ac3: gets-killed.txt's diff does not show the +MUT line — the payload is missing from the record"
else
  pend "ac3: diff capture (no emission yet)"
fi

# ── AC4 · hermetic by default — no flag, no writes (20260828k end-1 must keep holding) ─────
_before="$(find "$FX" -type f | sort)"
run_fixture "" >/dev/null || true
_after="$(find "$FX" -type f | sort)"
if [ "$_before" = "$_after" ]; then
  if [ "$EMITTED" = 1 ]; then
    ok "ac4: without SELFTEST_EVID the tool writes nothing (probe proven by ac1's rows)"
  else
    pend "ac4: default is write-free, but emission doesn't exist yet so this proves nothing"
  fi
else
  no "ac4: an unflagged selftest run left files behind — 20260828k end-1 (byte-identical tree) is broken"
fi

# ── AC5 · the generator renders the store; survivors first; its links are checked ──────────
GEN="$R/scripts/mutant-ledger.py"
if [ ! -f "$GEN" ]; then
  pend "ac5: scripts/mutant-ledger.py"
elif [ "$EMITTED" = 1 ]; then
  mkdir -p "$T/out"
  if python3 "$GEN" --evid "$T/evid" --out "$T/out" >/dev/null 2>&1 \
     && [ -s "$T/out/mutant-ledger.html" ] && [ -s "$T/out/mutant-ledger.md" ]; then
    ok "ac5: the generator renders html + md from a store"
    python3 - "$T/out/mutant-ledger.md" <<'PY' && ok "ac5: the survivor renders before the kills" || no "ac5: survivor does not sort first in the ledger"
import sys
md = open(sys.argv[1]).read()
s, k = md.find("survives.txt"), md.find("gets-killed.txt")
sys.exit(0 if 0 <= s < k else 1)
PY
    # positive control for the link check used on the real ledger below: a row with a bogus
    # repo path must be caught by the SAME checker, or ac7's clean result proves nothing.
    cp "$ROWS" "$T/evid2.jsonl"; mkdir -p "$T/evid2" "$T/out2"; mv "$T/evid2.jsonl" "$T/evid2/selftest-task.jsonl"
    # Same run_id on purpose: the bogus row must join the run the generator renders — a row
    # in a marker-less phantom run is invisible, and an invisible plant proves nothing.
    jq -c 'select(.mutant=="gets-killed.txt") | .target="docs/this-file-does-not-exist.md" | .mutant="bogus-target.txt"' \
      "$ROWS" >> "$T/evid2/selftest-task.jsonl"
    python3 "$GEN" --evid "$T/evid2" --out "$T/out2" >/dev/null 2>&1 || true
    linkcheck_fails="$(python3 "$T/linkcheck.py" "$T/out2/mutant-ledger.html" "$R" 2>/dev/null | awk '{print $2}')"
    if [ -s "$T/out2/mutant-ledger.html" ] && [ "${linkcheck_fails:-0}" -ge 1 ]; then
      ok "ac5: positive control — the link checker flags a planted bogus target ($linkcheck_fails dangling)"
    else
      no "ac5: positive control FAILED — the link checker cannot flag a bogus target, so ac7's clean pass below is meaningless"
    fi
  else
    no "ac5: generator run failed or produced no output for the fixture store"
  fi
else
  pend "ac5: generator behavior (no emission to feed it yet)"
fi

# ── AC6 · the real store exists: 6 corpora, ≥31 mutants, every run complete ────────────────
_store="$(ls "$R"/.evidence/selftest-2026*.jsonl 2>/dev/null | head -5)"
if [ -z "$_store" ]; then
  pend "ac6: .evidence/selftest-<slug>.jsonl (the real sweep has not been recorded)"
else
  _corpora="$(cat "$R"/.evidence/selftest-2026*.jsonl | jq -r 'select(.run_complete==true) | .spec + "/" + .task' | sort -u | wc -l | tr -d ' ')"
  _muts="$(cat "$R"/.evidence/selftest-2026*.jsonl | jq -r 'select(.run_complete != true) | .mutant' | sort -u | wc -l | tr -d ' ')"
  [ "$_corpora" -ge 6 ] && ok "ac6: the store carries complete runs for $_corpora corpora" \
                        || no "ac6: only $_corpora corpora have complete runs (6 committed corpora exist)"
  [ "$_muts" -ge 31 ] && ok "ac6: the store carries $_muts distinct mutants (>= 31)" \
                      || no "ac6: only $_muts distinct mutants recorded — the committed corpus holds 31"
fi

# ── AC7 · the committed ledger is fresh, deterministic, and dangling-free ──────────────────
if [ ! -f "$R/.evidence/mutant-ledger.html" ] || [ ! -f "$R/.evidence/mutant-ledger.md" ]; then
  pend "ac7: committed .evidence/mutant-ledger.{html,md}"
elif [ -f "$GEN" ] && [ -n "$_store" ]; then
  mkdir -p "$T/regen"
  python3 "$GEN" --evid "$R/.evidence" --out "$T/regen" >/dev/null 2>&1
  if cmp -s "$T/regen/mutant-ledger.html" "$R/.evidence/mutant-ledger.html" \
     && cmp -s "$T/regen/mutant-ledger.md" "$R/.evidence/mutant-ledger.md"; then
    ok "ac7: regenerating from the committed store reproduces the committed ledger byte-for-byte"
  else
    no "ac7: the committed ledger does not match its store — stale render, or a non-deterministic generator"
  fi
  _links="$(python3 "$T/linkcheck.py" "$R/.evidence/mutant-ledger.html" "$R")"
  _tot="${_links% *}"; _bad="${_links#* }"
  [ "$_tot" -ge 30 ] && ok "ac7: control — the ledger carries $_tot repo links (floor 30); extraction is live" \
                     || no "ac7: control — only $_tot repo links extracted; the checker went inert and proves nothing"
  [ "$_bad" = 0 ] && ok "ac7: every repo link in the committed ledger resolves" \
                  || no "ac7: $_bad dangling repo links in the committed ledger"
else
  pend "ac7: ledger freshness (generator or store missing)"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
