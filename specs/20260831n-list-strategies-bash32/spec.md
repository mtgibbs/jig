# Spec: --list works on the bash the laptop actually ships

- **Status:** Done v1.0 — implemented 2026-08-31 with the spec (red-before-green in
  `evidence/`); closes issue #106
- **Owner:** Matt (spec + implementation by Claude)
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Tools:** bash, git
- **MCP:** none
- **Permissions:** write:scripts/run-loop.sh

---

## 1. Why · [R — Requirements]

Issue #106: `run-loop.sh --list` uses `declare -A`, an associative array — bash 4.
macOS ships bash 3.2, where it is a hard error, so `--list` dies before listing
anything and the `20260829a` gate's end-3 reads "build-converge is unreachable by
name" — which on this platform it genuinely is. The repo's floor is bash 3.2
(AGENTS.md); `agent-bus-bootstrap` already carries the no-arrays idiom with a
comment saying exactly why. Homebrew's bash 5 on dev machines is what let this
hide.

## 2. Outcomes (Definition of Done) · [O — Outcomes]

1. `--list` runs under `/bin/bash` (3.2): exit 0, strategies listed, no `declare`
   error.
2. The dedup it implemented survives: a consumer `.harness/loops/<name>.conf`
   shadows the built-in of the same name — listed once, tagged `[consumer]`.
3. Output shape unchanged (`  %-20s [%s] %s`).

## 4. Approach · [A — Approach]

The `SEEN` map becomes a space-delimited string probed with a `case` match — the
same idiom `agent-bus-bootstrap` documents. No arrays of any kind.

## 5. Scope · [S — Structure: boundary]

### In scope
`scripts/run-loop.sh` — the `--list` block only.

### Out of scope
The rest of run-loop.sh (already bash-3.2 clean); the 20260829a gate itself.

## 9. Task breakdown · [O — Operations]

- T1: replace `declare -A SEEN` with the string/case idiom; keep dedup and output.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- `/bin/bash scripts/run-loop.sh --list` shall exit 0, print `build-converge`,
  and print no `declare` error. (ac1)
- When a consumer repo's `.harness/loops/` shadows a built-in name, that name
  shall appear exactly once, tagged `[consumer]`. (ac2)
- A consumer-only strategy shall list alongside built-ins (positive control that
  both sources still contribute). (ac3)
- Every listed line shall match the `  <name> [<origin>] <desc>` shape. (ac4)
- `bash -n` under `/bin/bash` shall pass. (ac5)

## 11. Verification

Single-task spec: one gate, `verify.sh`, no pend. All checks drive `/bin/bash`
explicitly (the 20260818c idiom — Homebrew bash 5 hides exactly this bug); the
consumer fixture is a temp git repo with a `.harness/loops/` dir.

## 12. Open questions

None.

## 14. Tuning log

- (none yet)
