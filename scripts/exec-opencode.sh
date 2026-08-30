#!/usr/bin/env bash
# exec-opencode.sh — the default executor binding for the build loop.
#
# Renamed from exec-qwen.sh: once the binding takes provider configuration from the environment,
# the filename named a model it no longer knows about. The image it runs in decides the model.
#
# Thin by contract (specs/20260825c-executor-binding §3, §7): take the prompt as $1, read ROOT
# from the environment, run the tool, let stdout be the transcript. No retry, no gate, no
# evidence, no stopping logic — the loop owns all of that. If this file ever grows a decision,
# the decision belongs in the loop, or every future binding has to reimplement it.
#
# It execs `opencode` DIRECTLY rather than `oc`. `oc` is a private laptop shim that reads a
# LiteLLM key from the macOS Keychain, falls back to 1Password, exports OPENCODE_QWEN_KEY,
# applies its own watchdog, and then execs opencode — four things, of which only the last
# belongs in a binding. Credential acquisition is the OPERATOR's (Keychain or 1Password on a
# laptop, `envFrom` a Secret in a Job) and the watchdog is already the LOOP's (ralph-build.sh
# run_bounded), which this file's own header has always said. A binding that reaches for a
# credential works on exactly one machine, and that is the property that decides whether a
# derived image is runnable by someone who is not this account.
#
# `oc` survives as a laptop convenience that sets the environment and calls this same binding.
#
# The codesheet is injected once per loop by ralph-build.sh, so there is nothing to suppress
# here — OC_SHEET was `oc`'s knob for `oc`'s own injection, and it went with `oc`.
set -uo pipefail
exec opencode run --dir "${ROOT:-$PWD}" "${1:?exec-opencode.sh <prompt>}"
