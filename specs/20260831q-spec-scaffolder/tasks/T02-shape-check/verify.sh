#!/usr/bin/env bash
# Gate for T02-shape-check (20260831q). Every broken fixture here is the POSITIVE
# CONTROL for one of --check's absence assertions (TEMPLATE Trap B): each probe is
# shown firing on a violation constructed on purpose. The banned staging verb is
# built by concatenation so this file never contains it as a word.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
NS="$R/scripts/new-spec.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

[ -f "$NS" ] || { echo "  FAIL  ac0: scripts/new-spec.sh does not exist" >&2; echo; echo "VERIFY: failures above" >&2; exit 1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

PW="pe""nd"

# mk_spec — fresh root + scaffolded 3-task spec; prints the spec dir
mk_spec() {
  local rt; rt="$(mktemp -d)"; rt="$(cd "$rt" && pwd -P)"; _FX="$_FX $rt"
  mkdir -p "$rt/specs"
  bash "$NS" --root "$rt" --id 20990101a fx-shape one-thing two-thing three-thing >/dev/null 2>&1 || return 1
  printf '%s' "$rt/specs/20990101a-fx-shape"
}

chk() { bash "$NS" --check "$1" 2>&1; }

# ── ac1: green on a fresh scaffold, and on a real merged per-task spec ──
D1="$(mk_spec)" || no "ac1: scaffold for the fixture failed"
chk "$D1" >/dev/null; rc=$?
[ "$rc" -eq 0 ] \
  && ok "ac1: --check is green on a fresh scaffold" \
  || no "ac1: --check rejects the scaffolder's own output (rc=$rc)"
chk "$R/specs/20260831p-monolithic-refused-outright" >/dev/null; rc=$?
[ "$rc" -eq 0 ] \
  && ok "ac1: --check is green on the real 20260831p spec" \
  || no "ac1: --check rejects 20260831p (rc=$rc)"

# ── ac2: missing tasks/ fails — multi-task AND single-task alike ──
D2="$(mk_spec)"
rm -rf "$D2/tasks"
out="$(chk "$D2")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'no tasks/ directory' \
  && ok "ac2: a multi-task spec without tasks/ is a shape violation" \
  || no "ac2: missing tasks/ passed --check (rc=$rc)"
RT2="$(mktemp -d)"; RT2="$(cd "$RT2" && pwd -P)"; _FX="$_FX $RT2"
mkdir -p "$RT2/specs"
bash "$NS" --root "$RT2" --id 20990101a lone-fix only-task >/dev/null 2>&1
rm -rf "$RT2/specs/20990101a-lone-fix/tasks"
out="$(chk "$RT2/specs/20990101a-lone-fix")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'single-task included' \
  && ok "ac2: a SINGLE-task spec without tasks/ is refused too — check is stricter than the loop here, by design" \
  || no "ac2: the single-task exemption is back in --check (rc=$rc)"

# ── ac3: a tasks.txt line with no gate dir, and a gate dir with no tasks.txt line ──
D3="$(mk_spec)"
rm -rf "$D3/tasks/T02-two-thing"
out="$(chk "$D3")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'task 2 has no tasks/T02' \
  && ok "ac3: a missing T02 dir is named" \
  || no "ac3: missing task dir not caught (rc=$rc)"
D3b="$(mk_spec)"
mkdir -p "$D3b/tasks/T04-ghost"
printf '#!/usr/bin/env bash\nexit 1\n' > "$D3b/tasks/T04-ghost/verify.sh"
chmod +x "$D3b/tasks/T04-ghost/verify.sh"
out="$(chk "$D3b")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'orphan or missing' \
  && ok "ac3: an orphan task dir (no tasks.txt line) is a violation" \
  || no "ac3: orphan T04 dir passed --check (rc=$rc)"

# ── ac4: gate file problems — absent, and present-but-not-executable ──
D4="$(mk_spec)"
rm "$D4/tasks/T03-three-thing/verify.sh"
chk "$D4" >/dev/null 2>&1 && no "ac4: a task dir without verify.sh passed" || ok "ac4: a task dir without verify.sh fails"
D4b="$(mk_spec)"
chmod -x "$D4b/tasks/T01-one-thing/verify.sh"
out="$(chk "$D4b")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'not executable' \
  && ok "ac4: a non-executable gate fails and is named" \
  || no "ac4: non-executable gate passed --check (rc=$rc)"

# ── ac5: the staging verb as CODE fails; the same word in a COMMENT does not ──
D5="$(mk_spec)"
echo "$PW ac9 \"later work\"" >> "$D5/tasks/T01-one-thing/verify.sh"
chk "$D5" >/dev/null 2>&1 && no "ac5: '$PW' as code in a task gate passed" || ok "ac5: '$PW' as code in a task gate fails"
D5b="$(mk_spec)"
echo "# this gate never uses $PW — the ban is honored" >> "$D5b/tasks/T01-one-thing/verify.sh"
chk "$D5b" >/dev/null 2>&1 \
  && ok "ac5: '$PW' in a comment is NOT a violation (comments stripped — a gate may state the ban)" \
  || no "ac5: a comment mentioning '$PW' tripped the probe"
D5c="$(mk_spec)"
echo "$PW convergence-claim" >> "$D5c/verify.sh"
chk "$D5c" >/dev/null 2>&1 && no "ac5: '$PW' as code in the spec-level gate passed" || ok "ac5: '$PW' as code in the spec-level gate fails"

# ── ac6: tasks.txt numbering must be contiguous from T1 ──
D6="$(mk_spec)"
printf 'T1: first thing\nT5: skipped ahead\nT3: third thing\n' > "$D6/tasks.txt"
out="$(chk "$D6")"; rc=$?
[ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "expected it to start 'T2:'" \
  && ok "ac6: non-contiguous numbering fails and names the expected line" \
  || no "ac6: renumbered tasks.txt passed --check (rc=$rc)"

# ── ac7: missing spec.md, and a nonexistent dir ──
D7="$(mk_spec)"
rm "$D7/spec.md"
chk "$D7" >/dev/null 2>&1 && no "ac7: missing spec.md passed" || ok "ac7: missing spec.md fails"
chk "$D7-nope" >/dev/null 2>&1 && no "ac7: a nonexistent dir passed" || ok "ac7: a nonexistent dir fails"

# ── ac8 ──
bash -n "$NS" \
  && ok "ac8: new-spec.sh passes bash -n" \
  || no "ac8: bash -n fails on new-spec.sh"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
