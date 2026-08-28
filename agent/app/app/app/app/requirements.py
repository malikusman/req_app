"""Drafting questions from a consultant's stated need, and judging when it's met.

The consultant says what they need to know. This turns that into questions an
employee can actually answer, and after each answer decides whether the need is
settled or what is still missing.

Both halves fail safe, in opposite directions, deliberately:

- Drafting falls back to a single plainly-worded question built from the statement.
  A consultant who stated a need and got nothing would have to state it again.
- Judging falls back to NOT satisfied. Wrongly closing a requirement loses the
  consultant's question silently; wrongly leaving it open costs at most one more
  question, and the caps bound that.
"""

import json
import re
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage

from app.circuit_breaker import record_failure, record_success
from app.json_parse import extract_json_object
from app.openai_factory import build_chat_openai, llm_configured

MAX_DRAFT = 3


def draft_questions(payload: dict[str, Any]) -> dict[str, Any]:
    """payload: {statement, max_questions, already_asked, package, profile, language}."""
    limit = max(1, min(int(payload.get("max_questions") or 1), MAX_DRAFT))

    if not llm_configured():
        return _fallback_draft(payload, reason="no_model")

    try:
        parsed = _call(_draft_prompt(payload, limit))
    except Exception as exc:  # noqa: BLE001
        return _fallback_draft(payload, reason=f"llm_failed: {type(exc).__name__}")

    questions = []
    for item in (parsed.get("questions") or [])[:limit]:
        if not isinstance(item, dict):
            continue
        body = str(item.get("body") or "").strip()
        if not body:
            continue
        questions.append(
            {
                "body": body[:500],
                "rationale": str(item.get("rationale") or "").strip()[:300],
            }
        )

    if not questions:
        return _fallback_draft(payload, reason="empty_llm_output")

    return {"questions": questions, "generated_by": "llm"}


def evaluate_requirement(payload: dict[str, Any]) -> dict[str, Any]:
    """payload: {statement, answers: [{question, answer}], language}."""
    answers = [a for a in (payload.get("answers") or []) if a.get("answer")]

    if not answers:
        return {"satisfied": False, "missing_aspects": ["No answer received yet."],
                "generated_by": "deterministic"}

    if not llm_configured():
        return _fallback_judgement(reason="no_model")

    try:
        parsed = _call(_judge_prompt(payload, answers))
    except Exception as exc:  # noqa: BLE001
        return _fallback_judgement(reason=f"llm_failed: {type(exc).__name__}")

    if not isinstance(parsed, dict) or "satisfied" not in parsed:
        return _fallback_judgement(reason="unusable_llm_output")

    missing = [str(m).strip()[:200] for m in (parsed.get("missing_aspects") or []) if str(m).strip()]
    return {
        "satisfied": bool(parsed.get("satisfied")) and not missing,
        "missing_aspects": missing[:5],
        "generated_by": "llm",
    }


# --------------------------------------------------------------------------- #
# prompts
# --------------------------------------------------------------------------- #


def _draft_prompt(payload: dict[str, Any], limit: int) -> str:
    package = payload.get("package") or {}
    profile = payload.get("profile") or {}
    asked = payload.get("already_asked") or []

    asked_block = ""
    if asked:
        asked_block = "\nAlready asked — do not repeat these:\n" + "\n".join(f"- {q}" for q in asked[:8])

    return f"""A consultant reviewing a discovery interview needs more information. Turn what
they said into questions for the employee.

The employee: {profile.get('name') or 'unknown'} — {profile.get('role_title') or 'unknown role'},
{profile.get('department') or 'unknown'}.

What the interview already concluded:
{json.dumps(package, ensure_ascii=False)[:2500]}

What the consultant needs to know, in their words:
"{payload.get('statement')}"
{asked_block}

Write at most {limit} question(s) in {payload.get('language', 'en')} (ISO 639-1).

Rules:
- The employee is not the consultant. Never mention consultants, reviews, reports or
  requirements — ask as the assistant they have been chatting with.
- ONE clause per question, answerable in a sentence. No compound questions.
- Plain words. No jargon, nothing they would have to decode.
- Ask only what the consultant's need actually requires. Fewer is better: if one
  question covers it, write one.
- Do not re-ask what the interview already established above.

Respond with JSON only:
{{"questions": [{{"body": "the question", "rationale": "what it settles for the consultant"}}]}}"""


def _judge_prompt(payload: dict[str, Any], answers: list[dict[str, Any]]) -> str:
    transcript = "\n\n".join(
        f"Q: {a.get('question')}\nA: {a.get('answer')}" for a in answers
    )
    return f"""Decide whether a consultant's information need has been met.

What they needed to know:
"{payload.get('statement')}"

What the employee has said so far:
{transcript[:3000]}

Be strict but not pedantic. Satisfied means someone reading these answers would have
what the consultant asked for — not that every detail is perfect. If something
material is genuinely missing, name it briefly.

Respond with JSON only:
{{"satisfied": true, "missing_aspects": []}}"""


def _call(system: str) -> dict[str, Any]:
    llm = build_chat_openai(temperature=0.2, json_mode=True)
    try:
        response = llm.invoke([SystemMessage(content=system), HumanMessage(content="Respond now.")])
        parsed = extract_json_object(response.content)
        record_success()
        return parsed
    except Exception:
        record_failure()
        raise


# --------------------------------------------------------------------------- #
# fallbacks
# --------------------------------------------------------------------------- #

_SENTENCE = re.compile(r"[.!?]\s")


def _fallback_draft(payload: dict[str, Any], reason: str) -> dict[str, Any]:
    """One question, built from the statement itself.

    Deliberately quotes the consultant's words rather than paraphrasing: without a
    model, a paraphrase would be a guess, and a slightly stiff question that asks
    the right thing beats a smooth one that asks the wrong thing.
    """
    statement = str(payload.get("statement") or "").strip()
    first = _SENTENCE.split(statement)[0].strip().rstrip(".?!") if statement else ""
    body = (
        f"Could you tell me a bit more about {first[0].lower() + first[1:]}?"
        if first
        else "Could you tell me a bit more about your work?"
    )
    return {
        "questions": [
            {"body": body[:500], "rationale": "Drafted without a language model, from the stated need."}
        ],
        "generated_by": "deterministic",
        "fallback_reason": reason,
    }


def _fallback_judgement(reason: str) -> dict[str, Any]:
    # Not satisfied: wrongly closing a requirement loses the consultant's question
    # silently, while leaving it open costs at most one more question.
    return {
        "satisfied": False,
        "missing_aspects": ["Could not be assessed automatically — review the answer yourself."],
        "generated_by": "deterministic",
        "fallback_reason": reason,
    }
