#!/usr/bin/env bash
# new-spec.sh — scaffold a spec in the canonical per-task shape, or validate one.
#
#   scripts/new-spec.sh [--root <repo-root>] [--id <YYYYMMDD><letter>] <spec-slug> <task-slug>...
#   scripts/new-spec.sh [--root <repo-root>] --check <spec-dir>
#
# Create mode lays out specs/<id>-<spec-slug>/ with one tasks/T<NN>-<slug>/verify.sh per
# task slug — EVERY spec gets tasks/, single-task included (directed 2026-08-31: the shape
# does not change with the task count, and there is no monolithic shape to fall back to).
# The emitted task gates are stubs that FAIL until authored: red by construction, so the
# first gate run is the red evidence, never a green lie. The spec-level verify.sh is
# convergence-only.
#
# --check validates a spec dir against the same shape and exits non-zero on any violation.
# It is stricter than the loop on one point BY DESIGN: the loop still tolerates a legacy
# single-task spec without tasks/ (those ~30 specs are done and only re-run directly);
# --check judges NEW work, where that shape is not authored any more.
#
# bash 3.2 floor (macOS): no arrays, no declare -A, no ${var,,}.
set -uo pipefail

usage() {
  echo "usage: new-spec.sh [--root <repo-root>] [--id <YYYYMMDD><letter>] <spec-slug> <task-slug>..." >&2
  echo "       new-spec.sh [--root <repo-root>] --check <spec-dir>" >&2
}
die() { echo "new-spec: $*" >&2; exit 1; }

_slug_ok() { printf '%s' "$1" | grep -Eq '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'; }

# _has_bare_word_pend <file> — true if the banned staging verb appears as code (comments
# stripped first — a gate ALLOWED to talk about the ban must not trip it: Trap A, scoped).
# The probe string is built by concatenation so this script never contains it either.
_PW="pe""nd"
_has_bare_word_pend() {
  sed 's/#.*//' "$1" | grep -Eq "(^|[^[:alnum:]_])${_PW}([^[:alnum:]_]|\$)"
}

# check_spec <dir> — validate the per-task shape; FAIL lines to stderr, rc 1 on any.
check_spec() {
  local d bad n nd i td line k
  d="$1"; bad=0
  [ -d "$d" ] || { echo "  FAIL  check: no such spec dir: $d" >&2; return 1; }
  d="$(cd "$d" && pwd -P)"
  [ -s "$d/spec.md" ]   || { echo "  FAIL  check: spec.md missing or empty" >&2; bad=1; }
  [ -f "$d/verify.sh" ] || { echo "  FAIL  check: spec-level verify.sh missing" >&2; bad=1; }
  [ -d "$d/evidence" ]  || { echo "  FAIL  check: evidence/ missing (red-before-green lives there)" >&2; bad=1; }
  if [ ! -f "$d/tasks.txt" ]; then
    echo "  FAIL  check: tasks.txt missing" >&2
    echo "VERIFY: shape violations above" >&2; return 1
  fi
  n="$(grep -c '^T[0-9]' "$d/tasks.txt")"
  [ "$n" -ge 1 ] || { echo "  FAIL  check: tasks.txt has no T-lines" >&2; bad=1; }
  if [ ! -d "$d/tasks" ]; then
    echo "  FAIL  check: no tasks/ directory — EVERY spec carries per-task gates, single-task included; there is no monolithic shape and no override" >&2
    bad=1
  else
    # tasks.txt numbering must be contiguous from T1 — a renumbered or duplicated line
    # silently detaches gates from tasks.
    k=0
    while IFS= read -r line; do
      case "$line" in
        T[0-9]*)
          k=$((k+1))
          case "$line" in
            "T$k:"*) : ;;
            *) echo "  FAIL  check: tasks.txt T-line $k reads '$line' — expected it to start 'T$k:'" >&2; bad=1 ;;
          esac ;;
      esac
    done < "$d/tasks.txt"
    i=1
    while [ "$i" -le "$n" ]; do
      td="$(ls -d "$d/tasks/T$(printf '%02d' "$i")"-* 2>/dev/null | head -1)"
      if [ -z "$td" ]; then
        echo "  FAIL  check: task $i has no tasks/T$(printf '%02d' "$i")-<slug>/ dir" >&2; bad=1
      elif [ ! -f "$td/verify.sh" ]; then
        echo "  FAIL  check: $td has no verify.sh" >&2; bad=1
      elif [ ! -x "$td/verify.sh" ]; then
        echo "  FAIL  check: $td/verify.sh is not executable" >&2; bad=1
      elif _has_bare_word_pend "$td/verify.sh"; then
        echo "  FAIL  check: '$_PW' appears as code in $td/verify.sh — banned from task gates (nothing later exists to defer to)" >&2; bad=1
      fi
      i=$((i+1))
    done
    nd="$(ls -d "$d/tasks/T"[0-9][0-9]-* 2>/dev/null | wc -l | tr -d ' ')"
    [ "$nd" -eq "$n" ] 2>/dev/null \
      || { echo "  FAIL  check: $nd task dirs for $n tasks.txt T-lines — orphan or missing dirs" >&2; bad=1; }
  fi
  if [ -f "$d/verify.sh" ] && _has_bare_word_pend "$d/verify.sh"; then
    echo "  FAIL  check: '$_PW' appears as code in the spec-level verify.sh — convergence defers to nothing" >&2; bad=1
  fi
  if [ "$bad" -eq 0 ]; then echo "check: $d matches the per-task shape"; return 0; fi
  echo "VERIFY: shape violations above" >&2
  return 1
}

# ── arg parsing ──────────────────────────────────────────────────────────────────────────
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd -P)"
ID=""
CHECK=""
SPEC_SLUG=""
TASK_SLUGS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --root)  [ $# -ge 2 ] || { usage; die "--root needs a value"; }
             ROOT_DIR="$(cd "$2" 2>/dev/null && pwd -P)" || die "--root: no such dir: $2"; shift 2 ;;
    --id)    [ $# -ge 2 ] || { usage; die "--id needs a value"; }; ID="$2"; shift 2 ;;
    --check) [ $# -ge 2 ] || { usage; die "--check needs a spec dir"; }; CHECK="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) usage; die "unknown option: $1" ;;
    *)  if [ -z "$SPEC_SLUG" ]; then SPEC_SLUG="$1"; else TASK_SLUGS="$TASK_SLUGS $1"; fi; shift ;;
  esac
done

if [ -n "$CHECK" ]; then
  check_spec "$CHECK"
  exit $?
fi

# ── create mode ──────────────────────────────────────────────────────────────────────────
[ -n "$SPEC_SLUG" ] || { usage; die "a spec slug is required"; }
[ -n "$TASK_SLUGS" ] || die "at least one task slug is required — EVERY spec carries tasks/, single-task included; there is no monolithic shape"
_slug_ok "$SPEC_SLUG" || die "bad spec slug '$SPEC_SLUG' (lowercase [a-z0-9-], no leading/trailing dash)"
for s in $TASK_SLUGS; do
  _slug_ok "$s" || die "bad task slug '$s' (lowercase [a-z0-9-], no leading/trailing dash)"
done

SPECS="$ROOT_DIR/specs"
[ -d "$SPECS" ] || die "no specs/ dir under $ROOT_DIR (wrong --root?)"

if [ -z "$ID" ]; then
  today="$(date +%Y%m%d)"
  for L in a b c d e f g h i j k l m n o p q r s t u v w x y z; do
    ls -d "$SPECS/$today$L"-* >/dev/null 2>&1 && continue
    ID="$today$L"; break
  done
  [ -n "$ID" ] || die "all 26 spec ids for $today are taken"
else
  printf '%s' "$ID" | grep -Eq '^[0-9]{8}[a-z]$' || die "bad --id '$ID' (want YYYYMMDD plus one lowercase letter)"
  ls -d "$SPECS/$ID"-* >/dev/null 2>&1 && die "id $ID is already taken"
fi

DIR="$SPECS/$ID-$SPEC_SLUG"
[ -e "$DIR" ] && die "$DIR already exists"

mkdir -p "$DIR/evidence"
: > "$DIR/tasks.txt"
i=0
for s in $TASK_SLUGS; do
  i=$((i+1))
  nn="$(printf '%02d' "$i")"
  td="$DIR/tasks/T$nn-$s"
  mkdir -p "$td"
  echo "T$i: TODO — $(printf '%s' "$s" | tr '-' ' ') (rewrite: semantically rich, this task's deliverables only)" >> "$DIR/tasks.txt"
  cat > "$td/verify.sh" <<EOF
#!/usr/bin/env bash
# Gate for T$nn-$s ($ID-$SPEC_SLUG). RED BY CONSTRUCTION: this stub fails until it is
# replaced with the task's real acceptance checks. Author the checks FIRST, run them red,
# capture evidence/red-before-green.txt, and only then build the deliverable.
set -uo pipefail
echo "  FAIL  T$nn-$s: gate is an unwritten stub — author this task's acceptance checks" >&2
exit 1
EOF
  chmod +x "$td/verify.sh"
done

cat > "$DIR/verify.sh" <<EOF
#!/usr/bin/env bash
# Convergence gate for $ID-$SPEC_SLUG: runs every task gate in order and owns no checks
# of its own beyond end-state convergence. Nothing is staged for later here.
set -uo pipefail
T="\$(cd "\$(dirname "\$0")" && pwd -P)"
fail=0
for g in "\$T"/tasks/T*/verify.sh; do
  echo "── \$(basename "\$(dirname "\$g")") ──"
  bash "\$g" || fail=1
done
[ "\$fail" -eq 0 ] && { echo "VERIFY: all task gates passed"; exit 0; }
echo "VERIFY: task-gate failures above" >&2
exit 1
EOF
chmod +x "$DIR/verify.sh"

cat > "$DIR/spec.md" <<EOF
# Spec: $ID-$SPEC_SLUG

<!-- Scaffolded by scripts/new-spec.sh — fill every section per specs/TEMPLATE.md.
     The task gates under tasks/ are failing stubs ON PURPOSE: author each task's real
     checks, run them RED (capture evidence/red-before-green.txt), then build to green. -->

- **Status:** Draft v0.1
- **Owner:** <name>
- **Constitution:** \`specs/constitution.md\` + \`specs/amendments.md\`
- **Touches:** <the files/paths this will change>
- **Tools:** none
- **MCP:** none

## 1. Why · [R — Requirements]

## 2. Outcomes (Definition of Done) · [R — Requirements]

## 9. Task breakdown · [O — Operations]
<!-- One entry per tasks.txt line. A task's anchor section holds ONLY that task's own
     deliverables (specs/TEMPLATE.md §"Task granularity"). -->

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

## 11. Verification — the gates
<!-- Per-task: tasks/T<NN>-<slug>/verify.sh, run cumulatively 1..N by the loop; the
     spec-level verify.sh is convergence-only. See specs/TEMPLATE.md §11. -->
EOF

check_spec "$DIR" >/dev/null 2>&1 || die "internal error: the scaffold does not pass its own --check"

echo "new-spec: scaffolded $DIR"
echo "  tasks: $(grep -c '^T[0-9]' "$DIR/tasks.txt") — rewrite each tasks.txt line to be semantically rich"
echo "  next:  1) fill spec.md   2) author each tasks/T<NN>-*/verify.sh red-first"
echo "         3) capture evidence/red-before-green.txt   4) build until green"
