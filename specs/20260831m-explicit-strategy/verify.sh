#!/usr/bin/env bash
# Gate for 20260831m-explicit-strategy. Single-task spec: one gate, no pend.
# Behavioral through the module's API with dispatcher.launch monkeypatched to a recorder;
# the API leg boots the REAL api.py with a no-op fake kubectl. dispatch-core is the
# separate regression control.
set -uo pipefail

T="$(cd "$(dirname "$0")" && pwd -P)"
R="$(cd "$T/../.." && pwd -P)"
DP="$R/scripts/dispatch/dispatcher.py"
AP="$R/scripts/dispatch/api.py"

fail=0
ok(){ echo "  PASS  $1"; }
no(){ echo "  FAIL  $1" >&2; fail=1; }

W="$(mktemp -d)"; W="$(cd "$W" && pwd -P)"
SRV=""
cleanup(){ [ -n "$SRV" ] && kill "$SRV" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT

# One python run does ac1/ac2/ac3/ac5/ac6; it prints VERDICT lines the shell asserts on.
py_out="$( cd "$R/scripts/dispatch" && HARNESS_LEDGER="$W" python3 - "$W" <<'EOF'
import json, os, sys
import dispatcher

W = sys.argv[1]
calls = []
def fake_launch(job, **kw):
    calls.append(job)
    return 0
dispatcher.launch = fake_launch

def run(strategy, event_id, allow, ledger="ledger.jsonl"):
    if allow is None:
        os.environ.pop("HARNESS_STRATEGIES", None)
    else:
        os.environ["HARNESS_STRATEGIES"] = allow
    return dispatcher.launch_run(
        "r", "s", strategy, event_id,
        ledger_path=f"{W}/{ledger}", image="img:default",
        namespace="ns", registry_path=f"{W}/registry.jsonl")

# ac1/ac2: enforced refusal — no launch, marked refused, unlike a duplicate
r1 = run("build-codex", "e-refuse", "build-converge")
print("V ac1_launched", r1.get("launched"), len(calls))
print("V ac2_refused", "refused" in r1)

# ac3: the refusal wrote no ledger — the SAME event id launches once configured
ledger = ""
try:
    ledger = open(f"{W}/ledger.jsonl").read()
except FileNotFoundError:
    pass
print("V ac3_ledger_clean", "e-refuse" not in ledger)
r2 = run("build-codex", "e-refuse", "build-converge build-codex")
print("V ac3_retry_launched", r2.get("launched"), len(calls))

# ac2b: a genuine duplicate is NOT marked refused
r3 = run("build-codex", "e-refuse", "build-converge build-codex")
print("V ac2b_dup", r3.get("launched"), "refused" in r3)

# ac5: listed vs unset render the identical Job — SAME event id (the run id names the
# Job), separate ledgers so the second is not deduped away
calls.clear()
run("build-converge", "e-same", "build-converge", ledger="l-a.jsonl")
run("build-converge", "e-same", None, ledger="l-b.jsonl")
print("V ac5_identical", len(calls) == 2 and calls[0] == calls[1])

# ac6: unset = legacy no-enforcement, any strategy dispatches
r4 = run("totally-novel", "e-legacy", None)
print("V ac6_legacy", r4.get("launched"))
EOF
)" || no "the python leg raised: $py_out"

v(){ printf '%s\n' "$py_out" | grep "^V $1 " | head -1; }

case "$(v ac1_launched)" in "V ac1_launched False 0") ok "ac1: unlisted strategy launches nothing (runner never called)";; *) no "ac1: $(v ac1_launched)";; esac
case "$(v ac2_refused)" in "V ac2_refused True") ok "ac2: the refusal is marked refused";; *) no "ac2: $(v ac2_refused)";; esac
case "$(v ac3_ledger_clean)" in "V ac3_ledger_clean True") ok "ac3: the refusal wrote no ledger entry";; *) no "ac3: the refusal poisoned the ledger — $(v ac3_ledger_clean)";; esac
case "$(v ac3_retry_launched)" in "V ac3_retry_launched True 1") ok "ac3: the SAME event id launches after configuration";; *) no "ac3: post-fix retry did not launch — $(v ac3_retry_launched)";; esac
case "$(v ac2b_dup)" in "V ac2b_dup False False") ok "ac2: a duplicate is not refused — the two states stay distinguishable";; *) no "ac2: duplicate/refusal conflated — $(v ac2b_dup)";; esac
case "$(v ac5_identical)" in "V ac5_identical True") ok "ac5: listed and unset render the identical Job (dict equality)";; *) no "ac5: the allowlist changed the rendered Job — $(v ac5_identical)";; esac
case "$(v ac6_legacy)" in "V ac6_legacy True") ok "ac6: unset allowlist keeps today's behavior (control)";; *) no "ac6: legacy path broke — $(v ac6_legacy)";; esac

# ── ac4: the API answers a refusal as 422 naming strategy + variable; 202 still means launch ──
KUBECTL="$W/kubectl"; printf '#!/usr/bin/env bash\nexit 0\n' > "$KUBECTL"; chmod +x "$KUBECTL"
PORT=$(( 21000 + RANDOM % 20000 ))
TOK="gate-test-token"
( cd "$R/scripts/dispatch" && \
  HARNESS_API_TOKEN="$TOK" HARNESS_LEDGER_PATH="$W/api-ledger.jsonl" \
  HARNESS_REGISTRY_PATH="$W/api-registry.jsonl" HARNESS_KUBECTL="$KUBECTL" \
  HARNESS_STRATEGIES="build-converge" DISPATCH_PORT="$PORT" python3 api.py >/dev/null 2>&1 ) &
SRV=$!
_up=0
for _i in $(seq 1 50); do
  curl -s -o /dev/null "http://127.0.0.1:$PORT/runs" 2>/dev/null && { _up=1; break; }
  sleep 0.1
done
if [ "$_up" != 1 ]; then
  no "ac4: api.py did not come up on :$PORT"
else
  body="$(curl -s -o "$W/resp" -w '%{http_code}' -X POST -H "Authorization: Bearer $TOK" \
    -H 'Content-Type: application/json' -d '{"repo":"r","spec":"s","strategy":"build-codex"}' \
    "http://127.0.0.1:$PORT/runs")"
  [ "$body" = 422 ] \
    && ok "ac4: an unlisted strategy answers 422" \
    || no "ac4: expected 422, got $body — $(cat "$W/resp")"
  grep -q 'build-codex' "$W/resp" && grep -q 'HARNESS_STRATEGIES' "$W/resp" \
    && ok "ac4: the body names the strategy and the enabling variable" \
    || no "ac4: body does not name strategy+variable: $(cat "$W/resp")"
  code2="$(curl -s -o "$W/resp2" -w '%{http_code}' -X POST -H "Authorization: Bearer $TOK" \
    -H 'Content-Type: application/json' -d '{"repo":"r","spec":"s","strategy":"build-converge"}' \
    "http://127.0.0.1:$PORT/runs")"
  [ "$code2" = 202 ] \
    && ok "ac4: a listed strategy still launches (202)" \
    || no "ac4: expected 202 for the listed strategy, got $code2 — $(cat "$W/resp2")"
fi

# ── ac7: the doc states the rule ──
grep -q 'HARNESS_STRATEGIES' "$R/docs/executors.md" \
  && ok "ac7: docs/executors.md documents the allowlist" \
  || no "ac7: docs/executors.md does not mention HARNESS_STRATEGIES"

# ── ac8 ──
python3 -m py_compile "$DP" "$AP" 2>/dev/null \
  && ok "ac8: dispatcher.py and api.py compile" \
  || no "ac8: py_compile fails"

echo
[ "$fail" -eq 0 ] && { echo "VERIFY: all checks passed"; exit 0; }
echo "VERIFY: failures above" >&2; exit 1
