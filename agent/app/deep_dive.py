"""Questions the consultant should consider asking, and why.

The requirement loop already turns a consultant's stated need into questions an
employee can answer. This is the step before that: proposing the need itself.

It exists because of what discovery deliberately does NOT do. The interview stays
light -- it maps a person's areas, learns how each works, what snags, and what the
worst friction costs in time. It does not go deep, because depth spent on the wrong
friction is wasted and an interview cannot know which friction will matter until the
whole company's evidence is aggregated. By review time the consultant DOES know, so
that is the right moment to go deep, and the right person to decide where.

Two audiences in one output, which is the trap this shares with requirements.py:
`body` is written for the EMPLOYEE and must never mention consultants, reviews or
reports; `rationale` is written for the CONSULTANT and explains what the answer
would settle. Getting them the wrong way round produces a question nobody can
answer attached to a reason nobody needs.

Fails safe, and unusually well: the deterministic fallback is not a degraded
template but the single highest-value suggestion computed directly from the
dossier -- a friction with no time attached is the thing standing between a
finding and a figure, and spotting that needs no model at all.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage

from app.circuit_breaker import record_failure, record_success
from app.config import settings
from app.json_parse import extract_json_object
from app.openai_factory import build_chat_openai, llm_configured, truncated

MAX_SUGGESTIONS = 3
MAX_TRUNCATION_RETRIES = 1

# What a suggestion is trying to get. Kept short and closed so the consultant's
# list can be grouped and so a model cannot invent a category that means nothing.
KINDS = {
    "quantify",   # put a number on a friction we only have words for
    "mechanism",  # how the work actually happens, step by step
    "exception",  # what happens when it goes wrong, and how often
    "ownership",  # who decides, who is blocked, where it waits
    "scale",      # how much of it there is
}
DEFAULT_KIND = "mechanism"


def suggest_questions(payload: dict[str, Any]) -> dict[str, Any]:
    """payload: {package, dossier, profile, already_asked, max_suggestions, language}."""
    limit = max(1, min(int(payload.get("max_suggestions") or MAX_SUGGESTIONS), MAX_SUGGESTIONS))
    gaps = _quantification_gaps(payload.get("dossier") or {})

    if not llm_configured():
        return _fallback(gaps, limit, reason="no_model")

    try:
        parsed = _call(_prompt(payload, gaps, limit))
    except Exception as exc:  # noqa: BLE001 — a missing suggestion must not break review
        logging.getLogger(__name__).warning("deep-dive suggestion failed: %s", exc)
        return _fallback(gaps, limit, reason=f"llm_failed: {type(exc).__name__}")

    suggestions = []
    for item in (parsed.get("suggestions") or [])[:limit]:
        if not isinstance(item, dict):
            continue
        body = str(item.get("body") or "").strip()
        rationale = str(item.get("rationale") or "").strip()
        # A suggestion without a reason is just a question, and the consultant has no
        # way to judge whether it is worth one of their employee's few remaining
        # answers. Both halves or it is not a suggestion.
        if not body or not rationale:
            continue
        kind = str(item.get("kind") or "").strip().lower()
        suggestions.append(
            {
                "body": body[:500],
                "rationale": rationale[:300],
                "kind": kind if kind in KINDS else DEFAULT_KIND,
            }
        )

    if not suggestions:
        return _fallback(gaps, limit, reason="empty_llm_output")

    return {"suggestions": suggestions, "generated_by": "llm"}


# --------------------------------------------------------------------------- #
# what the interview left unquantified
# --------------------------------------------------------------------------- #


def _quantification_gaps(dossier: dict[str, Any]) -> list[dict[str, str]]:
    """Areas whose friction was captured but never costed.

    This is the gap that matters most: it is precisely the difference between "AP
    re-keying is painful" and "AP re-keying costs 170 hours a year", and it is the
    one gap that can be found with certainty rather than judgement.
    """
    slots = (dossier or {}).get("slots") or {}
    gaps = []
    for key, entry in slots.items():
        slot, _, area = str(key).partition("::")
        if slot != "friction" or not area:
            continue
        if f"friction_cost::{area}" in slots:
            continue
        gaps.append({"area": area, "friction": str(entry.get("value") or "")[:240]})
    return gaps


# --------------------------------------------------------------------------- #
# model path
# --------------------------------------------------------------------------- #


def _prompt(payload: dict[str, Any], gaps: list[dict[str, str]], limit: int) -> str:
    profile = payload.get("profile") or {}
    asked = [q for q in (payload.get("already_asked") or []) if q][:10]

    asked_block = ""
    if asked:
        asked_block = "\nAlready put to this employee — do not repeat or reword these:\n" + "\n".join(
            f"- {q}" for q in asked
        )

    gap_block = ""
    if gaps:
        lines = "\n".join(f"- {g['area']}: \"{g['friction']}\"" for g in gaps)
        gap_block = (
            "\nFrictions this person described but never put a time to. Getting a number "
            "here is what lets the report say what the problem costs, so prefer these "
            "over anything else:\n" + lines + "\n"
        )

    return f"""A consultant is reviewing what a discovery interview found, and is deciding
what else is worth asking this employee. Propose the questions.

The employee: {profile.get('name') or 'unknown'} — {profile.get('role_title') or 'unknown role'},
{profile.get('department') or 'unknown'}.

What the interview concluded:
{json.dumps(payload.get('package') or {}, ensure_ascii=False)[:2500]}

What it captured:
{json.dumps(payload.get('dossier') or {}, ensure_ascii=False)[:2500]}
{gap_block}{asked_block}

Propose at most {limit} question(s), best first, in {payload.get('language', 'en')} (ISO 639-1).

What makes a good one here:
- It goes DEEPER than the interview did — the interview already covered how the work
  runs and what snags. Ask about the specific mechanics, the exceptions, the volumes,
  who is waiting on whom.
- It would change what the report can say. If the answer would not sharpen a finding
  or put a number on one, do not propose it.
- Prefer a question that turns a described problem into a measured one.

Two different readers, do not mix them up:
- `body` is sent TO THE EMPLOYEE. Never mention consultants, reviews, reports or
  requirements — it reads as the assistant they were already chatting with. ONE
  clause, answerable in a sentence, plain words.
- `rationale` is read BY THE CONSULTANT. One sentence on what the answer would
  settle and why it is worth asking. Be concrete, not "this would give more insight".

kind is one of: {', '.join(sorted(KINDS))}.

Respond with JSON only:
{{"suggestions": [{{"body": "...", "rationale": "...", "kind": "quantify"}}]}}"""


def _call(system: str) -> dict[str, Any]:
    cap = settings.openai_max_tokens
    messages = [SystemMessage(content=system), HumanMessage(content="Respond now.")]

    for attempt in range(MAX_TRUNCATION_RETRIES + 1):
        llm = build_chat_openai(temperature=0.3, json_mode=True, max_tokens=cap)
        try:
            response = llm.invoke(messages)
            if truncated(response):
                if attempt < MAX_TRUNCATION_RETRIES:
                    cap *= 2
                    continue
                raise RuntimeError(f"suggestion reply cut off at max_tokens={cap}")
            parsed = extract_json_object(response.content)
            record_success()
            return parsed
        except Exception:
            record_failure()
            raise

    raise RuntimeError("exhausted truncation retries")


# --------------------------------------------------------------------------- #
# deterministic path
# --------------------------------------------------------------------------- #


def _fallback(gaps: list[dict[str, str]], limit: int, reason: str) -> dict[str, Any]:
    """The uncosted frictions, as questions. No model required.

    Worth noting this is not a consolation prize: an uncosted friction is the most
    valuable thing to ask about, and finding one is arithmetic. A consultant who
    gets only these has still been pointed at the right questions.
    """
    suggestions = [
        {
            # Deliberately phrased around the AREA, not the friction text. That text
            # is the employee's own words from mid-conversation ("the re-keying is
            # the worst part"), and splicing a clause into a question is what
            # produced broken grammar in the requirement drafter. The friction goes
            # in the rationale instead, where the consultant reads it and grammar
            # does not have to survive the splice.
            "body": (
                f"Roughly how much time does the {gap['area'].lower()} work "
                "take you in a typical week?"
            ),
            "rationale": (
                f"They described this on {gap['area']} — \"{_trim(gap['friction'])}\" — "
                "but never put a time to it, so the report cannot say what it costs."
            ),
            "kind": "quantify",
        }
        for gap in gaps[:limit]
    ]

    return {
        "suggestions": suggestions,
        "generated_by": "deterministic",
        "fallback_reason": reason,
    }


def _trim(friction: str) -> str:
    """The friction as the consultant should see it quoted back — short enough to
    scan in a list, and without a trailing full stop inside the quotes."""
    text = " ".join(str(friction or "").split()).rstrip(".")
    return text if len(text) <= 90 else text[:87].rstrip() + "..."
