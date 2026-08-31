#!/usr/bin/env bash
# Gate for T03-authoring-skill (20260831q). Static checks on the skill file and the
# TEMPLATE edit. The absence assertion (the dead exemption sentence) has its positive
# control in evidence/red-before-green.txt: the probe fires on the pre-edit TEMPLATE.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
SK="$R/.claude/skills/author-spec/SKILL.md"
TPL="$R/specs/TEMPLATE.md"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

# ── ac1: the skill exists and is a Claude Code skill ──
if [ ! -f "$SK" ]; then
  no "ac1: .claude/skills/author-spec/SKILL.md does not exist"
else
  ok "ac1: SKILL.md exists"
  grep -q '^name: author-spec' "$SK" \
    && ok "ac1: frontmatter names the skill author-spec" \
    || no "ac1: frontmatter lacks 'name: author-spec'"
fi

# ── ac2: the skill teaches the convention, concretely ──
if [ -f "$SK" ]; then
  grep -q 'scripts/new-spec.sh' "$SK" \
    && ok "ac2: the skill names scripts/new-spec.sh" \
    || no "ac2: the skill never names the scaffolder"
  grep -q 'red-before-green' "$SK" \
    && ok "ac2: the skill teaches red-before-green evidence" \
    || no "ac2: the skill does not mention red-before-green"
  grep -qi 'single-task' "$SK" && grep -q 'tasks/T<NN>-<slug>/verify.sh' "$SK" \
    && ok "ac2: the skill states the per-task layout, single-task included" \
    || no "ac2: the skill misses the per-task layout or the single-task rule"
  grep -q 'no override' "$SK" \
    && ok "ac2: the skill says there is no override" \
    || no "ac2: the skill does not say the refusal has no override"
  grep -q -- '--check' "$SK" \
    && ok "ac2: the skill requires --check before a PR" \
    || no "ac2: the skill never mentions --check"
fi

# ── ac3: TEMPLATE.md names the scaffolder and the exemption sentence is gone ──
grep -q 'scripts/new-spec.sh' "$TPL" \
  && ok "ac3: TEMPLATE names scripts/new-spec.sh" \
  || no "ac3: TEMPLATE does not name the scaffolder"
grep -Fq 'needs no `tasks/` directory' "$TPL" \
  && no "ac3: the single-task exemption sentence is still in the TEMPLATE" \
  || ok "ac3: the single-task exemption sentence is gone"
grep -q 'single-task spec still carries' "$TPL" \
  && ok "ac3: TEMPLATE states that a single-task spec still carries tasks/" \
  || no "ac3: TEMPLATE lacks the replacement rule for single-task specs"
grep -q 'Every spec carries one gate per task' "$TPL" \
  && ok "ac3: the gate-layout heading sentence covers EVERY spec" \
  || no "ac3: the gate-layout opener still scopes the rule to multi-task specs"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
