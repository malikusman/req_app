from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    openai_api_key: str = ""
    openai_model: str = "gpt-4o-mini"
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
