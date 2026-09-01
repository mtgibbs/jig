#!/usr/bin/env bash
# Gate for T03-scaffolder-mutants (20260831u-mutants-always-run).
#
# Authoring mutants is the default path: the scaffolder emits a template corpus whose
# header parses but whose sentinel TARGET cannot pass selftest for free; --check refuses
# a task without a well-formed mutant; TEMPLATE.md teaches the inversion move where the
# gate shape is already taught. --check is an authoring tool for NEW work (its own header
# says so), so it enforces the corpus unconditionally — the date boundary lives in the
# LOOP (T02), which is the half that meets history.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
NS="$R/scripts/new-spec.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

D="$(mktemp -d)"; D="$(cd "$D" && pwd -P)"; _FX="$_FX $D"
mkdir -p "$D/specs"
bash "$NS" --root "$D" --id 20990101a fx alpha beta >/dev/null 2>&1 \
  || no "ac1: scaffold failed outright"
SPEC="$D/specs/20990101a-fx"

# ── ac1: every scaffolded task carries a template corpus with a parseable header ──
_miss=""
for i in 1 2; do
  td="$(ls -d "$SPEC/tasks/T0$i"-* 2>/dev/null | head -1)"
  m="$(ls "$td/mutants/"* 2>/dev/null | head -1)"
  if [ -z "$m" ]; then _miss="$_miss T0$i:no-corpus"; continue; fi
  grep -q '^#[[:space:]]*MUTANT:[[:space:]]' "$m" || _miss="$_miss T0$i:no-MUTANT"
  grep -q '^#[[:space:]]*TARGET:[[:space:]]' "$m" || _miss="$_miss T0$i:no-TARGET"
  grep -q '^#[[:space:]]*WHY:[[:space:]]'    "$m" || _miss="$_miss T0$i:no-WHY"
done
[ -z "$_miss" ] \
  && ok "ac1: each task scaffolds a mutants/ template with MUTANT:/TARGET:/WHY: headers" \
  || no "ac1: template corpus missing or malformed —$_miss"

# ── ac2: the template cannot pass selftest for free — its TARGET is a sentinel ──
m="$(ls "$SPEC/tasks/T01-"*/mutants/* 2>/dev/null | head -1)"
if [ -n "$m" ] && grep '^#[[:space:]]*TARGET:' "$m" | grep -q '<'; then
  ok "ac2: the template TARGET is a sentinel (<...>) — a scaffold that selftests green would be a lie"
else
  no "ac2: the template TARGET reads as a real path — an unauthored corpus could pass as authored"
fi

# ── ac3: --check passes the fresh scaffold's shape ──
if bash "$NS" --root "$D" --check "$SPEC" >/dev/null 2>&1; then
  ok "ac3: --check passes a fresh scaffold (template corpus satisfies the shape check)"
else
  no "ac3: --check fails its own scaffold — authors start from a broken state"
fi

# ── ac4: --check refuses a task whose corpus is gone ──
rm -rf "$SPEC/tasks/T02-"*/mutants
out4="$(bash "$NS" --root "$D" --check "$SPEC" 2>&1)"; rc4=$?
[ "$rc4" -ne 0 ] \
  && ok "ac4: --check fails when a task has no mutant corpus (rc=$rc4)" \
  || no "ac4: --check passed a corpus-less task — the authoring tool does not require the pill"
printf '%s' "$out4" | grep -q "mutant" \
  && ok "ac4: the failure names the missing corpus" \
  || no "ac4: the failure does not mention mutants"

# ── ac5: --check refuses a malformed mutant (header contract, not just presence) ──
# T02's corpus is RESTORED first. ac4 left it missing, and a leftover missing corpus fails
# --check for ac4's reason — behind which a headerless-acceptance defect hides. Found by
# this spec's own first selftest run: headerless-accepted.sh SURVIVED until this line.
td2="$(ls -d "$SPEC/tasks/T02-"* | head -1)"
mkdir -p "$td2/mutants"
{ printf '# %s: ac1\n' "MUTANT"; printf '# %s: some/real/path\n' "TARGET"
  printf '# %s: restored so ac5 isolates the headerless case\n' "WHY"; printf 'body\n'
} > "$td2/mutants/restored.txt"
td="$(ls -d "$SPEC/tasks/T01-"* | head -1)"
rm -rf "$td/mutants"; mkdir -p "$td/mutants"
printf 'no header at all\n' > "$td/mutants/broken.txt"
bash "$NS" --root "$D" --check "$SPEC" >/dev/null 2>&1 \
  && no "ac5: --check accepted a mutant with no MUTANT:/TARGET: header" \
  || ok "ac5: --check refuses a headerless mutant — presence without the contract is not a corpus"

# ── ac6: TEMPLATE.md teaches the inversion move ──
grep -qi "invert" "$R/specs/TEMPLATE.md" && grep -qi "mutants/" "$R/specs/TEMPLATE.md" \
  && ok "ac6: TEMPLATE.md teaches authoring mutants by inverting each assertion" \
  || no "ac6: TEMPLATE.md does not teach the mutant authoring move — the convention loses to the template again"

bash -n "$NS" && ok "ac7: new-spec.sh passes bash -n" || no "ac7: new-spec.sh fails bash -n"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T03 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
