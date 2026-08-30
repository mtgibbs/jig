#!/usr/bin/env bash
# MUTANT: ac08
# TARGET: scripts/exec-qwen.sh
# WHY: does the obvious half — execs opencode instead of oc, so the "still calls oc" check
# WHY: passes — and keeps the credential fetch. The binding now works on exactly one machine:
# WHY: the one with that Keychain entry and that 1Password vault. A container has neither, and
# WHY: the failure arrives as an empty key rather than as a missing tool.
set -uo pipefail
KEY="$(security find-generic-password -s opencode-qwen -w 2>/dev/null || true)"
[ -z "$KEY" ] && KEY="$(op read 'op://pi-cluster/opencode-coder/password' 2>/dev/null || true)"
export OPENCODE_QWEN_KEY="$KEY"
exec env OC_SHEET=off opencode run --dir "${ROOT:-$PWD}" "${1:?exec-qwen.sh <prompt>}"
