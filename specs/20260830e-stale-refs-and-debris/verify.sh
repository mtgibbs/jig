#!/usr/bin/env bash
# specs/20260830e-stale-refs-and-debris/verify.sh — the deterministic gate for "stale
# references, root debris, LICENSE — the neglect-signal sweep".
#
# THE GATE IS THE DELIVERABLE. Issue #74 v0.1 hand-enumerated seven dangling references;
# one resolved itself when an unrelated spec landed, two were retired by the constitution
# split, and this gate's first dry run found three the list never had. A hand-maintained
# enumeration is stale the moment another spec merges; the resolver below stays true on
# its own, and the spec's list is its expected output, not its specification.
#
# THE THREE-VERDICT CONTRACT: ok / no / pend; STRICT=1 promotes every pend. An artifact
# that does not exist yet (LICENSE, CONTRIBUTING.md, the imported research doc, the
# renamed spec dir, .evidence/README.md) reads `pend`. An artifact that exists and is
# wrong (a dangling citation, a `.env` strategy line, root tasks/ debris, the slug
# collision) is `no` outright.
#
# Trap discipline (TEMPLATE §11): every absence assertion here carries a POSITIVE
# CONTROL — the resolver must flag a planted bogus path and the `.env` probe must fire
# on a planted fixture before their clean results count (Trap B). The extraction must
# collect at least MIN_PATHS real references, asserted numerically — a regex that
# silently matches nothing passes every link check ever written (Trap A-prime; the
# threshold is hard per issue #74's research, not merely "non-degenerate").
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

_stray="$(find "$R/specs/20260830e-stale-refs-and-debris" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name evidence 2>/dev/null | head -3)"
[ -n "$_stray" ] && no "scope: unexpected files in the spec dir — $_stray" \
                 || ok "scope: spec dir holds only its own artifacts"

T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
trap 'rm -rf "$T"' EXIT

# ── AC1 · every backticked repo path in README + docs resolves, or is marked external ──────
# Corpus: README.md and docs/**/*.md — the files a stranger reads. Extraction mirrors
# 20260830c's AC2 (same token shape, same placeholder filter) with two refinements paid
# for by the dry run: `pi-cluster/`-prefixed paths are the explicit external-repo marker
# (exempt), and the run-artifact names a loop writes into a worktree (`spec.md`,
# `plan.md`, `tasks.txt`, `review.md`) are prose, not repo paths. A path may resolve
# from the repo root, from docs/, or from the citing doc's own directory.
MIN_PATHS=20
PATH_RE='^/?([A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+\.(md|sh|txt|py|mjs|yaml|yml|html|conf|json|service)$|^/?[A-Za-z0-9_.-]+\.md$'
collect(){ # $1 = file — emit its backticked path-shaped tokens, one per line, filtered
  grep -o '`[^`]*`' "$1" 2>/dev/null | tr -d '\`' \
    | grep -E "$PATH_RE" | grep -v '[<>*{}$]' \
    | grep -v '^pi-cluster/' | grep -vE '^(spec|plan|tasks|review)\.(md|txt)$' | sort -u
}
resolve(){ # $1 = citing doc, $2 = path — 0 if it resolves anywhere legitimate
  _q="${2#/}"
  [ -e "$R/$_q" ] || [ -e "$R/docs/$_q" ] || [ -e "$(dirname "$1")/$_q" ]
}

# Positive control (Trap B): the probe must flag a planted bogus path via the SAME
# collect+resolve pair, or a clean sweep below proves nothing.
printf 'see `docs/this-file-does-not-exist.md` for details\n' > "$T/fixture.md"
_ctl=""
while IFS= read -r p; do resolve "$T/fixture.md" "$p" || _ctl="$p"; done <<EOF
$(collect "$T/fixture.md")
EOF
[ -n "$_ctl" ] && ok "ac1: positive control — the resolver flags a planted bogus path" \
              || no "ac1: positive control FAILED — the resolver cannot flag anything, so a clean sweep is meaningless"

_dangling=""; _count=0
for doc in "$R/README.md" $(find "$R/docs" -name '*.md' 2>/dev/null | sort); do
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    _count=$((_count + 1))
    resolve "$doc" "$p" || _dangling="$_dangling ${doc#"$R"/}:$p"
  done <<EOF
$(collect "$doc")
EOF
done
[ -n "$_dangling" ] && no "ac1: dangling references —$_dangling" \
                    || ok "ac1: every backticked repo path in README + docs resolves or is marked external"
[ "$_count" -ge "$MIN_PATHS" ] \
  && ok "ac1: control — extraction collected $_count path refs (threshold $MIN_PATHS)" \
  || no "ac1: control — extraction collected only $_count refs (< $MIN_PATHS); the filter went inert and ac1 proves nothing"

# ── AC2 · no doc describes a strategy file as `.env` ───────────────────────────────────────
# Strategies resolve as scripts/loops/<name>.conf since 20260828c; a doc teaching `.env`
# teaches the first thing a reader tries to fail. Probe is anchored on `loops/…\.env` so
# a historical mention of the bare extension (the rename's own story) stays legal.
ENV_RE='loops/[^` ]*\.env'
printf 'a strategy is `scripts/loops/<name>.env` here\n' > "$T/envfix.md"
grep -qE "$ENV_RE" "$T/envfix.md" \
  && ok "ac2: positive control — the .env probe fires on a planted fixture" \
  || no "ac2: positive control FAILED — the .env probe cannot fire"
_env="$(grep -rnE "$ENV_RE" "$R/README.md" "$R/docs" 2>/dev/null | head -3)"
[ -n "$_env" ] && no "ac2: a doc still describes strategies as .env — $(printf '%s' "$_env" | tr '\n' ' ' | cut -c1-160)" \
               || ok "ac2: no doc describes a strategy file with a .env extension"

# ── AC3 · the four script-docstring citations resolve or carry the external marker ─────────
# Scripts are not in AC1's corpus (their comments cite runtime artifacts a resolver can't
# judge), so the four known citation defects are pinned individually.
if [ -f "$R/.evidence/README.md" ]; then
  grep -q '\.harness' "$R/.evidence/README.md" && grep -q 'slug' "$R/.evidence/README.md" \
    && ok "ac3: .evidence/README.md exists and documents the \$HOME-fallback timers and slug keying loop-index.py cites" \
    || no "ac3: .evidence/README.md exists but doesn't document what loop-index.py cites it for (~/.harness timers, spec-slug keying)"
else
  pend "ac3: .evidence/README.md (cited by scripts/loop-index.py)"
fi
if grep -q 'scripts/README\.md' "$R/scripts/ralph-judge-exec-qwen.sh"; then
  no "ac3: ralph-judge-exec-qwen.sh still cites scripts/README.md, which does not exist"
elif grep -q 'exec-opencode\.sh' "$R/scripts/ralph-judge-exec-qwen.sh"; then
  ok "ac3: ralph-judge-exec-qwen.sh cites scripts/exec-opencode.sh for Keychain-first key resolution"
else
  no "ac3: ralph-judge-exec-qwen.sh cites nothing that exists for key resolution"
fi
for s in ralph-bus.sh agent-bus-bootstrap; do
  _bare="$(grep -n 'docs/agent-bus\.md' "$R/scripts/$s" | grep -v 'pi-cluster/docs/agent-bus\.md' | head -2)"
  if [ -n "$_bare" ]; then
    no "ac3: scripts/$s cites docs/agent-bus.md without the pi-cluster/ external marker — $(printf '%s' "$_bare" | tr '\n' ' ' | cut -c1-100)"
  elif grep -q 'pi-cluster/docs/agent-bus\.md' "$R/scripts/$s"; then
    ok "ac3: scripts/$s marks its agent-bus.md citation external (pi-cluster/)"
  else
    no "ac3: scripts/$s no longer cites agent-bus.md at all — the runbook pointer was load-bearing, restore it with the marker"
  fi
done

# ── AC4 · the codesheet evidence is importable-checked, not a bare external claim ──────────
# Seven files cite docs/research/codemap-serena-token-efficiency.md as a bare repo path,
# and it backs the README's 20–56% claim (783 trials). OQ2 resolved import.
if [ -f "$R/docs/research/codemap-serena-token-efficiency.md" ]; then
  grep -q '783' "$R/docs/research/codemap-serena-token-efficiency.md" \
    && grep -qi 'pi-cluster' "$R/docs/research/codemap-serena-token-efficiency.md" \
    && ok "ac4: the codesheet research doc is imported, carries the 783-trial evidence and its provenance" \
    || no "ac4: docs/research/codemap-serena-token-efficiency.md exists but lacks the 783-trial evidence or the pi-cluster provenance note"
else
  pend "ac4: docs/research/codemap-serena-token-efficiency.md (imported from pi-cluster)"
fi

# ── AC5 · root tasks/ debris is gone ───────────────────────────────────────────────────────
[ -d "$R/tasks" ] && no "ac5: repo-root tasks/ still exists — $(find "$R/tasks" -type f | head -3 | tr '\n' ' ')" \
                  || ok "ac5: no tasks/ directory at repo root"

# ── AC6 · LICENSE (MIT) and CONTRIBUTING.md exist and say what they must ───────────────────
if [ -f "$R/LICENSE" ]; then
  grep -q 'MIT License' "$R/LICENSE" && grep -q 'Permission is hereby granted' "$R/LICENSE" \
    && ok "ac6: LICENSE is MIT (OQ1: permissive by owner's choice)" \
    || no "ac6: LICENSE exists but is not the MIT text"
else
  pend "ac6: LICENSE"
fi
if [ -f "$R/CONTRIBUTING.md" ]; then
  grep -qi 'pull request' "$R/CONTRIBUTING.md" && grep -q 'verify\.sh' "$R/CONTRIBUTING.md" \
    && grep -qi 'red' "$R/CONTRIBUTING.md" \
    && ok "ac6: CONTRIBUTING.md states the convention — PRs only, specs bring gates, red-before-green" \
    || no "ac6: CONTRIBUTING.md exists but omits the convention (PRs only / verify.sh gates / red-before-green)"
else
  pend "ac6: CONTRIBUTING.md"
fi

# ── AC7 · spec slugs are unique on their date+letter prefix ────────────────────────────────
# 20260830a was claimed twice (worker-credentials via #66, then product-naming via #80).
# First claim keeps the slug; the later one moves to 20260830d. The check is general so
# the next collision fails the day it lands, not when a human notices.
dups(){ sed 's/-.*//' | sort | uniq -d; }
printf '20260830a-one\n20260830a-two\n20260830b-three\n' | dups | grep -q . \
  && ok "ac7: positive control — the duplicate-prefix probe fires on a planted collision" \
  || no "ac7: positive control FAILED — the duplicate-prefix probe cannot fire"
_dup="$(ls -d "$R"/specs/2026*/ 2>/dev/null | while read -r d; do basename "$d"; done | dups | tr '\n' ' ')"
[ -n "$_dup" ] && no "ac7: spec-slug prefix collision — $_dup" \
               || ok "ac7: every specs/2026* directory has a unique date+letter prefix"
[ -d "$R/specs/20260830d-product-naming" ] \
  && ok "ac7: 20260830a-product-naming moved to 20260830d-product-naming (worker-credentials held first claim)" \
  || pend "ac7: specs/20260830d-product-naming (the renamed dir)"

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
