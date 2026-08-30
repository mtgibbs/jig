"""Intent parser for dispatcher."""
from __future__ import annotations
import os
import re

VERBS = {"fix"}

ACTIVE_DEADLINE_SECONDS = 1800
TTL_SECONDS_AFTER_FINISHED = 3600


def parse_intent(text: str) -> dict | None:
    """Parse a plain-text intent string into a structured intent dict.

    Expected form: '@<mention> fix <repo> <spec> [<strategy>]'

    The strategy is one OPTIONAL trailing field. Four fields still yield
    build-converge, which is what every caller that exists today sends. Six or
    more is still a parse failure: widening by one optional field must not turn
    this into a permissive parser, because an unbounded tail means a typo
    silently becomes a strategy name.

    Returns:
        Dict with keys verb, repo, spec, strategy or None on parse failure.
    """
    if text is None:
        return None

    text = text.strip()
    if not text:
        return None

    parts = text.split()
    if len(parts) not in (4, 5):
        return None

    mention, verb, repo, spec = parts[:4]
    strategy = parts[4] if len(parts) == 5 else "build-converge"

    if not mention.startswith("@"):
        return None

    if verb not in VERBS:
        return None

    return {
        "verb": verb,
        "repo": repo,
        "spec": spec,
        "strategy": strategy,
    }


def worker_image(strategy: str, default: str) -> str:
    """Resolve the worker image for a strategy.

    A MAP and nothing more: HARNESS_WORKER_IMAGE_<STRATEGY_UPPER_SNAKE> when set,
    otherwise the single HARNESS_WORKER_IMAGE the deployment already supplies.

    No policy, no fallback chain, no judgement. docs/design/fleet-dispatch.md names
    "the dispatcher stays describable in a paragraph" as a cliff, and image-selection
    policy is exactly the kind of code that erodes it.

    Why it matters that this is resolved from the REQUESTED strategy: build-codex on
    the opencode image is a run that cannot possibly succeed, and without this it fails
    as a confusing shell error inside the pod rather than as a dispatch-time refusal.
    """
    if not strategy:
        return default
    suffix = re.sub(r"[^A-Za-z0-9]", "_", strategy).upper()
    return os.environ.get(f"HARNESS_WORKER_IMAGE_{suffix}") or default


def worker_secret(strategy: str, default: str) -> str:
    """Resolve the Secret whose contents a worker of this strategy should receive.

    The same map as worker_image(), deliberately: HARNESS_WORKER_SECRET_<STRATEGY_UPPER_SNAKE>
    when set, otherwise the single HARNESS_WORKER_SECRET, otherwise nothing. Two maps that
    resolved per-strategy config differently would be two things to reason about, and the second
    one is always the one somebody forgets.

    Per strategy rather than one shared blob because the worker is the least-trusted component in
    the fleet: it runs a model that writes code into a working tree and then executes that
    repository's own deterministic gate. One secret for everyone means a build-codex worker holds
    the LiteLLM key it will never use, and a compromise of any family is a compromise of all.

    (Worded without naming the gate script: 20260828g ac8 greps this module for a gate invocation
    and does not strip comments, so prose ABOUT the loop reads as this module driving one. The
    check is blunt in the right direction — a dispatcher that grew a gate call would be the defect
    it is looking for — so the prose moves, not the check.)

    Falls back to the shared default or to NOTHING, never to a sibling strategy's secret. An empty
    return renders no envFrom at all, which is what keeps a laptop and a local container free of
    every Kubernetes concept in this module.

    This resolves a NAME. No credential value passes through here.
    """
    if not strategy:
        return default
    suffix = re.sub(r"[^A-Za-z0-9]", "_", strategy).upper()
    return os.environ.get(f"HARNESS_WORKER_SECRET_{suffix}") or default


def already_seen(ledger_path: str, event_id: str) -> bool:
    """Return True if event_id has been actioned before.

    A missing ledger file is not an error — a fresh dispatcher has actioned nothing.
    Tolerates unreadable or unwritable paths without raising.
    """
    if not ledger_path or not event_id:
        return False
    try:
        if not os.path.exists(ledger_path):
            return False
        with open(ledger_path, "r") as f:
            for line in f:
                if line.strip() == event_id:
                    return True
        return False
    except Exception:
        return False


def record_seen(ledger_path: str, event_id: str) -> None:
    """Record event_id as actioned by appending to ledger_path.

    Creates the file and any missing parent directories.
    Tolerates unreadable or unwritable paths without raising.
    """
    if not ledger_path or not event_id:
        return
    try:
        parent_dir = os.path.dirname(ledger_path)
        if parent_dir:
            os.makedirs(parent_dir, exist_ok=True)
        with open(ledger_path, "a") as f:
            f.write(event_id + "\n")
    except Exception:
        pass


def render_job(intent: dict, *, image: str, namespace: str, run_id: str, secret: str = "") -> dict:
    """Render a Kubernetes Job object as a plain Python dict.

    Args:
        intent: Dict with keys verb, repo, spec, strategy.
        image: Container image to run.
        namespace: Kubernetes namespace.
        run_id: Unique identifier for this run, used in the Job name.
        secret: Name of a Secret to expose to the container via envFrom. Empty means the
            key is OMITTED from the rendered object entirely — an envFrom of [] is a
            different object from no envFrom, and every deployment that exists today
            configures neither variable.

    Returns:
        Dict representing a Kubernetes Job object.
    """
    container = {
        "name": "run",
        "image": image,
        "env": [
            {
                "name": "REPO",
                "value": intent["repo"],
            },
            {
                "name": "SPEC",
                "value": intent["spec"],
            },
            {
                "name": "STRATEGY",
                "value": intent["strategy"],
            },
        ],
    }
    # Added only when it resolves. Assigning None or [] would satisfy a reader skimming for
    # "is envFrom handled" while changing the rendered object for every existing deployment.
    if secret:
        container["envFrom"] = [{"secretRef": {"name": secret}}]

    return {
        "apiVersion": "batch/v1",
        "kind": "Job",
        "metadata": {
            "namespace": namespace,
            "name": f"run-{run_id}",
        },
        "spec": {
            "activeDeadlineSeconds": ACTIVE_DEADLINE_SECONDS,
            "ttlSecondsAfterFinished": TTL_SECONDS_AFTER_FINISHED,
            "backoffLimit": 0,
            "template": {
                "spec": {
                    "nodeSelector": {
                        "harness-fleet": "true",
                    },
                    "restartPolicy": "Never",
                    "containers": [container],
                }
            },
        },
    }


def launch(job: dict, *, runner=None) -> int:
    """Serialize Job dict to JSON and apply it via kubectl.

    Args:
        job: Dict representing a Kubernetes Job object.
        runner: Optional command name override. If None, reads HARNESS_KUBECTL
                environment variable, defaulting to 'kubectl'.

    Returns:
        Command exit status. Never raises.
    """
    import json
    import subprocess
    import sys

    cmd_name = runner
    if cmd_name is None:
        cmd_name = os.environ.get("HARNESS_KUBECTL", "kubectl")

    # Inside the try: json.dumps() raises on a Job it cannot serialise, and this function is
    # documented as never raising. dispatch() has no handler, so an escape reaches the top of a
    # long-lived process.
    try:
        data = json.dumps(job)
        proc = subprocess.run(
            [cmd_name, "apply", "-f", "-"],
            input=data.encode("utf-8"),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
    except Exception as exc:
        # The runner could not be executed at all — a wrong image, or a typo'd HARNESS_KUBECTL.
        # Name it: this message is what points a reader at the image rather than at the Job body.
        print(
            "dispatch: could not execute %r: %s" % (cmd_name, exc),
            file=sys.stderr,
        )
        return 1

    if proc.returncode != 0:
        # The runner ran and refused. Its own words are the diagnostic; captured-and-discarded is
        # why a rejected Job used to reach a human as a bare exit code. stderr, never stdout — a
        # caller may be reading structured output from stdout.
        detail = (proc.stderr or b"").decode("utf-8", "replace").strip()
        print(
            "dispatch: %s apply rejected the Job (exit %d): %s"
            % (cmd_name, proc.returncode, detail or "(no output)"),
            file=sys.stderr,
        )

    # Silent on success. A dispatcher that logs every launch buries the one line that matters.
    return proc.returncode


def dispatch(
    intent: dict,
    event_id: str,
    *,
    ledger_path: str,
    registry_path: str | None = None,
    image: str,
    namespace: str,
) -> dict:
    """Perform the core dispatch flow: dedupe, render, launch, record.

    This is the idempotency mechanism. It takes an ALREADY-PARSED intent mapping
    and never sees a chat string.

    Order is load-bearing:
    1. Check the ledger — if already seen, return without launching.
    2. Render the Job.
    3. Launch the Job.
    4. Record the event id.
    5. Record the run in the registry (if registry_path supplied).

    Args:
        intent: Dict with keys verb, repo, spec, strategy (already parsed).
        event_id: Unique identifier for this event.
        ledger_path: Path to the ledger file.
        registry_path: Optional path to the registry file.
        image: Container image for the Job.
        namespace: Kubernetes namespace.

    Returns:
        Dict with keys:
        - 'intent': parsed intent dict
        - 'launched': bool indicating if a Job was launched
        - 'exit_code': int exit code from launch (0 or non-zero) or None
    """
    if already_seen(ledger_path, event_id):
        return {"intent": intent, "launched": False, "exit_code": None}

    run_id = event_id
    # The strategy that names the Job's STRATEGY env and the strategy that selects its
    # image are THE SAME value, read once from the intent being rendered. A run launched
    # with one strategy's name on the env and another strategy's image is the failure this
    # resolution exists to make impossible, and both halves read as correct in isolation.
    # ONE strategy, read once, feeding all three: the Job's STRATEGY env, the image that can run
    # it, and the credentials it is entitled to. A run launched under one strategy's name on
    # another strategy's image carrying a third strategy's secret is the failure this placement
    # makes impossible, and every one of those three halves reads as correct in isolation.
    strategy = intent.get("strategy", "")
    image = worker_image(strategy, image)
    secret = worker_secret(strategy, os.environ.get("HARNESS_WORKER_SECRET", ""))
    job = render_job(intent, image=image, namespace=namespace, run_id=run_id, secret=secret)
    exit_code = launch(job)

    record_seen(ledger_path, event_id)

    if registry_path:
        record = {
            "event_id": event_id,
            "repo": intent["repo"],
            "spec": intent["spec"],
            "strategy": intent["strategy"],
            "job_name": job["metadata"]["name"],
            "status": "launched" if exit_code == 0 else "failed",
        }
        record_run(registry_path, record)

    return {"intent": intent, "launched": True, "exit_code": exit_code}


def handle_event(
    text: str,
    event_id: str,
    *,
    ledger_path: str,
    registry_path: str | None = None,
    image: str,
    namespace: str,
) -> dict:
    """Parse intent and dispatch through the transport-agnostic core.

    Args:
        text: Plain text intent string (e.g. '@harness fix repo spec').
        event_id: Unique identifier for this event.
        ledger_path: Path to the ledger file.
        registry_path: Optional path to the registry file.
        image: Container image for the Job.
        namespace: Kubernetes namespace.

    Returns:
        Dict with keys:
        - 'intent': parsed intent dict or None
        - 'launched': bool indicating if a Job was launched
        - 'exit_code': int exit code from launch (0 or non-zero) or None
    """
    intent = parse_intent(text)
    if intent is None:
        return {"intent": None, "launched": False, "exit_code": None}

    return dispatch(
        intent,
        event_id,
        ledger_path=ledger_path,
        registry_path=registry_path,
        image=image,
        namespace=namespace,
    )


def record_run(registry_path: str, record: dict) -> None:
    """Append one run record to the registry.

    Creates the file and any missing parent directories.
    Tolerates unreadable or unwritable paths without raising.
    """
    if not registry_path or not record:
        return
    try:
        parent_dir = os.path.dirname(registry_path)
        if parent_dir:
            os.makedirs(parent_dir, exist_ok=True)
        with open(registry_path, "a") as f:
            import json

            f.write(json.dumps(record) + "\n")
    except Exception:
        pass


def read_runs(registry_path: str) -> list:
    """Return all run records from the registry as a list of dicts.

    A missing registry file is not an error — returns an empty list.
    Skips corrupt lines without failing the whole read.
    Tolerates unreadable paths without raising.
    """
    if not registry_path:
        return []
    try:
        if not os.path.exists(registry_path):
            return []
        records = []
        with open(registry_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    import json

                    record = json.loads(line)
                    records.append(record)
                except Exception:
                    continue
        return records
    except Exception:
        return []


def get_run(registry_path: str, event_id: str) -> dict | None:
    """Return the single record with the given event_id, or None if not found.

    Tolerates unreadable paths and missing files without raising.
    """
    if not registry_path or not event_id:
        return None
    try:
        if not os.path.exists(registry_path):
            return None
        with open(registry_path, "r") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    import json

                    record = json.loads(line)
                    if record.get("event_id") == event_id:
                        return record
                except Exception:
                    continue
        return None
    except Exception:
        return None


def launch_run(repo, spec, strategy, event_id, *, ledger_path, image, namespace, registry_path=None):
    """Dispatch a run using separate values instead of a parsed intent.

    Takes repo, spec and strategy as SEPARATE VALUES, builds the intent mapping
    directly from them, and returns the result of calling dispatch.

    Args:
        repo: Repository name.
        spec: Spec name.
        strategy: Strategy name; falls back to 'build-converge' if empty or None.
        event_id: Unique identifier for this event.
        ledger_path: Path to the ledger file.
        image: Container image for the Job.
        namespace: Kubernetes namespace.
        registry_path: Optional path to the registry file.

    Returns:
        Dict with keys:
        - 'intent': parsed intent dict
        - 'launched': bool indicating if a Job was launched
        - 'exit_code': int exit code from launch (0 or non-zero) or None
    """
    if not strategy:
        strategy = "build-converge"

    intent = {
        "verb": "fix",
        "repo": repo,
        "spec": spec,
        "strategy": strategy,
    }

    return dispatch(
        intent,
        event_id,
        ledger_path=ledger_path,
        registry_path=registry_path,
        image=image,
        namespace=namespace,
    )
