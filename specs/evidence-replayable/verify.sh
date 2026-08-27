#!/usr/bin/env bash
# specs/evidence-replayable/verify.sh — the deterministic gate for "an attempt's record is
# replayable, not just readable".
#
# FUNCTIONAL, NOT GREP-BASED. ralph-log.sh is sourceable, so this gate sources it, points it at
# a scratch evidence root and a fixture git repo, calls each writer, and asserts on the ARTIFACTS
# it produced. Grepping the loop for the string "prompt.md" would pass on a comment — the exact
# defect TEMPLATE.md §11 Trap A names, and the exact way four consecutive specs shipped a check
# that could not fail.
#
# Three verdicts. `pend` is for a LATER task's deliverable, keyed on that task's OWN artifact.
# STRICT=1 promotes every pend, so "all tasks passed" can never mean "half of it was never
# written".
set -uo pipefail

R="$(cd "$(dirname "$0")/../.." && pwd)"
fail=0
ok(){   echo "  PASS  $1"; }
no(){   echo "  FAIL  $1" >&2; fail=1; }
pend(){ if [ "${STRICT:-0}" = 1 ]; then no "$1 — still unbuilt at the final check (STRICT)"
        else echo "  pend  $1 (not built yet)"; fi; }

LOG="$R/scripts/ralph-log.sh"
BUILD="$R/scripts/ralph-build.sh"
JUDGE="$R/scripts/ralph-judge.sh"
DOCTOR="$R/scripts/loop-doctor.sh"

# ───────────────────────────────────────────────────────────────────────────────────────────
# SCOPE AND LITTER — FIRST, AND FATAL.
# gate-score.sh's pend contract: an early exit-0 path ahead of the scope check is the
# fail-open-ordering bug. Nothing below runs if the tree is not the tree we expect.
# ───────────────────────────────────────────────────────────────────────────────────────────
for f in "$LOG" "$BUILD" "$JUDGE" "$DOCTOR"; do
  [ -r "$f" ] || { echo "  FAIL  scope: $f missing — this gate cannot run" >&2; exit 1; }
  bash -n "$f" 2>/dev/null || { echo "  FAIL  scope: $f is not syntactically valid bash" >&2; exit 1; }
done
ok "scope: the four touched scripts exist and parse"

# The spec dir carries exactly its four artifacts plus an optional fixtures/ dir. A stray file
# here is litter from a task that wrote in the wrong place.
_stray="$(find "$R/specs/evidence-replayable" -maxdepth 1 -mindepth 1 \
          ! -name spec.md ! -name tasks.txt ! -name verify.sh ! -name fixtures ! -name evidence \
          2>/dev/null | head -3)"
if [ -n "$_stray" ]; then no "scope: unexpected files in the spec dir — $_stray"; else
  ok "scope: spec dir holds only its own artifacts"; fi

# ───────────────────────────────────────────────────────────────────────────────────────────
# SCRATCH — a fixture repo and an evidence root, both thrown away on exit.
# ───────────────────────────────────────────────────────────────────────────────────────────
T="$(mktemp -d 2>/dev/null)" || { echo "  FAIL  scope: no writable temp dir" >&2; exit 1; }
trap 'chmod -R u+rwX "$T" 2>/dev/null; rm -rf "$T"' EXIT INT TERM

REPO="$T/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email gate@example.invalid
git -C "$REPO" config user.name  gate
printf 'original\n'   > "$REPO/tracked.txt"
mkdir -p "$REPO/.evidence"
printf 'harness own record\n' > "$REPO/.evidence/junk.txt"
git -C "$REPO" add tracked.txt 2>/dev/null
git -C "$REPO" commit -qm base 2>/dev/null
BASE="$(git -C "$REPO" rev-parse HEAD 2>/dev/null)"

# The attempt's "work": one tracked file modified, one NEW untracked file created. The new file
# is the whole point of AC-5 — a patch built without `git add -N` omits it entirely and still
# passes `git apply --check`, which is a false green.
printf 'changed\n'    > "$REPO/tracked.txt"
printf 'brand new\n'  > "$REPO/created.txt"

mkdir -p "$T/specs/evidence-replayable"

# probe <extra-shell> — source ralph-log.sh with a scratch root, run log_init, then the caller's
# body. Written to a file with a QUOTED heredoc: an unquoted one would let this shell expand the
# body before the probe's shell ever saw it (AGENTS.md, "never interpolate into a foreign
# language").
cat > "$T/probe.sh" <<'PROBE'
#!/usr/bin/env bash
set -uo pipefail
. "$GATE_LOG_SH"
log_init >/dev/null 2>&1
printf '%s\n' "${LOG_DIR:-}" > "$GATE_OUT/logdir"
printf '%s\n' "${LOG_OK:-0}" > "$GATE_OUT/logok"
eval "$GATE_BODY"
exit 0
PROBE
chmod +x "$T/probe.sh"

probe() {
  GATE_LOG_SH="$LOG" GATE_OUT="$T" GATE_BODY="${1:-:}" \
  ROOT="$REPO" SPEC_DIR="$T/specs/evidence-replayable" \
  RALPH_LOG_DIR="$T/ev" RALPH_AGENT=gate \
  bash "$T/probe.sh" >/dev/null 2>&1
  _rc=$?
  D="$(cat "$T/logdir" 2>/dev/null)"
  return $_rc
}

# has <fn> — is this writer built yet? `type` on a sourced file, not a grep on the source.
has() {
  GATE_LOG_SH="$LOG" GATE_OUT="$T" GATE_BODY=":" \
  ROOT="$REPO" SPEC_DIR="$T/specs/evidence-replayable" \
  RALPH_LOG_DIR="$T/ev" RALPH_AGENT=gate \
  bash -c '. "$GATE_LOG_SH"; type "'"$1"'" >/dev/null 2>&1' >/dev/null 2>&1
}

D=""
probe ':' || true
if [ -z "$D" ] || [ ! -d "$D" ]; then
  no "log_init did not produce a usable LOG_DIR under RALPH_LOG_DIR — nothing below can be tested"
  echo "---"; [ "$fail" = 0 ] && exit 0 || exit 1
fi
ok "harness: log_init honours RALPH_LOG_DIR and creates a run directory"

# ───────────────────────────────────────────────────────────────────────────────────────────
# AC-10 — the run-dir leaf is still <agent>-<pid>. Every reader parses the pid out of it.
# ───────────────────────────────────────────────────────────────────────────────────────────
case "$(basename "$D")" in
  gate-[0-9]*) ok "ac10: run-dir leaf is <agent>-<pid> ($(basename "$D"))" ;;
  *)           no "ac10: run-dir leaf is '$(basename "$D")', not <agent>-<pid>" ;;
esac

# ───────────────────────────────────────────────────────────────────────────────────────────
# T1 · AC-1/AC-2 — the prompt survives byte-for-byte.
# The probe text starts with `-n` and carries a backslash and a trailing newline: `echo` mangles
# all three, `printf '%s'` does not. A writer that passes on a tame string and corrupts a real
# prompt is the failure this fixture exists to catch.
# ───────────────────────────────────────────────────────────────────────────────────────────
PTXT='-n literal
back\slash and $notexpanded
'
if has log_prompt; then
  printf '%s' "$PTXT" > "$T/expected.prompt"
  GATE_PROMPT="$PTXT" probe 'log_prompt T1 1 "$GATE_PROMPT"' || true
  f="$D/T1-attempt1.prompt.md"
  if [ -f "$f" ]; then
    if cmp -s "$f" "$T/expected.prompt"; then
      ok "ac1: .prompt.md holds the prompt byte-for-byte"
    else
      no "ac1: .prompt.md differs from the prompt it was given (echo instead of printf '%s'?)"
    fi
  else
    no "ac1: log_prompt exists but wrote no $(basename "$f")"
  fi
else
  pend "ac1: log_prompt"
  pend "ac2: prompt survives a stillborn executor"
fi

# ───────────────────────────────────────────────────────────────────────────────────────────
# T2 · AC-3 — the gate record, and AC-14 — the extension is not .log
# ───────────────────────────────────────────────────────────────────────────────────────────
if has log_gate; then
  probe 'log_gate T1 1 "  PASS  a
  FAIL  b" 1' || true
  f="$D/T1-attempt1.gate.txt"
  if [ -f "$f" ]; then
    if [ "$(tail -2 "$f" | head -1)" = "---GATE-RC---" ] && [ "$(tail -1 "$f")" = "1" ]; then
      ok "ac3: .gate.txt ends in ---GATE-RC--- followed by the gate's exit status"
    else
      no "ac3: .gate.txt does not end in the ---GATE-RC--- sentinel + rc"
    fi
    grep -q "FAIL  b" "$f" && ok "ac3: .gate.txt carries the gate's output verbatim" \
                           || no "ac3: .gate.txt dropped the gate's output"
  else
    [ -f "$D/T1-attempt1.gate.log" ] \
      && no "ac3/ac14: the artifact is named .gate.log — it matches T*-attempt*.log and will double every attempt count" \
      || no "ac3: log_gate exists but wrote no $(basename "$f")"
  fi
else
  pend "ac3: log_gate"
fi

# ───────────────────────────────────────────────────────────────────────────────────────────
# T3 · AC-5/AC-6 — an applyable patch that includes NEW files and excludes .evidence.
#
# POSITIVE CONTROL (TEMPLATE.md §11 Trap B): a bare `git diff` on this same tree is built first
# and asserted NOT to mention created.txt. Without that control, "the patch applies" is a claim
# an EMPTY patch also satisfies, and the `-N` pass this AC exists to require would be optional.
# ───────────────────────────────────────────────────────────────────────────────────────────
git -C "$REPO" diff > "$T/naive.patch" 2>/dev/null
if grep -q 'created\.txt' "$T/naive.patch" 2>/dev/null; then
  no "control: a bare git diff already contains the new file — this fixture cannot prove -N is load-bearing"
else
  ok "control: a bare git diff omits the new file (so ac5 is a real requirement)"
fi

if has log_patch; then
  probe 'log_patch T1 1' || true
  f="$D/T1-attempt1.patch"
  if [ -f "$f" ]; then
    if grep -q 'created\.txt' "$f"; then
      ok "ac5: .patch includes a file the attempt newly created"
    else
      no "ac5: .patch omits the new file — git add -A -N was skipped, and the patch is a false green"
    fi
    # Apply against the pre-attempt tree, in a clone so the fixture is untouched.
    CK="$T/applycheck"
    rm -rf "$CK"; git clone -q "$REPO" "$CK" 2>/dev/null
    if git -C "$CK" checkout -q "$BASE" 2>/dev/null && git -C "$CK" apply --check "$f" 2>/dev/null; then
      ok "ac5: git apply --check accepts .patch against the pre-attempt tree"
    else
      no "ac5: git apply --check rejects .patch against the pre-attempt tree"
    fi
    grep -q '\.evidence/' "$f" \
      && no "ac6: .patch contains a path under .evidence/ — the harness recorded its own record" \
      || ok "ac6: .patch excludes .evidence/"
  else
    no "ac5: log_patch exists but wrote no $(basename "$f")"
  fi
else
  pend "ac5: log_patch"
  pend "ac6: .evidence excluded from the patch"
fi

# ───────────────────────────────────────────────────────────────────────────────────────────
# T4/T5 · AC-7/AC-8 — the per-attempt record, and null-is-not-zero.
# ───────────────────────────────────────────────────────────────────────────────────────────
if has log_meta; then
  probe 'log_meta T1 1' || true
  f="$D/T1-attempt1.json"
  if [ -f "$f" ]; then
    if command -v jq >/dev/null 2>&1; then
      if jq -e . "$f" >/dev/null 2>&1; then
        ok "ac7: .json is parseable JSON"
        miss=""
        for k in run_id run_label repo spec task attempt binding agent started ended \
                 duration_s exec_rc verify_rc outcome bytes_prompt bytes_transcript bytes_patch; do
          jq -e "has(\"$k\")" "$f" >/dev/null 2>&1 || miss="$miss $k"
        done
        [ -z "$miss" ] && ok "ac7: .json carries every §3.2 field" \
                       || no "ac7: .json is missing fields —$miss"
        # AC-8: unset RUN_LABEL is JSON null, never "" and never absent.
        case "$(jq -c '.run_label' "$f" 2>/dev/null)" in
          null) ok "ac8: run_label is null when RUN_LABEL is unset" ;;
          '""') no "ac8: run_label is the empty string — null and \"\" are different values" ;;
          *)    no "ac8: run_label is $(jq -c '.run_label' "$f" 2>/dev/null) with RUN_LABEL unset" ;;
        esac
        # …and the positive control for that null: with RUN_LABEL set it must be the string.
        rm -f "$f"
        RUN_LABEL=s1-run1 probe 'log_meta T1 1' || true
        if [ "$(jq -r '.run_label' "$f" 2>/dev/null)" = "s1-run1" ]; then
          ok "control: run_label carries RUN_LABEL when it is set (so the null above is measured, not broken)"
        else
          no "control: run_label does not carry RUN_LABEL — the null above proves nothing"
        fi
      else
        no "ac7: .json is not parseable JSON — a quote in a task label or binding path?"
      fi
    else
      pend "ac7: jq is absent, .json content cannot be asserted"
    fi
  else
    no "ac7: log_meta exists but wrote no $(basename "$f")"
  fi
else
  pend "ac7: log_meta"
  pend "ac8: run_label null-vs-empty"
fi

# ───────────────────────────────────────────────────────────────────────────────────────────
# T5 · AC-9 — `latest` is a RELATIVE symlink beside the run dir.
# ───────────────────────────────────────────────────────────────────────────────────────────
LATEST="$(dirname "$D")/latest"
if [ -L "$LATEST" ]; then
  tgt="$(readlink "$LATEST" 2>/dev/null)"
  case "$tgt" in
    */*) no "ac9: latest -> '$tgt' is a path, not a sibling basename — it breaks when the repo moves" ;;
    "")  no "ac9: latest is a symlink with no readable target" ;;
    *)   if [ "$tgt" = "$(basename "$D")" ]; then
           ok "ac9: latest is a relative symlink to the newest run ($tgt)"
         else
           no "ac9: latest -> '$tgt' but the newest run is '$(basename "$D")'"
         fi ;;
  esac
elif [ -e "$LATEST" ]; then
  no "ac9: latest exists but is not a symlink"
else
  pend "ac9: latest symlink"
fi

# ───────────────────────────────────────────────────────────────────────────────────────────
# AC-14 — no new artifact matches the glob two readers already use.
# Asserted by EXPANDING the glob over the produced directory, not by reading the source: a
# source-level check would pass on a comment, and it is the expansion that the readers do.
# ───────────────────────────────────────────────────────────────────────────────────────────
printf 'transcript\n' > "$D/T1-attempt1.log"
n=0; for p in "$D"/T*-attempt*.log; do [ -f "$p" ] && n=$((n + 1)); done
if [ "$n" = 1 ]; then
  ok "ac14: exactly one artifact matches T*-attempt*.log (the transcript)"
else
  no "ac14: $n artifacts match T*-attempt*.log — a new extension is shadowing the transcript glob"
fi

# ───────────────────────────────────────────────────────────────────────────────────────────
# AC-4 — verify.sh is invoked exactly as often as it was at 1ea0c6e. Writing .gate.txt must
# reuse the captured output; a second invocation would double every gate's side effects.
# Comments are stripped first so the count measures CODE, not a sentence about code.
# ───────────────────────────────────────────────────────────────────────────────────────────
vn="$(sed 's/#.*//' "$BUILD" | grep -c 'bash "\$VERIFY"' 2>/dev/null || echo 0)"
if [ "$vn" = 2 ]; then
  ok "ac4: ralph-build.sh invokes verify.sh twice, unchanged from 1ea0c6e (loop + STRICT)"
else
  no "ac4: ralph-build.sh invokes verify.sh $vn times; the baseline is 2 (loop + final STRICT)"
fi

# ───────────────────────────────────────────────────────────────────────────────────────────
# AC-11 — a writer that cannot write must not change the loop's exit status.
# Skipped honestly when running as root, where chmod 000 does not deny.
# ───────────────────────────────────────────────────────────────────────────────────────────
if [ "$(id -u 2>/dev/null || echo 1)" = 0 ]; then
  pend "ac11: cannot test unwritable LOG_DIR as root"
elif has log_prompt || has log_gate || has log_patch || has log_meta; then
  chmod 000 "$D" 2>/dev/null
  GATE_LOG_SH="$LOG" GATE_OUT="$T" ROOT="$REPO" \
  GATE_BODY='for w in log_prompt log_gate log_patch log_meta; do
               type "$w" >/dev/null 2>&1 && "$w" T9 9 x 0 || true; done' \
  SPEC_DIR="$T/specs/evidence-replayable" RALPH_LOG_DIR="$T/ev" RALPH_AGENT=gate \
  bash "$T/probe.sh" >/dev/null 2>&1
  rc=$?
  chmod 755 "$D" 2>/dev/null
  [ "$rc" = 0 ] && ok "ac11: writers exit 0 against an unwritable LOG_DIR" \
                || no "ac11: a writer returned $rc against an unwritable LOG_DIR — it can fail the loop"
else
  pend "ac11: no writers built yet"
fi

# ───────────────────────────────────────────────────────────────────────────────────────────
# T6 · AC-12/AC-13 — loop-doctor classifies the new artifacts, and old runs read unchanged.
# AC-13's legacy fixture is the positive control that the reader change is ADDITIVE.
# ───────────────────────────────────────────────────────────────────────────────────────────
mkdir -p "$T/dr/status" "$T/dr/logs/gate-1001" "$T/dr/logs/gate-1002"
cat > "$T/dr/status/gate-1001.json" <<'J'
{"agent":"gate","repo":"fixture","spec":"specs/evidence-replayable","branch":"b","task_index":1,
 "total_tasks":1,"attempt":1,"max_attempts":3,"phase":"passed","verify_pass":true,
 "started":1000,"updated":1100}
J
sed 's/gate-1001/gate-1002/' "$T/dr/status/gate-1001.json" > "$T/dr/status/gate-1002.json"
# modern: one transcript plus the full new artifact set
for e in log prompt.md gate.txt patch json; do printf 'x\n' > "$T/dr/logs/gate-1001/T1-attempt1.$e"; done
# legacy: exactly what a pre-spec run left behind
printf 'x\n' > "$T/dr/logs/gate-1002/T1-attempt1.log"
printf 'x\n' > "$T/dr/logs/gate-1002/T1-attempt1.diff"

# STAGING, not the check. loop-doctor's deliverable is BEHAVIOUR, so the check is the functional
# unparsed==0 assertion below; this grep only decides whether that check is ARMED yet. Without it
# ac12 hard-FAILs on T6's work from T1 onward, and no retry of T1 can ever fix it — the too-coarse
# anchoring failure TEMPLATE.md §11 measures at 45/0 -> 49/6.
_doctor_taught=0
sed 's/#.*//' "$DOCTOR" | grep -q 'prompt\.md' 2>/dev/null && _doctor_taught=1

if [ "$_doctor_taught" = 0 ]; then
  pend "ac12: loop-doctor's artifact case arms"
  # ac13 is NOT staged: a legacy run must read unchanged at every point in the build, including
  # before T6. It is the control that proves the eventual edit was additive, so it arms now.
  if command -v jq >/dev/null 2>&1; then
    dj="$(bash "$DOCTOR" --status-dir "$T/dr/status" --log-dir "$T/dr/logs" --json --now 2000 2>/dev/null)"
    l="$(printf '%s\n' "$dj" | jq -c 'select(.run_id=="gate-1002")' 2>/dev/null | head -1)"
    if [ -n "$l" ] && [ "$(printf '%s' "$l" | jq -r '.unparsed')" = 0 ] \
    && [ "$(printf '%s' "$l" | jq -r '.attempts_seen')" = 1 ] \
    && [ "$(printf '%s' "$l" | jq -r '.diffs_seen')" = 1 ]; then
      ok "ac13: a legacy .log+.diff run classifies cleanly (baseline, pre-T6)"
    else
      no "ac13: a legacy .log+.diff run does not classify cleanly even before T6"
    fi
  else
    pend "ac13: jq is absent"
  fi
elif command -v jq >/dev/null 2>&1; then
  dj="$(bash "$DOCTOR" --status-dir "$T/dr/status" --log-dir "$T/dr/logs" --json --now 2000 2>/dev/null)"
  m="$(printf '%s\n' "$dj" | jq -c 'select(.run_id=="gate-1001")' 2>/dev/null | head -1)"
  l="$(printf '%s\n' "$dj" | jq -c 'select(.run_id=="gate-1002")' 2>/dev/null | head -1)"
  if [ -n "$m" ]; then
    [ "$(printf '%s' "$m" | jq -r '.unparsed')" = 0 ] \
      && ok "ac12: loop-doctor reports unparsed=0 for a run holding the full artifact set" \
      || no "ac12: loop-doctor reports unparsed=$(printf '%s' "$m" | jq -r '.unparsed') on a HEALTHY run — the new artifacts read as format drift"
    [ "$(printf '%s' "$m" | jq -r '.attempts_seen')" = 1 ] \
      && ok "ac12: attempts_seen counts transcripts (1), not files" \
      || no "ac12: attempts_seen=$(printf '%s' "$m" | jq -r '.attempts_seen'), expected 1 transcript"
  else
    no "ac12: loop-doctor emitted no record for the modern fixture run"
  fi
  if [ -n "$l" ]; then
    if [ "$(printf '%s' "$l" | jq -r '.unparsed')" = 0 ] \
    && [ "$(printf '%s' "$l" | jq -r '.attempts_seen')" = 1 ] \
    && [ "$(printf '%s' "$l" | jq -r '.diffs_seen')" = 1 ]; then
      ok "ac13: a legacy .log+.diff run still classifies exactly as before (the additive control)"
    else
      no "ac13: the legacy run's classification changed — the reader edit was not additive"
    fi
  else
    no "ac13: loop-doctor emitted no record for the legacy fixture run"
  fi
else
  pend "ac12/ac13: jq is absent, loop-doctor's JSON cannot be asserted"
fi

# POSITIVE CONTROL for ac14/ac12 (TEMPLATE.md §11 Trap B). The two assertions above are of the
# form "expect 1" and "expect 0" — both are also satisfied by a probe that never fires. Rename
# the gate artifact to the WRONG extension and prove the counters move. If this control does not
# move them, the checks above prove nothing.
if command -v jq >/dev/null 2>&1; then
  mv "$T/dr/logs/gate-1001/T1-attempt1.gate.txt" "$T/dr/logs/gate-1001/T1-attempt1.gate.log" 2>/dev/null
  cj="$(bash "$DOCTOR" --status-dir "$T/dr/status" --log-dir "$T/dr/logs" --json --now 2000 2>/dev/null \
        | jq -c 'select(.run_id=="gate-1001")' 2>/dev/null | head -1)"
  mv "$T/dr/logs/gate-1001/T1-attempt1.gate.log" "$T/dr/logs/gate-1001/T1-attempt1.gate.txt" 2>/dev/null
  if [ "$(printf '%s' "$cj" | jq -r '.attempts_seen' 2>/dev/null)" = 2 ]; then
    ok "control: naming the gate artifact .gate.log DOES double attempts_seen — the .txt requirement is real and the probe fires"
  else
    no "control: renaming to .gate.log did not move attempts_seen — ac12/ac14 are measuring nothing"
  fi
fi

# ───────────────────────────────────────────────────────────────────────────────────────────
# T7 · the call sites. Presence-gated on each writer's OWN artifact appearing in the loop, not
# on a task number. Comments are stripped so a sentence about a call is not a call.
# ───────────────────────────────────────────────────────────────────────────────────────────
_calls(){ sed 's/#.*//' "$1" | grep -c "$2" 2>/dev/null || echo 0; }

if has log_prompt; then
  [ "$(_calls "$BUILD" 'log_prompt')" -ge 1 ] \
    && ok "ac1: ralph-build.sh calls log_prompt" || pend "ac1: log_prompt call site in ralph-build.sh"
  [ "$(_calls "$JUDGE" 'log_prompt')" -ge 1 ] \
    && ok "ac15: ralph-judge.sh persists the judge prompt" || pend "ac15: log_prompt call site in ralph-judge.sh"
else
  pend "ac1: log_prompt call site"
  pend "ac15: judge prompt persisted"
fi

if has log_gate; then
  [ "$(_calls "$BUILD" 'log_gate')" -ge 2 ] \
    && ok "ac3: ralph-build.sh calls log_gate on both the passing and failing paths" \
    || pend "ac3: log_gate call sites (both paths) in ralph-build.sh"
else
  pend "ac3: log_gate call sites"
fi

if has log_patch; then
  [ "$(_calls "$BUILD" 'log_patch')" -ge 1 ] \
    && ok "ac5: ralph-build.sh calls log_patch" || pend "ac5: log_patch call site in ralph-build.sh"
else
  pend "ac5: log_patch call site"
fi

if has log_meta; then
  [ "$(_calls "$BUILD" 'log_meta')" -ge 1 ] \
    && ok "ac7: ralph-build.sh calls log_meta" || pend "ac7: log_meta call site in ralph-build.sh"
else
  pend "ac7: log_meta call site"
fi

echo "---"
[ "$fail" = 0 ] && exit 0 || exit 1
