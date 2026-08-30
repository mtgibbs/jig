# fixtures.sh — a throwaway loop, so "was the executor called?" is observed, not inferred.
#
# The stub executor appends one line per invocation to execlog.txt and creates the next missing
# marker file. Task N's gate passes iff its marker exists. So a task that was skipped leaves NO
# line in execlog — which is the only direct evidence that the executor was never invoked.

# mkloop <dir> <pertask:yes|no> — a two-task fixture repo carrying the REAL scripts/.
# `bound` comes from scripts/bound.sh. Sourced here rather than relied on transitively:
# every gate that loads this file also loads assert.sh first, which pulls bound in — but a
# fixtures file that only works in that order is a trap for the next gate written against it.
# Idempotent. See specs/amendments.md, "Portability follows the invoker, not the tool".
# shellcheck source=/dev/null
. "$ROOT/scripts/bound.sh" 2>/dev/null || true

mkloop() {
  local d="$1" pertask="$2"
  rm -rf "$d"; mkdir -p "$d/specs/fx"
  cp -r "$ROOT/scripts" "$d/scripts"
  printf '# fixture\n' > "$d/specs/fx/spec.md"
  printf 'T1: make a.\n\nT2: make b.\n' > "$d/specs/fx/tasks.txt"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/specs/fx/verify.sh"
  chmod +x "$d/specs/fx/verify.sh"
  if [ "$pertask" = yes ]; then
    for p in 01:a 02:b; do
      local n="${p%%:*}" m="${p##*:}"
      mkdir -p "$d/specs/fx/tasks/T$n-$m"
      printf '#!/usr/bin/env bash\n[ -f %s.txt ] && { echo "  PASS  ac1: %s"; echo "VERIFY: PASS"; exit 0; }\necho "  FAIL  ac1: %s" >&2; echo "VERIFY: FAIL"; exit 1\n' "$m" "$m" "$m" \
        > "$d/specs/fx/tasks/T$n-$m/verify.sh"
      chmod +x "$d/specs/fx/tasks/T$n-$m/verify.sh"
    done
  fi
  ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
}

# The stub executor: records that it ran, then does the next piece of work.
mkexec() {
  cat > "$T/exec.sh" <<'X'
#!/usr/bin/env bash
echo "invoked $(date +%s%N)" >> "$ROOT/execlog.txt"
if   [ ! -f "$ROOT/a.txt" ]; then echo a > "$ROOT/a.txt"
elif [ ! -f "$ROOT/b.txt" ]; then echo b > "$ROOT/b.txt"
else echo extra >> "$ROOT/extra.txt"; fi
X
  chmod +x "$T/exec.sh"
}

# runloop <dir> [env...] — BOUNDED. Sets RC; output in $T/<basename>.out
runloop() {
  local d="$1"; shift
  local tag; tag="$(basename "$d")"
  ( cd "$d" && bound 180 env "$@" RALPH_LOG=off RALPH_EXEC_CMD="$T/exec.sh" RALPH_AGENT=gate \
      bash scripts/ralph-build.sh specs/fx ) > "$T/$tag.out" 2>&1
  RC=$?
}
loopout() { tr '\n' ' ' < "$T/$1.out" 2>/dev/null | tail -c 400; }
# how many times the executor ran in that fixture
execs() { [ -f "$1/execlog.txt" ] && grep -c invoked "$1/execlog.txt" || echo 0; }
