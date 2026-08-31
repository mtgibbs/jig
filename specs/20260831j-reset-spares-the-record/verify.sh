#!/usr/bin/env bash
# Gate for 20260831j-reset-spares-the-record. Single-task spec: one gate, no pend.
# The fixture runs the REAL ralph-build.sh with a stub executor that litters and never
# goes green; bookkeeping is planted AFTER the fixture commit (untracked — a new spec's
# first run). Post-#26 hb_write recreates its OWN status file, so the planted one
# belongs to a different worker: nothing rewrites it, deletion is observable.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../.." && pwd -P)"
RB="$R/scripts/ralph-build.sh"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

# One-task per-task-layout fixture; gates red unless ok.txt says done.
mk_fx() {
  local d; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git -C "$d" init -q
  git -C "$d" config user.email fx@fx.invalid
  git -C "$d" config user.name fx
  mkdir -p "$d/specs/fx/tasks/T01-thing" "$d/.evidence"
  echo '# fx spec' > "$d/specs/fx/spec.md"
  echo 'T1: write done into ok.txt' > "$d/specs/fx/tasks.txt"
  # As in the real repo: run evidence is IGNORED, so the clean spares it via .gitignore.
  # The bookkeeping set must survive WITHOUT this crutch — nothing else is listed.
  printf '.evidence/runs/\n' > "$d/.gitignore"
  local gate='grep -q done "$(git rev-parse --show-toplevel)/ok.txt" 2>/dev/null || { echo "  FAIL  fx: ok.txt missing" >&2; exit 1; }; echo "  PASS  fx: ok.txt present"; exit 0'
  printf '#!/usr/bin/env bash\n%s\n' "$gate" > "$d/specs/fx/tasks/T01-thing/verify.sh"
  printf '#!/usr/bin/env bash\n%s\n' "$gate" > "$d/specs/fx/verify.sh"
  git -C "$d" add -A && git -C "$d" commit -qm fx >/dev/null
  printf '%s' "$d"
}

mk_stub() { # <body> -> path
  local s; s="$(mktemp)"; _FX="$_FX $s"
  printf '#!/usr/bin/env bash\n: "${ROOT:?}"\n%s\nprintf "stub transcript line %%d\\n" $(seq 1 40)\nexit 0\n' "$1" > "$s"
  printf '%s' "$s"
}

run_fx() { # <dir> <stub>
  local d="$1" s="$2"; shift 2
  ( cd "$d" && env -u HARNESS_REPORT_URL -u HARNESS_REPORT_TOKEN -u RALPH_ALLOW_MONOLITHIC \
      RALPH_SHEET=off RALPH_RETRIES=0 RALPH_EXEC_TIMEOUT=60 \
      RALPH_EXEC_CMD="bash $s" bash "$RB" specs/fx 2>&1 )
}

FX="$(mk_fx)"
# Untracked bookkeeping, planted after the commit — a new spec's first run.
mkdir -p "$FX/.evidence/status/fx/other-host"
echo '{"phase":"stopped","agent":"other"}' > "$FX/.evidence/status/fx/other-host/other.json"
echo '{"task":"T1","evidence":"planted"}'  > "$FX/.evidence/index-fx.jsonl"
echo '{"run":"r0","cost":0}'               > "$FX/.evidence/metrics.jsonl"

# The stub litters and never satisfies the gate: the attempt fails, the reset runs.
S_LITTER="$(mk_stub 'echo stray > "$ROOT/stray.txt"; mkdir -p "$ROOT/junkdir"; echo j > "$ROOT/junkdir/f.txt"')"
out="$(run_fx "$FX" "$S_LITTER")"; rc=$?

# ── ac1: another worker's status file survives the reset ──
[ -f "$FX/.evidence/status/fx/other-host/other.json" ] \
  && ok "ac1: another worker's status file survived the failure reset" \
  || no "ac1: the reset ate .evidence/status/fx/other-host/other.json — the record is gone"

# ── ac2: index and metrics survive ──
[ -f "$FX/.evidence/index-fx.jsonl" ] \
  && ok "ac2: the untracked index survived" \
  || no "ac2: .evidence/index-fx.jsonl was deleted"
[ -f "$FX/.evidence/metrics.jsonl" ] \
  && ok "ac2: untracked metrics survived" \
  || no "ac2: .evidence/metrics.jsonl was deleted"

# ── ac3: the clean still cleans — litter is removed (positive control) ──
[ -f "$FX/stray.txt" ] \
  && no "ac3: stray.txt survived — the excludes swallowed the clean" \
  || ok "ac3: litter file removed"
[ -d "$FX/junkdir" ] \
  && no "ac3: junkdir/ survived — -d lost or excludes too broad" \
  || ok "ac3: litter directory removed"

# ── ac4: the guard's own voice — no Removing .evidence, but the litter is announced ──
printf '%s' "$out" | grep -q 'Removing .evidence' \
  && no "ac4: the clean announced 'Removing .evidence/…' — bookkeeping was cleaned" \
  || ok "ac4: no 'Removing .evidence' in the run output"
printf '%s' "$out" | grep -q 'Removing stray.txt' \
  && ok "ac4: positive control — the clean announced removing the litter" \
  || no "ac4: 'Removing stray.txt' absent — the probe is not watching the clean at all"

# ── ac5: the failing run still fails (the reset path actually ran) ──
[ "$rc" -eq 2 ] \
  && ok "ac5: the run exited 2 (stop-needs-human)" \
  || no "ac5: expected exit 2, got $rc"

# ── ac6: one clean, shared by both paths ──
_n="$(grep -c 'clean -fd' "$RB")"
[ "$_n" -eq 1 ] \
  && ok "ac6: 'clean -fd' appears once — verify-failure and scope paths share the helper" \
  || no "ac6: 'clean -fd' appears $_n times — the reset is not single-sourced"

# ── ac7 ──
bash -n "$RB" \
  && ok "ac7: ralph-build.sh passes bash -n" \
  || no "ac7: bash -n fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
