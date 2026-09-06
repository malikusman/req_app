"""Post-discovery companion replies (non-interview).

The employee has finished their interview. This is the ordinary chat that follows:
tips, tool questions, things they want to mention. It must never re-interview them
— what to ask, and whether to reopen discovery at all, is decided in Rails.

Rails assembles the context (interview insights, memory facts, recent notes) and
this does the reasoning, matching how discovery already splits: Rails owns state,
the agent owns model calls.
"""

from __future__ import annotations

import json
import logging
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage

from app.circuit_breaker import record_failure, record_success
from app.config import settings
from app.json_parse import extract_json_object
from app.llm import OpenAIUnavailable
from app.openai_factory import build_chat_openai, llm_configured, truncated

FALLBACK = (
    "I'm here if you want tips, tools, or to share anything from your day. "
    'If it should count for the company report, say "add this to my interview".'
)

# One retry at a doubled cap. A reasoning model can spend its whole budget thinking
# and emit nothing, and re-asking at the same cap fails identically.
MAX_TRUNCATION_RETRIES = 1


def generate_companion_reply(
    *,
    user_message: str,
    intent: str,
    language: str,
    context: dict[str, Any],
) -> dict[str, Any]:
    """Returns {reply, generated_by, fallback_reason}.

    The reason matters: a bare string gave Rails no way to tell a real reply from the
    canned one, so a model that was failing every single turn looked exactly like a
    model doing its job. That is precisely how a broken drafting call stayed hidden
    for a whole scenario run.
    """
    if not llm_configured():
        return _fallback("no_model")

    # The promote nudge ("add this to my interview") earns its place when someone
    # volunteers something about their work — but on a direct question it crowds out
    # the answer, and a companion that redirects instead of helping is not much use.
    # An observed reply to "how do I chase overdue approvals faster?" spent itself
    # entirely on the nudge and never answered, so the nudge is secondary here.
    if intent == "ask":
        task = (
            "Answer their question first, with something concrete they could actually "
            "try — grounded in the context if it is relevant, and never invented. Only "
            "after that, and only if it fits naturally, may you note they can say "
            '"add this to my interview" to have something inform the company report.'
        )
    else:
        task = (
            "If they share work details, acknowledge them, and mention they can say "
            '"add this to my interview" to have it inform the company report.'
        )

    system = (
        "You are Worktruth's WhatsApp companion for an employee whose discovery "
        "interview is already complete. Be brief (2-5 short sentences), helpful and "
        "warm. Do NOT run a new interview and do NOT ask a list of discovery "
        "questions. Do NOT invent company systems or claim a tool is officially "
        f"recommended unless it appears in the context. {task} "
        f"Language: {language} (ISO 639-1). Intent hint: {intent}."
    )
    human = (
        f"Employee message: {user_message}\n"
        f"Context: {json.dumps(context, ensure_ascii=False)[:4000]}\n"
        'Respond as JSON: {"reply":"..."}'
    )
    messages = [SystemMessage(content=system), HumanMessage(content=human)]

    # Was hardcoded to 400, which is nowhere near enough for a reasoning model whose
    # thinking counts against the cap — it would burn the budget and return nothing.
    cap = settings.openai_max_tokens

    for attempt in range(MAX_TRUNCATION_RETRIES + 1):
        try:
            llm = build_chat_openai(temperature=0.4, max_tokens=cap)
            response = llm.invoke(messages)
            if truncated(response):
                if attempt < MAX_TRUNCATION_RETRIES:
                    cap *= 2
                    continue
                record_failure()
                return _fallback(f"truncated_at_{cap}")

            content = getattr(response, "content", "") or str(response)
            parsed = extract_json_object(content)
            record_success()
            reply = str(parsed.get("reply") or "").strip()
            return (
                {"reply": reply, "generated_by": "llm", "fallback_reason": None}
                if reply
                else _fallback("empty_reply")
            )
        except OpenAIUnavailable as exc:
            record_failure()
            return _fallback(f"unavailable: {exc}")
        except Exception as exc:  # noqa: BLE001 — a broken reply must not break inbound
            # Logged, and NOT counted as a model failure: a TypeError here is our bug,
            # not an outage, and feeding it to the circuit breaker took the whole
            # discovery path down with it. That is exactly how the missing max_tokens
            # parameter stayed hidden.
            logging.getLogger(__name__).exception("companion reply failed: %s", exc)
            return _fallback(f"error: {type(exc).__name__}")

    return _fallback("exhausted_retries")


def _fallback(reason: str) -> dict[str, Any]:
    return {"reply": FALLBACK, "generated_by": "deterministic", "fallback_reason": reason}
