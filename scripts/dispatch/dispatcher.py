"""Intent parser for dispatcher."""
from __future__ import annotations

VERBS = {"fix"}


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
