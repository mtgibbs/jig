"""Intent parser for dispatcher."""
from __future__ import annotations
import os

VERBS = {"fix"}

ACTIVE_DEADLINE_SECONDS = 1800
TTL_SECONDS_AFTER_FINISHED = 3600


def parse_intent(text: str) -> dict | None:
    """Parse a plain-text intent string into a structured intent dict.

    Expected form: '@<mention> fix <repo> <spec>'
    Strategy is always 'build-converge' for v1.

    Returns:
        Dict with keys verb, repo, spec, strategy or None on parse failure.
    """
    if text is None:
        return None

    text = text.strip()
    if not text:
        return None

    parts = text.split()
    if len(parts) != 4:
        return None

    mention, verb, repo, spec = parts

    if not mention.startswith("@"):
        return None

    if verb not in VERBS:
        return None

    return {
        "verb": verb,
        "repo": repo,
        "spec": spec,
        "strategy": "build-converge",
    }


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


def render_job(intent: dict, *, image: str, namespace: str, run_id: str) -> dict:
    """Render a Kubernetes Job object as a plain Python dict.

    Args:
        intent: Dict with keys verb, repo, spec, strategy.
        image: Container image to run.
        namespace: Kubernetes namespace.
        run_id: Unique identifier for this run, used in the Job name.

    Returns:
        Dict representing a Kubernetes Job object.
    """
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
                    "containers": [
                        {
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
                    ],
                }
            },
        },
    }
