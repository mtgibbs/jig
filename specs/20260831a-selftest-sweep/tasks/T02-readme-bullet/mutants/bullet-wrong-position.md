# MUTANT: ac05
# TARGET: .evidence/README.md
# WHY: the bullet exists VERBATIM but sits before the mutant-ledger bullet.
# WHY: §6b says directly after — a verbatim grep alone cannot tell these apart,
# WHY: which is why the gate asserts position.
# .evidence/ — the in-repo record of what the loops actually did

Everything a run leaves behind is keyed by **spec slug** and committed here, per the
constitution ("Evidence is the record"). The convention itself is specified in
`specs/20260825a-evidence-convention/spec.md`; `scripts/loop-index.py` joins the stores
into `index-<slug>.md` / `index-<slug>.jsonl` in this directory.

## Why in-repo, and why the fallback exists

The harness also writes to an unversioned dotfolder, `~/.harness/`, which runs deletion
timers: **3 days for logs, 1 day for status files**. 14 of this project's first 42 runs
had already lost their status file to that timer before anyone noticed — which is why
every reader (`loop-index.py` first among them) reads the in-repo `.evidence/` first and
treats `~/.harness/` only as a fallback for what a run has not yet committed.

## What lives where

- `.evidence/status/` — one JSON per executor process: task, attempt, phase, verdict
- `.evidence/runs/` — per-attempt `.log` / `.diff` (gitignored; bulky)
- `index-<slug>.{md,jsonl}` — the joined, re-derivable index per spec
- `selftest-<slug>.jsonl` — mutant kill/survivor rows from `scripts/gate-selftest.sh`
  (written when `SELFTEST_EVID` is set; one row per mutant with the install-time diff,
  plus a `run_complete` marker per corpus run — spec `20260830f-mutant-observability`)
- `scripts/selftest-sweep.sh` (run from anywhere) records every corpus above in one
  command and regenerates the ledger; `--dry-run` lists what it would run
- `mutant-ledger.{md,html}` — the rendered Mutant Ledger; regenerate with
  `scripts/mutant-ledger.py`, never edit
- a spec's narrative evidence (red-before-green records, findings) lives with the spec,
  in `specs/<slug>/evidence/`
