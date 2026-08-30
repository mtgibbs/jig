#!/usr/bin/env bash
# specs/20260827a-spec-manifest/verify.sh — the deterministic gate for "a spec declares what it needs,
# and the loop refuses to start without it".
#
# FUNCTIONAL. It builds fixture spec.md files and runs the REAL reader and the REAL run-loop.sh
# against them. It never greps run-loop.sh for a word: four consecutive specs shipped a check
# that passed because the word it searched for was already in a comment (TEMPLATE.md §11 Trap A).
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

FIELD="$R/scripts/spec-field.sh"
RUNLOOP="$R/scripts/run-loop.sh"
TEMPLATE="$R/specs/TEMPLATE.md"
SELF="$R/specs/20260827a-spec-manifest/spec.md"

# ── SCOPE AND LITTER — FIRST, AND FATAL ────────────────────────────────────────────────────
[ -r "$RUNLOOP" ] || { echo "  FAIL  scope: scripts/run-loop.sh missing" >&2; exit 1; }
bash -n "$RUNLOOP" 2>/dev/null || { echo "  FAIL  scope: run-loop.sh is not valid bash" >&2; exit 1; }
[ -r "$SELF" ] || { echo "  FAIL  scope: this spec's own spec.md is missing" >&2; exit 1; }
ok "scope: run-loop.sh and this spec exist and parse"

_stray="$(find "$R/specs/20260827a-spec-manifest" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence \
          2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

# No spec that PREDATES this one may gain a declaration (spec §4, §5 out-of-scope).
#
# Named explicitly, and deliberately not `specs/*`. The original form forbade a declaration in
# EVERY spec but this one, which reads as scope discipline and is in fact a permanent ban on
# adopting the grammar this spec exists to introduce: the first spec to declare `Tools:` — the
# feature working as designed — failed the gate. `specs/20260827b-fleet-run-key` is what found it.
# The guard's intent is "this change did not retrofit declarations onto the specs that already
# existed", and that set is finite and known, so it is written down rather than inferred.
_PREDATING="20260825a-evidence-convention 20260826a-evidence-replayable 20260825b-evidence-spec-nesting
20260825c-executor-binding 20260802a-judge-loop 20260818b-loop-doctor
20260810a-loop-report 20260818a-ralph-retry-contract 20260818c-run-regression-guard
20260801a-scored-gate 20260818d-tasks-ledger"
_leaked=""
for _s in $_PREDATING; do
  [ -f "$R/specs/$_s/spec.md" ] || continue
  grep -q '^- \*\*Tools:\*\*' "$R/specs/$_s/spec.md" 2>/dev/null && _leaked="$_leaked $_s"
done
[ -n "$_leaked" ] && no "scope: a pre-existing spec gained a declaration —$_leaked" \
                  || ok "scope: no spec predating this one was given a declaration"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT INT TERM

# ── FIXTURES ───────────────────────────────────────────────────────────────────────────────
# Every fixture is a real spec dir: run-loop.sh's own preflight demands spec.md + verify.sh.
mkfix() {  # mkfix <name> <header-lines-or-empty>
  d="$T/specs/$1"; mkdir -p "$d"
  { printf '# Spec: fixture %s\n\n' "$1"
    [ -n "${2:-}" ] && printf '%s\n' "$2"
    printf '\n---\n\n## body\n\n'
    # BELOW the rule and inside a fence: prose about the grammar, never a declaration.
    printf '```markdown\n- **Tools:** ghost-tool\n```\n'
  } > "$d/spec.md"
  printf '#!/usr/bin/env bash\necho "  PASS  fixture"\n' > "$d/verify.sh"
  # NO tasks.txt, deliberately. run-loop.sh's build phase checks for it (run-loop.sh:54) and
  # exits 1 when it is absent — AFTER the preflight and BEFORE any executor. That gives the
  # probe two distinguishable outcomes (1 = preflight passed, 3 = preflight rejected) without
  # ever starting a model.
  chmod +x "$d/verify.sh"
  printf '%s' "$d"
}

GHOST="__no_such_binary_$$__"
F_NONE="$(mkfix nodecl "")"
F_OK="$(mkfix present   "- **Tools:** sh")"
F_MISS="$(mkfix missing "- **Tools:** $GHOST")"
F_MULTI="$(mkfix multi  "- **Tools:** $GHOST, ${GHOST}2")"
F_NONEVAL="$(mkfix explicitnone "- **Tools:** none")"
F_PERM="$(mkfix perms   "- **Permissions:** write:x/**, exec:git")"
F_MCP="$(mkfix mcp      "- **MCP:** homelab")"

# ── T1 · the reader ────────────────────────────────────────────────────────────────────────
if [ -x "$FIELD" ]; then
  out="$(bash "$FIELD" "$SELF" Tools 2>/dev/null)"; rc=$?
  if [ "$rc" = 0 ] && [ "$(printf '%s\n' "$out" | tr '\n' ' ')" = "git sed " ]; then
    ok "ac1: reader splits on commas and strips whitespace (this spec declares: git, sed)"
  else
    no "ac1: reading Tools from this spec gave rc=$rc [$(printf '%s' "$out" | tr '\n' '/')], expected git/sed"
  fi

  if [ -n "$out" ] && [ "$(bash "$FIELD" "$SELF" Tools 2>/dev/null | wc -l | tr -d ' ')" = 2 ]; then
    ok "ac1: each value is a complete line, trailing newline included (a while-read consumer is safe)"
  else
    no "ac1: the reader's last value has no trailing newline — a while-read consumer drops it, and the preflight is one"
  fi

  # AC-3/AC-14 — the fence below the rule is prose. This spec's §3.1 declares jq and swift
  # inside one; a whole-file parser reports them and fails its own gate.
  if printf '%s\n' "$out" | grep -qx 'jq\|swift'; then
    no "ac3/ac14: the reader read a declaration out of a fenced code block below the --- rule"
  else
    ok "ac3/ac14: declarations inside a fence below the rule are ignored"
  fi
  # …and the same assertion against a fixture built for it, so this does not depend on §3.1 surviving edits.
  gout="$(bash "$FIELD" "$F_NONE/spec.md" Tools 2>/dev/null)"; grc=$?
  if [ "$grc" = 1 ] && [ -z "$gout" ]; then
    ok "ac2/ac3: an absent key exits 1 and prints nothing (the fixture's only Tools line is fenced)"
  elif printf '%s' "$gout" | grep -q ghost-tool; then
    no "ac3: the reader found 'ghost-tool' — it is inside a fence below the rule"
  else
    no "ac2: an absent key gave rc=$grc [$gout], expected rc=1 and no output"
  fi

  bash "$FIELD" "$F_NONEVAL/spec.md" Tools >/dev/null 2>&1 \
    && ok "ac2: an explicit 'none' exits 0 — declares-none is not declares-nothing" \
    || no "ac2: 'Tools: none' exited nonzero; absent and none must be distinguishable"

  bash "$FIELD" "$T/does-not-exist.md" Tools >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && ok "ac4: an unreadable spec exits 2, never degrading to declares-nothing" \
                || no "ac4: unreadable spec exited $rc, expected 2"
  bash "$FIELD" >/dev/null 2>&1; rc=$?
  [ "$rc" = 2 ] && ok "ac4: a missing argument exits 2" || no "ac4: missing argument exited $rc, expected 2"

  lst="$(bash "$FIELD" "$SELF" --list 2>/dev/null)"
  if printf '%s\n' "$lst" | grep -qx 'Tools' && printf '%s\n' "$lst" | grep -qx 'Permissions'; then
    ok "ac5: --list enumerates the declared keys"
  else
    no "ac5: --list did not enumerate Tools and Permissions [$(printf '%s' "$lst" | tr '\n' '/')]"
  fi
else
  for a in ac1 ac2 ac3 ac4 ac5 ac14; do pend "$a: scripts/spec-field.sh"; done
fi

# ── T2 · the documented grammar ────────────────────────────────────────────────────────────
if [ -r "$TEMPLATE" ] && grep -q 'Permissions' "$TEMPLATE" 2>/dev/null; then
  # The distinction is the point of the doc task, so assert the DISTINCTION, not the word.
  if grep -qi 'not verified\|recorded only\|unenforced' "$TEMPLATE"; then
    ok "ac12: TEMPLATE.md states that Permissions is recorded, not verified"
  else
    no "ac12: TEMPLATE.md names Permissions without saying it is unenforced — that is the field looking checked"
  fi
else
  pend "ac12: the grammar documented in TEMPLATE.md"
fi

# ── T3 · the preflight. Probed BEHAVIOURALLY: run the real run-loop.sh against fixtures. ────
# It is invoked from a scratch git repo on a non-main branch, because its existing preflight
# refuses main — and that refusal must keep working.
WT="$T/wt"; mkdir -p "$WT"
git -C "$WT" init -q 2>/dev/null
git -C "$WT" config user.email g@example.invalid; git -C "$WT" config user.name g
printf 'x\n' > "$WT/f"; git -C "$WT" add f 2>/dev/null; git -C "$WT" commit -qm base 2>/dev/null
git -C "$WT" checkout -q -b throwaway 2>/dev/null

# The REAL strategy, because LOOPS_DIR is hardcoded at run-loop.sh:14 and is not read from the
# environment — a scratch strategy dir would silently never load, and every behavioural check
# below would pass while measuring nothing (Trap A-prime: a scope that was written and was inert).
runloop() {  # runloop <spec-dir>; sets $RL_OUT, returns run-loop.sh's exit code
  RL_OUT="$(cd "$WT" && RALPH_EXEC_CMD="$R/scripts/exec-opencode.sh" \
            bash "$RUNLOOP" build-converge "$1" 2>&1)"
  return $?
}

# Prove the probe can distinguish before trusting it: an undeclared fixture must reach the build
# phase and stop at its missing-tasks check. If this is not 1, every rc comparison below is noise.
runloop "$F_NONE"; _probe=$?
[ "$_probe" = 1 ] \
  && ok "control: the probe reaches the build phase on a clean preflight (rc=1, no executor run)" \
  || no "control: an undeclared fixture gave rc=$_probe, expected 1 — the probe cannot tell pass from reject"

# Is the preflight built? Probe by BEHAVIOUR — a declared-missing tool must be rejected.
runloop "$F_MISS"; miss_rc=$?
if [ "$miss_rc" = 3 ]; then
  ok "ac6: a declared tool that is absent exits 3 before any phase runs"
  printf '%s' "$RL_OUT" | grep -q "$GHOST" \
    && ok "ac6: the failure names the missing tool" \
    || no "ac6: exit 3 without naming '$GHOST' — that is a symptom, not a cause"
  printf '%s' "$RL_OUT" | grep -q 'spec.md' \
    && ok "ac6: the failure names the spec that declared it" \
    || no "ac6: the failure does not name the declaring spec file"

  # CONTROL (Trap B): a preflight that rejects EVERYTHING also produces exit 3. A tool that is
  # certainly present must produce a different outcome, or the assertion above measures nothing.
  runloop "$F_OK"; okrc=$?
  [ "$okrc" != 3 ] \
    && ok "control: a declared tool that IS present does not exit 3 (rc=$okrc) — ac6 discriminates" \
    || no "control: 'Tools: sh' also exits 3 — the preflight rejects everything and ac6 proves nothing"

  runloop "$F_MULTI"; mrc=$?
  n=0
  printf '%s' "$RL_OUT" | grep -q "${GHOST}2" && n=$((n+1))
  printf '%s' "$RL_OUT" | grep -q "$GHOST"    && n=$((n+1))
  [ "$mrc" = 3 ] && [ "$n" = 2 ] \
    && ok "ac7: every missing tool is named in one run, not just the first" \
    || no "ac7: two missing tools produced rc=$mrc naming $n of 2"

  runloop "$F_NONEVAL"; nrc=$?
  [ "$nrc" != 3 ] && ok "ac8: 'Tools: none' proceeds" || no "ac8: 'Tools: none' was rejected"

  runloop "$F_NONE"; zrc=$?
  [ "$zrc" != 3 ] && ok "ac9: a spec with no declaration proceeds, as it did at 8fa87e3" \
                  || no "ac9: an undeclared spec is now rejected — the change is not additive"

  runloop "$F_PERM"; prc=$?
  if [ "$prc" != 3 ]; then
    if printf '%s' "$RL_OUT" | grep -qi 'not verified\|recorded'; then
      ok "ac12: declared Permissions are printed under a not-verified label"
    else
      no "ac12: Permissions printed (or not) without saying they are unverified"
    fi
  else
    no "ac12: a Permissions declaration must never fail the preflight (rc=$prc)"
  fi

  # AC-10 — a declared MCP requires the executor's config in the worktree.
  # The gate does NOT know which file that is, and must not: the path is derived from the
  # binding (AC-11). So it learns the name FROM THE ERROR MESSAGE, which AC-10 requires the
  # preflight to print anyway — then creates that file and asserts the rejection lifts. A gate
  # that hardcoded `opencode.json` here would be asserting the very thing AC-11 forbids.
  runloop "$F_MCP"; mrc10=$?
  if [ "$mrc10" != 3 ]; then
    no "ac10: 'MCP: homelab' with no executor config gave rc=$mrc10, expected 3"
  else
    cfg="$(printf '%s' "$RL_OUT" | grep -o '[A-Za-z0-9._-]*\.json' | head -1)"
    if [ -z "$cfg" ]; then
      no "ac10: exit 3 without naming the config file it wants — that is a symptom, not a cause"
    else
      ok "ac10: a declared MCP with no executor config exits 3, naming $cfg"
      printf '{}\n' > "$WT/$cfg"
      runloop "$F_MCP"; lift=$?
      rm -f "$WT/$cfg"
      [ "$lift" != 3 ] \
        && ok "control: creating $cfg lifts the rejection (rc=$lift) — ac10 checks the config, not the MCP key" \
        || no "control: creating $cfg did not lift the rejection — ac10 rejects any MCP declaration and proves nothing"
    fi
  fi

  # AC-11 — the config path is derived, not hardcoded. Asserted on CODE with comments stripped,
  # because the literal's ABSENCE is the requirement and no fixture can exhibit it.
  if sed 's/#.*//' "$RUNLOOP" | grep -q 'opencode\.json'; then
    no "ac11: run-loop.sh hardcodes opencode.json — a codex or container binding cannot satisfy it"
  else
    ok "ac11: no hardcoded opencode.json in run-loop.sh"
  fi

  # AC-13 — a failing preflight mutates nothing.
  before="$(find "$F_MISS" -type f -exec wc -c {} + 2>/dev/null | sort)"
  runloop "$F_MISS" || true
  after="$(find "$F_MISS" -type f -exec wc -c {} + 2>/dev/null | sort)"
  [ "$before" = "$after" ] && ok "ac13: a failing preflight created, modified and deleted nothing" \
                           || no "ac13: the fixture spec dir changed across a failing preflight"
else
  pend "ac6: the run-loop.sh preflight"
  for a in ac7 ac8 ac9 ac10 ac11 ac12 ac13; do pend "$a: the run-loop.sh preflight"; done
fi

# The existing main-branch refusal must survive the edit. Always armed — it is a regression
# guard on behaviour that already works, not a staged deliverable.
# From a scratch repo whose branch really is `main`. Running this from $R would have proved
# nothing: $R is a worktree on spec/spec-manifest, so the refusal could never have fired.
MW="$T/wtmain"; mkdir -p "$MW"
git -C "$MW" init -q 2>/dev/null
git -C "$MW" config user.email g@example.invalid; git -C "$MW" config user.name g
printf 'x\n' > "$MW/f"; git -C "$MW" add f 2>/dev/null; git -C "$MW" commit -qm base 2>/dev/null
git -C "$MW" branch -M main 2>/dev/null
mrc_out="$(cd "$MW" && bash "$RUNLOOP" build-converge "$F_NONE" 2>&1)"; mrc=$?
if [ "$mrc" != 0 ] && printf '%s' "$mrc_out" | grep -qi 'main\|worktree'; then
  ok "regression: run-loop.sh still refuses to run on main"
else
  no "regression: run-loop.sh no longer refuses main (rc=$mrc) — the preflight edit broke it"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
