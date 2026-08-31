#!/usr/bin/env bash
# Gate for 20260831k-scope-guard-diff-base. Single-task spec: one gate, no pend.
# Meta-gate: runs the four REAL legacy gates in throwaway clones and asserts only on
# their own scope line ('scope:out-of-scope-files-untouched') — the guard's voice.
# The clone's origin/main is pinned to the clone's HEAD, so the only history diff is
# the one the fixture commits; everything else the legacy gates do is their business.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../.." && pwd -P)"
. "$R/scripts/bound.sh"

GATES="20260818a-ralph-retry-contract 20260818b-loop-doctor 20260818c-run-regression-guard 20260818d-tasks-ledger"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

_FX=""
cleanup(){ for d in $_FX; do rm -rf "$d"; done; }
trap cleanup EXIT

mk_clone() { # -> path; origin/main pinned to HEAD so the fixture owns the whole diff
  local d s; d="$(mktemp -d)"; d="$(cd "$d" && pwd -P)"; _FX="$_FX $d"
  git clone -q --local "$R" "$d/repo" 2>/dev/null
  git -C "$d/repo" config user.email fx@fx.invalid
  git -C "$d/repo" config user.name fx
  # The clone carries COMMITTED state only; sync the four gates from the working tree and
  # commit, so the meta-gate blesses what this run is actually testing (red-before-green
  # would otherwise keep testing the old committed guards). Committed BEFORE the pin, so
  # the sync itself is not a diff the fixture sees.
  for s in $GATES; do cp "$R/specs/$s/verify.sh" "$d/repo/specs/$s/verify.sh"; done
  git -C "$d/repo" commit -qam 'fx: sync working-tree gates' >/dev/null 2>&1 || true
  git -C "$d/repo" update-ref refs/remotes/origin/main HEAD
  printf '%s' "$d/repo"
}

edit_out_of_scope() { # <clone> — touch a file from every legacy gate's forbidden list
  echo '# fx-scope-probe' >> "$1/scripts/ralph-build.sh"   # 20260818b's list
  echo '# fx-scope-probe' >> "$1/scripts/ralph-judge.sh"   # a/c/d's lists
  printf '\n<!-- fx-scope-probe -->\n' >> "$1/specs/TEMPLATE.md"
}

scope_line() { # <clone> <spec> [env k=v...] -> the gate's scope line (or empty)
  local d="$1" s="$2"; shift 2
  # ${1+"$@"}, not "$@": bash 3.2 under `set -u` treats an EMPTY "$@" as unbound and
  # kills the subshell — every probe then reads <missing>. Same trap _scope_violations hit.
  # bound WRAPS env, not the reverse: bound is a shell function and env(1) cannot exec one.
  ( cd "$d" && bound 180 env -u RETRY_BASE -u LOOP_DOCTOR_BASE -u RRG_BASE -u TL_BASE \
      ${1+"$@"} bash "specs/$s/verify.sh" 2>&1 ) \
    | grep 'scope:out-of-scope-files-untouched' | head -1
}

# ── ac1: committed out-of-scope edit, clean tree → no false fire on another spec's branch ──
CG="$(mk_clone)"
edit_out_of_scope "$CG"
git -C "$CG" commit -qam 'fx: another spec legitimately edits these' >/dev/null
for s in $GATES; do
  line="$(scope_line "$CG" "$s")"
  case "$line" in
    *PASS*) ok "ac1: $s clears a committed edit on a clean tree" ;;
    *)      no "ac1: $s fired on another branch's committed work — line: ${line:-<missing>}" ;;
  esac
done

# ── ac2: the SAME edit uncommitted → every guard still fires (teeth) ──
CD="$(mk_clone)"
edit_out_of_scope "$CD"
for s in $GATES; do
  line="$(scope_line "$CD" "$s")"
  case "$line" in
    *FAIL*) ok "ac2: $s fires on a dirty out-of-scope tree" ;;
    *)      no "ac2: $s did NOT fire on a dirty tree — the guard lost its teeth: ${line:-<missing>}" ;;
  esac
done

# ── ac3: the env override still buys the history audit ──
line="$(scope_line "$CG" 20260818b-loop-doctor LOOP_DOCTOR_BASE=origin/main)"
case "$line" in
  *FAIL*) ok "ac3: LOOP_DOCTOR_BASE=origin/main still audits committed history" ;;
  *)      no "ac3: the explicit base override no longer fires: ${line:-<missing>}" ;;
esac

# ── ac4: the default is gone from all four files ──
if grep -l ':-origin/main}' $(for s in $GATES; do echo "$R/specs/$s/verify.sh"; done) 2>/dev/null | grep -q .; then
  no "ac4: an origin/main default remains: $(grep -l ':-origin/main}' $(for s in $GATES; do echo "$R/specs/$s/verify.sh"; done) 2>/dev/null | tr '\n' ' ')"
else
  ok "ac4: no gate defaults its diff base to origin/main"
fi

# ── ac5 ──
_syn=0
for s in $GATES; do bash -n "$R/specs/$s/verify.sh" || _syn=1; done
[ "$_syn" -eq 0 ] && ok "ac5: all four gates pass bash -n" || no "ac5: bash -n fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
