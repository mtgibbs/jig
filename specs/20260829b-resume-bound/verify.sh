#!/usr/bin/env bash
# Convergence gate for 20260829b.
#
# This spec has ONE task, so a separate end-state gate would either duplicate T01's assertions or
# be a weaker restatement of them — and a weaker restatement is the worse outcome, because it
# passes in cases the real gate would catch and reads as independent confirmation. Delegate.
#
# `run_gates` never invokes this file for a spec carrying tasks/ (it runs the per-task gates
# directly); it exists because run-loop.sh requires it and because a human or CI running the spec
# by hand should get the real check rather than nothing. It therefore carries T01's full cost,
# including the one assertion that must wait out the old 60s bound.
set -u
ROOT="${ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
exec bash "$ROOT/specs/20260829b-resume-bound/tasks/T01-resume-bound/verify.sh"
