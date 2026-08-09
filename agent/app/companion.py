"""Post-discovery companion replies (non-interview)."""

from __future__ import annotations

import json
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage

from app.circuit_breaker import record_failure, record_success
from app.json_parse import extract_json_object
from app.llm import OpenAIUnavailable
from app.openai_factory import build_chat_openai, llm_configured


FALLBACK = (
    "I'm here if you want tips, tools, or to share anything from your day. "
    'If it should count for the company report, say "add this to my interview".'
)


def generate_companion_reply(
    *,
    user_message: str,
    intent: str,
    language: str,
    context: dict[str, Any],
) -> str:
    if not llm_configured():
        return FALLBACK

    system = (
        "You are Worktruth's WhatsApp companion after discovery is complete. "
        "Be brief (2-5 sentences). Do not run an interview. "
        "Do not invent company systems. "
        f"Language: {language}. Intent hint: {intent}."
    )
    human = (
        f"Employee message: {user_message}\n"
        f"Context: {json.dumps(context)[:4000]}\n"
        'Respond as JSON: {"reply":"..."}'
    )

    try:
        llm = build_chat_openai(temperature=0.4, max_tokens=400)
        raw = llm.invoke([SystemMessage(content=system), HumanMessage(content=human)])
        content = getattr(raw, "content", "") or str(raw)
        parsed = extract_json_object(content)
        record_success()
        reply = (parsed.get("reply") or "").strip()
        return reply or FALLBACK
    except (OpenAIUnavailable, Exception):  # noqa: BLE001
        record_failure()
        return FALLBACK
