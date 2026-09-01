#!/usr/bin/env bash
# Gate for T01-pin-matches-server (20260901a-kubectl-skew-pin).
#
# The invariant, not the answer key: whatever version the pin holds, it must sit within
# one minor of the k3s server version RECORDED IN THE SAME FILE, that record must exist
# with its check date (an undated match is a match that rots silently), and the two
# arch checksums must be upstream's own for the pinned version, fetched live from
# dl.k8s.io. ac3 needs network and FAILS CLOSED without it: a checksum check that
# passes offline is not a checksum check.
set -uo pipefail
T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../../../.." && pwd -P)"
DF="$R/docker/dispatcher.Dockerfile"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

[ -f "$DF" ] || { no "ac1: docker/dispatcher.Dockerfile is missing"; echo "VERIFY: failures above" >&2; exit 1; }

PIN="$(sed -n 's/^ARG KUBECTL_VERSION=\(v[0-9][0-9.]*\)[[:space:]]*$/\1/p' "$DF" | head -1)"
SRV="$(grep -E '^#' "$DF" | grep -oE 'v1\.[0-9]+\.[0-9]+\+k3s[0-9]+' | head -1)"

# ── ac1: the pin sits within kubectl's supported ±1-minor skew of the recorded server ──
if [ -z "$PIN" ]; then
  no "ac1: no ARG KUBECTL_VERSION pin found — nothing to judge the skew of"
elif [ -z "$SRV" ]; then
  no "ac1: no recorded k3s server version in the file — skew cannot be computed against a file that does not say what it was matched to"
else
  pm="$(printf '%s' "$PIN" | cut -d. -f2)"
  sm="$(printf '%s' "$SRV" | cut -d. -f2)"
  d=$((pm - sm)); [ "$d" -lt 0 ] && d=$((-d))
  if [ "$d" -le 1 ]; then
    ok "ac1: pin $PIN is within one minor of recorded server $SRV"
  else
    no "ac1: pin $PIN is $d minors from recorded server $SRV — outside kubectl's supported ±1 skew"
  fi
fi

# ── ac2: the match is recorded — concrete server version AND a check date ──
if grep -E '^#.*matched' "$DF" | grep -E 'v1\.[0-9]+\.[0-9]+\+k3s[0-9]+' | grep -qE '20[0-9][0-9]-[01][0-9]-[0-3][0-9]'; then
  ok "ac2: the VERSION SKEW comment records the matched server version with a check date"
else
  no "ac2: no comment line records 'matched ... v1.X.Y+k3sN ... YYYY-MM-DD' — the next bump re-derives what this one already knew"
fi

# ── ac3: both arch checksums are upstream's own for the pinned version ──
if [ -z "$PIN" ]; then
  no "ac3: no pin — nothing to verify checksums against"
else
  for arch in amd64 arm64; do
    want="$(curl -fsSL -m 20 "https://dl.k8s.io/release/$PIN/bin/linux/$arch/kubectl.sha256" 2>/dev/null)"
    have="$(sed -n "s/.*${arch}) KUBECTL_SHA=\([0-9a-f]\{64\}\).*/\1/p" "$DF" | head -1)"
    if [ -z "$want" ]; then
      no "ac3: upstream sha256 for $PIN/$arch unreachable — this check needs dl.k8s.io and fails closed without it"
    elif [ -z "$have" ]; then
      no "ac3: no 64-hex KUBECTL_SHA found for $arch in the Dockerfile"
    elif [ "$want" = "$have" ]; then
      ok "ac3: $arch checksum matches upstream for $PIN"
    else
      no "ac3: $arch checksum is not upstream's for $PIN — a bumped pin with stale checksums breaks the build, or verifies the wrong binary"
    fi
  done
fi

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: T01 all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2
exit 1
