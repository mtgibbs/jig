# fixtures.sh — a throwaway loop plus a stub coordinator, so both directions are observed.
# `bound` comes from scripts/bound.sh. Sourced here rather than relied on transitively:
# every gate that loads this file also loads assert.sh first, which pulls bound in — but a
# fixtures file that only works in that order is a trap for the next gate written against it.
# Idempotent. See specs/amendments.md, "Portability follows the invoker, not the tool".
# shellcheck source=/dev/null
. "$ROOT/scripts/bound.sh" 2>/dev/null || true

COORD_PY="$ROOT/specs/20260828m-worker-channel/lib/coord.py"

# mkloop <dir> — a two-task fixture repo with per-task gates, carrying the REAL scripts/.
mkloop() {
  local d="$1"
  rm -rf "$d"; mkdir -p "$d/specs/fx"
  cp -r "$ROOT/scripts" "$d/scripts"
  printf '# fixture\n' > "$d/specs/fx/spec.md"
  printf 'T1: make a.\n\nT2: make b.\n' > "$d/specs/fx/tasks.txt"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$d/specs/fx/verify.sh"; chmod +x "$d/specs/fx/verify.sh"
  for p in 01:a 02:b; do
    local n="${p%%:*}" m="${p##*:}"
    mkdir -p "$d/specs/fx/tasks/T$n-$m"
    printf '#!/usr/bin/env bash\n[ -f %s.txt ] && { echo "  PASS  ac1: %s"; echo "VERIFY: PASS"; exit 0; }\necho "  FAIL  ac1: %s" >&2; echo "VERIFY: FAIL"; exit 1\n' "$m" "$m" "$m" \
      > "$d/specs/fx/tasks/T$n-$m/verify.sh"
    chmod +x "$d/specs/fx/tasks/T$n-$m/verify.sh"
  done
  ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t \
      && git add -A && git commit -qm init ) >/dev/null 2>&1
}

mkexec() {
  cat > "$T/exec.sh" <<'X'
#!/usr/bin/env bash
echo "invoked" >> "$ROOT/execlog.txt"
if   [ ! -f "$ROOT/a.txt" ]; then echo a > "$ROOT/a.txt"
elif [ ! -f "$ROOT/b.txt" ]; then echo b > "$ROOT/b.txt"; fi
X
  chmod +x "$T/exec.sh"
}

# coord_start [action] — stub coordinator. Sets COORD_URL; requests land in $T/coord.log.
coord_start() {
  # Clear the port file FIRST. The readiness wait below is `while [ ! -s coord.port ]`, so a stale
  # file from an earlier coord_start satisfies it instantly and COORD_URL is set to a server that
  # has already been killed. Everything then behaves as though the coordinator were absent.
  #
  # This was not harmless. ac3 asserts that a 500, an unparseable body and an absent coordinator
  # are all "carry on" — and it was green while testing the absent case three times over, because
  # the 500 and BROKEN stubs were never actually reached. ac4 is what surfaced it: it needs a
  # coordinator that really answers, and a check that must PASS is the only kind that notices a
  # stub nobody is talking to.
  : > "$T/coord.log"; rm -f "$T/coord.port"; echo "${1:-none}" > "$T/action.txt"
  python3 "$COORD_PY" "$T/coord.log" "$T/action.txt" > "$T/coord.port" 2>"$T/coord.err" &
  COORD_PID=$!
  local i=0
  while [ ! -s "$T/coord.port" ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done
  COORD_URL="http://127.0.0.1:$(cat "$T/coord.port" 2>/dev/null)"
}
coord_stop() { [ -n "${COORD_PID:-}" ] && kill "$COORD_PID" 2>/dev/null; COORD_PID=""; }
coord_say()  { echo "$1" > "$T/action.txt"; }
# posts <path-fragment> — how many requests hit a path
posts() { grep -c "\"p\": *\"[^\"]*$1" "$T/coord.log" 2>/dev/null || echo 0; }

TOKEN="TOKEN-COORD-7b2"

# runloop <dir> [env...] — BOUNDED; sets RC, output in $T/<tag>.out
runloop() {
  local d="$1"; shift; local tag; tag="$(basename "$d")"
  ( cd "$d" && bound 180 env "$@" RALPH_LOG=off RALPH_EXEC_CMD="$T/exec.sh" RALPH_AGENT=gate \
      bash scripts/ralph-build.sh specs/fx ) > "$T/$tag.out" 2>&1
  RC=$?
}
loopout() { tr '\n' ' ' < "$T/$1.out" 2>/dev/null | tail -c 400; }
execs()   { [ -f "$1/execlog.txt" ] && grep -c invoked "$1/execlog.txt" || echo 0; }
