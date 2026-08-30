#!/usr/bin/env bash
# entrypoint.sh — give the clone credential to git, then get out of the way.
#
# This is the mechanism behind the HARNESS_CLONE_PAT row of docs/executors.md. run-task.sh clones
# a plain https URL with NO token in it and relies on a credential helper having been configured
# before it runs; this is that step, and until it existed the contract named a variable nothing
# read.
#
# Two properties are load-bearing:
#
#   1. UNSET IS A NO-OP. Most runs of this image — a laptop, a plain `docker run`, any public
#      repo — never set the variable, and they must behave exactly as they did before this file
#      existed. Writing an empty credential is worse than writing none: it converts "no credential
#      configured" into an authentication failure.
#
#   2. THE VALUE NEVER REACHES ARGV. `git config` with the token as an argument is readable from
#      /proc for the life of the process, and the container transcript ships to the coordinator.
#      It reaches the file by redirection, and by nothing else.
#
# Exec's run-task.sh BY NAME with "$@" rather than deferring to CMD. `exec "$@"` plus a CMD would
# make `docker run <image> specs/fx --repo proj` try to execute `specs/fx` — every documented
# invocation breaks at once, and the error mentions neither this file nor the CMD.
set -eu

if [ -n "${HARNESS_CLONE_PAT:-}" ]; then
  # 0600 from birth: umask before the redirect, never chmod after it. A chmod afterwards leaves a
  # window in which the token is world-readable to every other process in the container.
  ( umask 077; printf 'https://x-access-token:%s@github.com\n' "$HARNESS_CLONE_PAT" > "$HOME/.git-credentials" )
  git config --global credential.helper store
  # The variable has done its job. Unset it so it is absent from the environment run-task.sh and
  # the model's process tree inherit.
  unset HARNESS_CLONE_PAT
fi

exec "$(dirname "$0")/run-task.sh" "$@"
