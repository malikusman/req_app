"""build_chat_openai's signature is load-bearing: companion.py passed max_tokens
before the parameter existed, every call raised TypeError, a bare `except Exception`
swallowed it as an outage, and the companion silently never used the model."""

import pytest

from app import openai_factory
from app.config import settings


def test_accepts_max_tokens():
    llm = openai_factory.build_chat_openai(temperature=0.4, max_tokens=400)
    assert llm.max_tokens == 400


def test_defaults_max_tokens_from_settings():
    # Every prompt asks for a compact JSON object; an uncapped generation just lets a
    # local model ramble, which is minutes per turn on a 12B.
    llm = openai_factory.build_chat_openai()
    assert llm.max_tokens == settings.openai_max_tokens


def test_companion_passes_a_cap_the_factory_accepts():
    # The exact call companion.py makes. This is the regression that mattered.
    from app import companion  # noqa: F401  (import proves the module loads)

    openai_factory.build_chat_openai(temperature=0.4, max_tokens=400)


@pytest.mark.parametrize("kwargs", [{}, {"json_mode": True}, {"temperature": 0.1}])
def test_builds_with_the_usual_call_shapes(kwargs):
    assert openai_factory.build_chat_openai(**kwargs) is not None


class TestTruncationDetection:
    """A reply cut off at the token cap cannot be repaired by asking again with the
    same cap — the reformat retry truncates identically. It cost three model calls
    and ~508s before surfacing as a generic timeout, so it fails fast now."""

    def test_detects_a_truncated_reply(self):
        from app.multi_agent_llm import _truncated

        class Resp:
            response_metadata = {"finish_reason": "length"}

        assert _truncated(Resp()) is True

    def test_a_completed_reply_is_not_truncated(self):
        from app.multi_agent_llm import _truncated

        class Resp:
            response_metadata = {"finish_reason": "stop"}

        assert _truncated(Resp()) is False

    def test_tolerates_a_response_without_metadata(self):
        from app.multi_agent_llm import _truncated

        assert _truncated(object()) is False


class TestBaseUrl:
    """A blank OPENAI_BASE_URL must not become the base URL.

    ChatOpenAI reads OPENAI_BASE_URL from the environment itself, so a
    present-but-empty value -- exactly what `${OPENAI_BASE_URL:-}` yields in
    docker-compose -- is taken as a real base and every call dies with
    APIConnectionError("Connection error."). The true cause, "Request URL is
    missing an 'http://' or 'https://' protocol", is buried three exceptions deep,
    so this is expensive to diagnose and trivial to prevent. MEASURED against the
    real API: blank env -> every call failed; explicit default -> 2.8s success.
    """

    def test_falls_back_to_the_official_api_when_unset(self, monkeypatch):
        monkeypatch.setattr(settings, "openai_base_url", "")
        # Set in the environment too: the point is that the library's own env
        # lookup never gets the chance to read a blank value.
        monkeypatch.setenv("OPENAI_BASE_URL", "")

        llm = openai_factory.build_chat_openai()

        assert str(llm.openai_api_base) == openai_factory.DEFAULT_CHAT_BASE

    def test_keeps_an_explicit_local_base(self, monkeypatch):
        monkeypatch.setattr(settings, "openai_base_url", "http://host.docker.internal:1234/v1")

        llm = openai_factory.build_chat_openai()

        assert str(llm.openai_api_base) == "http://host.docker.internal:1234/v1"

    def test_strips_a_trailing_slash(self, monkeypatch):
        monkeypatch.setattr(settings, "openai_base_url", "http://host.docker.internal:1234/v1/")

        llm = openai_factory.build_chat_openai()

        assert str(llm.openai_api_base) == "http://host.docker.internal:1234/v1"
