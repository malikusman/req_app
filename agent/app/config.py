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

    class Config:
        env_file = ".env"


settings = Settings()
