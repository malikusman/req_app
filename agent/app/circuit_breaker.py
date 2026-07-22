"""OpenAI circuit breaker shared with Rails via Redis key `openai:circuit_open`.

Both the Python agent and Rails `OpenaiCircuitBreaker` must use the same
`REDIS_URL` (DB /0). The agent owns windowed failure counting; Rails reads the
flag and may trip/reset on retryable outages. Fail-open on Redis errors.
"""

import time

import redis

from app.config import settings

_redis = None


def _client() -> redis.Redis:
    global _redis
    if _redis is None:
        _redis = redis.from_url(settings.redis_url, decode_responses=True)
    return _redis


def is_open() -> bool:
    try:
        return _client().get(settings.circuit_breaker_key) == "1"
    except redis.RedisError:
        return False


def record_failure() -> None:
    try:
        client = _client()
        key = "openai:error_window"
        now = int(time.time())
        client.zadd(key, {str(now): now})
        client.zremrangebyscore(key, 0, now - 300)
        total = client.zcard(key)
        if total >= 4:
            failures = sum(1 for _ in client.zrange(key, 0, -1))
            if failures >= 4 and total > 0 and (failures / total) >= 0.5:
                client.setex(settings.circuit_breaker_key, settings.circuit_breaker_ttl_seconds, "1")
    except redis.RedisError:
        pass


def record_success() -> None:
    try:
        _client().delete(settings.circuit_breaker_key)
    except redis.RedisError:
        pass
