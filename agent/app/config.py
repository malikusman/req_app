from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    openai_api_key: str = ""
    openai_model: str = "gpt-4.1-mini"
    # Empty → LangChain default (api.openai.com). Set for LM Studio e.g. http://host.docker.internal:1234/v1
    openai_base_url: str = ""
    # Disable strict JSON response_format for local servers that reject it
    openai_json_mode: bool = True
    # Reasoning budget for models that think before answering ("low" | "medium" |
    # "high" | "minimal"). EMPTY BY DEFAULT and only sent when set, because a
    # non-reasoning model rejects the parameter outright.
    #
    # This matters enormously for local reasoning models: reasoning tokens count
    # against max_tokens. On a simple synthetic prompt "low" was plenty (471
    # reasoning tokens, 52s). But MEASURED on a real turn once conversation history
    # accumulates, "low" still exhausted the cap (5997/6000 reasoning tokens, empty
    # content, finish_reason=length, 419s) while "minimal" on the identical turn
    # completed cleanly (2796 reasoning tokens, valid JSON, finish_reason=stop,
    # 366s). Use "minimal" for this model, not "low".
    openai_reasoning_effort: str = ""
    # Cap on generated tokens. Uncapped, a local model rambles (a realistic Gemma 12B
    # discovery turn measured 570s). But too tight is worse than uncapped: at 1200
    # the reply was cut off mid-JSON (finish_reason=length), which cannot parse, and
    # the reformat retry truncated identically — three model calls, ~508s, then a
    # generic timeout. MEASURED: this turn uses ~1000 completion tokens and finishes
    # in ~69s at 3000, stopping on its own.
    openai_max_tokens: int = 3000
    rails_internal_url: str = "http://rails:3000"
    internal_api_token: str = "dev-internal-token"
    redis_url: str = "redis://redis:6379/0"
    circuit_breaker_key: str = "openai:circuit_open"
    circuit_breaker_ttl_seconds: int = 300
    max_openai_retries: int = 2
    # LangSmith (BLK-4 easy-wins): set LANGSMITH_API_KEY to enable tracing
    langsmith_api_key: str = ""
    langsmith_project: str = "worktruth-agent"
    # Empty = auto (on when api key present); "true"/"false" to force
    langsmith_tracing: str = ""

    class Config:
        env_file = ".env"


settings = Settings()


def configure_langsmith() -> bool:
    """Enable LangSmith when an API key is present (unless explicitly disabled).

    LangChain/LangGraph pick up LANGSMITH_* env vars automatically for LLM traces.
    Returns True when tracing is enabled.
    """
    import os

    api_key = settings.langsmith_api_key.strip()
    if api_key:
        os.environ.setdefault("LANGSMITH_API_KEY", api_key)

    flag = settings.langsmith_tracing.strip().lower()
    if flag in ("0", "false", "no", "off"):
        return False
    if flag in ("1", "true", "yes", "on"):
        enabled = True
    else:
        enabled = bool(api_key)

    if not enabled:
        return False
    if not os.environ.get("LANGSMITH_API_KEY", "").strip():
        return False

    os.environ["LANGSMITH_TRACING"] = "true"
    os.environ.setdefault("LANGSMITH_PROJECT", settings.langsmith_project)
    return True
