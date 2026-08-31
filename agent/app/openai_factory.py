# Shared ChatOpenAI factory so local LM Studio and production OpenAI share one switch.
from __future__ import annotations

from urllib.parse import urlparse

from langchain_openai import ChatOpenAI

from app.config import settings


def llm_configured() -> bool:
    return bool(settings.openai_api_key.strip() or settings.openai_base_url.strip())


def _use_json_mode(requested: bool) -> bool:
    if not requested:
        return False
    if not settings.openai_json_mode:
        return False
    base = settings.openai_base_url.strip()
    if not base:
        return True
    host = urlparse(base).hostname or ""
    return host in ("api.openai.com",) or host.endswith(".openai.com")


def build_chat_openai(
    *,
    model: str | None = None,
    temperature: float = 0.4,
    json_mode: bool = False,
    max_tokens: int | None = None,
) -> ChatOpenAI:
    """max_tokens defaults to settings.openai_max_tokens (OPENAI_MAX_TOKENS).

    This parameter was missing while companion.py already passed it, so every
    companion reply raised TypeError, was swallowed by a bare `except Exception`,
    and returned the canned fallback — while also recording a circuit-breaker
    failure. The companion never once used the model.
    """
    kwargs: dict = {
        "model": model or settings.openai_model,
        "api_key": settings.openai_api_key.strip() or "lm-studio",
        "temperature": temperature,
        "max_tokens": max_tokens or settings.openai_max_tokens,
    }
    if settings.openai_base_url.strip():
        kwargs["base_url"] = settings.openai_base_url.rstrip("/")
    model_kwargs: dict = {}
    if _use_json_mode(json_mode):
        model_kwargs["response_format"] = {"type": "json_object"}

    if model_kwargs:
        kwargs["model_kwargs"] = model_kwargs

    effort = settings.openai_reasoning_effort.strip()
    if effort:
        # A first-class ChatOpenAI parameter — passing it through model_kwargs works
        # but warns. Only sent when configured: a non-reasoning model rejects it.
        kwargs["reasoning_effort"] = effort

    return ChatOpenAI(**kwargs)
