# Spec: 20260901a-kubectl-skew-pin

- **Status:** Done v1.0
- **Owner:** mtgibbs
- **Constitution:** `specs/constitution.md` + `specs/amendments.md`
- **Touches:** `docker/dispatcher.Dockerfile`
- **Tools:** curl
- **MCP:** none

## 1. Why · [R — Requirements]

`docker/dispatcher.Dockerfile` pins `ARG KUBECTL_VERSION=v1.37.0`. The cluster it
dispatches into runs **v1.34.3+k3s1** — +3 minors, outside Kubernetes' supported ±1
client/server skew. The Dockerfile's own `VERSION SKEW` comment calls for exactly this
check ("Check the k3s server version before bumping this"); this spec is that check
arriving late, filed as jig #116.

Upgrading the cluster is not available as the fix: k3s's own release channels top out at
`v1.36.4+k3s1` (checked 2026-09-01) — **there is no k3s v1.37**. The pin is the only side
that can move.

The failure shape being bought off is the one the comment predicted: a far-ahead kubectl
fails later, at `apply` time, inside a long-lived Deployment, with a message about the
resource rather than about the skew.

## 2. Outcomes (Definition of Done) · [R — Requirements]

1. The kubectl pin sits within one minor of the k3s server version, per kubectl's
   supported skew policy. `v1.34.11` (exact minor match) is the default; `v1.35.8`
   is acceptable headroom.
2. The `VERSION SKEW` comment records the **concrete server version this pin was matched
   to and the date it was checked** (`v1.34.3+k3s1`, checked 2026-08-31 — pi-cluster
   `ARCHITECTURE.md:39`), so the next bump compares against a recorded baseline instead
   of re-deriving one.
3. Both arch `KUBECTL_SHA` values are upstream's own for the pinned version, from
   `https://dl.k8s.io/release/<version>/bin/linux/<arch>/kubectl.sha256` — the source
   the Dockerfile comment already names. Fetch them; do not trust any value quoted in
   an issue or a spec.

Out of scope: the pi-cluster image-tag bump that consumes the corrected image
(pi-cluster's PR, not this repo's), and any change to what the dispatcher runs.

## 9. Task breakdown · [O — Operations]

### T01 pin-matches-server

One file, three moves, all in `docker/dispatcher.Dockerfile`:

- `ARG KUBECTL_VERSION` moves to a version within one minor of `v1.34.3+k3s1`.
- The existing `VERSION SKEW` comment block gains the matched-server record: the
  concrete version (`v1.34.3+k3s1`) and the check date (`2026-08-31`), in a `#` comment
  line containing the word `matched`.
- Both `KUBECTL_SHA` values (amd64, arm64) become upstream's published sha256 for the
  pinned version. Everything else in the file stays byte-identical — this task changes
  the pin, its provenance record, and its checksums, nothing else.

## 10. Acceptance criteria (EARS) · [O — Operations made testable]

- **ac1** — WHEN the gate parses `ARG KUBECTL_VERSION` and the k3s server version
  recorded in the file's comments, the pin's minor version SHALL be within one of the
  recorded server's minor version.
- **ac2** — The file SHALL contain a comment line recording the matched server version
  (`v1.X.Y+k3sN` form) together with a `YYYY-MM-DD` check date, on a line containing
  the word `matched`.
- **ac3** — FOR EACH arch in {amd64, arm64}, the `KUBECTL_SHA` value SHALL equal the
  sha256 published at `dl.k8s.io/release/<pin>/bin/linux/<arch>/kubectl.sha256`,
  fetched at verification time; WHEN dl.k8s.io is unreachable the check SHALL fail
  closed rather than assume.

## 11. Verification — the gates

Per-task: `tasks/T01-pin-matches-server/verify.sh` checks ac1–ac3 against the real
Dockerfile (ac3 live against upstream). The spec-level `verify.sh` is convergence-only.

The gate encodes the **invariant** (skew vs. the recorded server, checksums vs.
upstream), not the answer key: a future bump that moves pin + record + checksums
together stays green; any one of the three moving alone goes red. Mutant corpus:
`tasks/T01-pin-matches-server/mutants/` — one per assertion id.

## 14. Changelog

- **v1.0 (2026-09-01)** — Built by the qwen loop (red attempt 1, green attempt 2).
  First live run of both 20260831u/v instruments: in-loop selftest at first green
  `killed=3 survivor=0 wrong-reason=0 hung=0`; work sensitivity **4/4 NOTICED**
  (revert-hunk + drop-line on the ARG and both sha lines; the added comment line
  correctly skipped as inert). Judge (codex): 0 accepted, 1 gate-gap
  `scope-byte-identity-ungated` — §9's "everything else stays byte-identical" is
  promised but not gated; left report-only, escalated in the PR. Authoring lesson
  banked in v0.2: the spec header's `Tools:` field is a list the preflight executes
  (`command -v` per word), not prose — a parenthetical there refused the first launch.
