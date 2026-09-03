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
from app.config import settings
from app.openai_factory import build_chat_openai, llm_configured, truncated

MAX_DRAFT = 3


class TruncatedReply(RuntimeError):
    """The model hit its token cap before producing usable output."""


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


# One retry with a doubled cap. A reasoning model can spend its whole budget
# thinking and emit nothing; re-asking at the same cap fails identically, so the
# only useful retry is a bigger one.
MAX_TRUNCATION_RETRIES = 1


def _call(system: str) -> dict[str, Any]:
    """Both of these calls silently fell back to a canned template when the model
    hit its cap — the consultant's stated need produced a stiff, echoed question and
    nothing said why. Detecting truncation and escalating recovers the real answer.
    """
    cap = settings.openai_max_tokens
    messages = [SystemMessage(content=system), HumanMessage(content="Respond now.")]

    for attempt in range(MAX_TRUNCATION_RETRIES + 1):
        llm = build_chat_openai(temperature=0.2, json_mode=True, max_tokens=cap)
        try:
            response = llm.invoke(messages)
            if truncated(response):
                if attempt < MAX_TRUNCATION_RETRIES:
                    cap *= 2
                    continue
                raise TruncatedReply(
                    f"model reply was still cut off at max_tokens={cap}; "
                    "the prompt asks for more output than the model will finish"
                )
            parsed = extract_json_object(response.content)
            record_success()
            return parsed
        except TruncatedReply:
            record_failure()
            raise
        except Exception:
            record_failure()
            raise

    raise TruncatedReply("exhausted truncation retries")


# --------------------------------------------------------------------------- #
# fallbacks
# --------------------------------------------------------------------------- #

_SENTENCE = re.compile(r"[.!?]\s")


# A consultant states a need in the FIRST person ("I need to know who signs off").
# Splicing that verbatim into a question addressed to the employee produced
# "Could you tell me a bit more about i need to know who signs off...?" — broken
# grammar and nonsensical to the person receiving it. These strip the framing so
# what remains is the subject of the need, not the consultant's narration of it.
_NEED_PREFIXES = re.compile(
    r"^\s*(?:i\s+(?:need|want|would\s+like)\s+to\s+(?:know|understand|find\s+out|check)"
    r"|i\s+(?:need|want)"
    r"|can\s+(?:you|we)\s+(?:find\s+out|check|confirm)"
    r"|please\s+(?:find\s+out|check|confirm|ask)"
    r"|find\s+out|check|confirm|ask\s+(?:them|him|her)?)"
    r"\s*(?:about|whether|if|that|:)?\s*",
    re.IGNORECASE,
)


def _need_subject(statement: str) -> str:
    """The thing being asked about, with the consultant's first-person framing removed."""
    first = _SENTENCE.split(statement)[0].strip() if statement else ""
    subject = _NEED_PREFIXES.sub("", first).strip().rstrip(".?!,;")
    # If stripping left nothing useful, fall back to the whole first clause.
    return subject or first.rstrip(".?!,;")


def _fallback_draft(payload: dict[str, Any], reason: str) -> dict[str, Any]:
    """One question, built from the statement itself.

    Deliberately grounded in the consultant's own words rather than paraphrasing:
    without a model, a paraphrase would be a guess, and a slightly stiff question
    that asks the right thing beats a smooth one that asks the wrong thing. But it
    must still read as a question TO THE EMPLOYEE, not as the consultant's note to
    themselves.
    """
    statement = str(payload.get("statement") or "").strip()
    subject = _need_subject(statement)
    body = (
        f"Could you tell me a bit more about {subject[0].lower() + subject[1:]}?"
        if subject
        else "Could you tell me a bit more about how that part of your work runs?"
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
