"""Tolerant JSON extraction for LLM replies.

Parse failures must not be treated like transport outages until a single
reformat retry has also failed.
"""

from __future__ import annotations

import json
import re
from typing import Any


class LlmJsonParseError(ValueError):
    """Raised when the model reply cannot be parsed as a JSON object."""


_FENCE_RE = re.compile(r"^```(?:json)?\s*\n?(.*?)\n?```\s*$", re.DOTALL | re.IGNORECASE)


def extract_json_object(content: str | None) -> dict[str, Any]:
    if content is None:
        raise LlmJsonParseError("empty LLM content")

    text = content.strip()
    if not text:
        raise LlmJsonParseError("empty LLM content")

    fenced = _FENCE_RE.match(text)
    if fenced:
        text = fenced.group(1).strip()
    elif text.startswith("```"):
        # Partial / trailing fence — strip opening fence line and optional closing.
        parts = text.split("```")
        if len(parts) >= 2:
            inner = parts[1]
            if inner.lstrip().lower().startswith("json"):
                inner = inner.lstrip()[4:]
            text = inner.strip()

    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end <= start:
            raise LlmJsonParseError("no JSON object in LLM content") from None
        try:
            payload = json.loads(text[start : end + 1])
        except json.JSONDecodeError as exc:
            raise LlmJsonParseError(str(exc)) from exc

    if not isinstance(payload, dict):
        raise LlmJsonParseError(f"expected JSON object, got {type(payload).__name__}")
    return payload
