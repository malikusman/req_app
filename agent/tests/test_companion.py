"""The companion is the only agent path Rails calls on a completed conversation, so
its failure modes have to be legible rather than silent."""

import pytest

from app import companion


class TestNoModel:
    def test_returns_the_canned_line_and_says_why(self):
        out = companion.generate_companion_reply(
            user_message="thanks!", intent="casual", language="en", context={}
        )

        assert out["reply"] == companion.FALLBACK
        assert out["generated_by"] == "deterministic"
        assert out["fallback_reason"] == "no_model"


class TestWithModel:
    """A bare string gave Rails no way to tell a real reply from the canned one, so a
    model failing every single turn looked exactly like one doing its job."""

    def _reply(self, monkeypatch, response=None, raises=None, is_truncated=False):
        monkeypatch.setattr(companion, "llm_configured", lambda: True)
        monkeypatch.setattr(companion, "truncated", lambda _r: is_truncated)
        monkeypatch.setattr(companion, "record_success", lambda: None)
        monkeypatch.setattr(companion, "record_failure", lambda: None)

        class _LLM:
            def invoke(self, _messages):
                if raises:
                    raise raises
                return response

        monkeypatch.setattr(companion, "build_chat_openai", lambda **_kw: _LLM())
        return companion.generate_companion_reply(
            user_message="how do I chase approvals?", intent="ask", language="en", context={}
        )

    def test_uses_the_model_reply(self, monkeypatch):
        class R:
            content = '{"reply": "Try a follow-up cadence."}'

        out = self._reply(monkeypatch, response=R())

        assert out["reply"] == "Try a follow-up cadence."
        assert out["generated_by"] == "llm"
        assert out["fallback_reason"] is None

    def test_handles_a_fenced_json_block(self, monkeypatch):
        class R:
            content = '```json\n{"reply": "Fenced but fine."}\n```'

        assert self._reply(monkeypatch, response=R())["reply"] == "Fenced but fine."

    def test_falls_back_with_a_reason_when_the_model_returns_nothing(self, monkeypatch):
        class R:
            content = '{"reply": "   "}'

        out = self._reply(monkeypatch, response=R())

        assert out["reply"] == companion.FALLBACK
        assert out["fallback_reason"] == "empty_reply"

    def test_reports_truncation_rather_than_looking_like_a_bad_answer(self, monkeypatch):
        class R:
            content = '{"reply": "half a sen'

        out = self._reply(monkeypatch, response=R(), is_truncated=True)

        assert out["generated_by"] == "deterministic"
        assert out["fallback_reason"].startswith("truncated_at_")

    def test_an_exception_is_named_and_never_raised(self, monkeypatch):
        # A bug of ours must not break inbound message handling.
        out = self._reply(monkeypatch, raises=TypeError("unexpected keyword"))

        assert out["reply"] == companion.FALLBACK
        assert out["fallback_reason"] == "error: TypeError"

    def test_does_not_hardcode_a_tiny_token_cap(self, monkeypatch):
        # It was pinned at 400, which a reasoning model spends on thinking alone,
        # returning nothing at all.
        seen = {}
        monkeypatch.setattr(companion, "llm_configured", lambda: True)
        monkeypatch.setattr(companion, "truncated", lambda _r: False)
        monkeypatch.setattr(companion, "record_success", lambda: None)

        class R:
            content = '{"reply": "ok"}'

        class _LLM:
            def invoke(self, _messages):
                return R()

        def _factory(**kw):
            seen.update(kw)
            return _LLM()

        monkeypatch.setattr(companion, "build_chat_openai", _factory)
        companion.generate_companion_reply(
            user_message="hi", intent="casual", language="en", context={}
        )

        assert seen["max_tokens"] == companion.settings.openai_max_tokens
        assert seen["max_tokens"] > 400


class TestAskIntentPrioritisesAnswering:
    """A companion that redirects to "add this to my interview" instead of answering
    a direct question is not much use. Observed against a local model: the reply to
    "how do I chase overdue approvals faster?" spent itself entirely on the nudge."""

    def _system_prompt(self, monkeypatch, intent):
        captured = {}
        monkeypatch.setattr(companion, "llm_configured", lambda: True)
        monkeypatch.setattr(companion, "truncated", lambda _r: False)
        monkeypatch.setattr(companion, "record_success", lambda: None)

        class R:
            content = '{"reply": "ok"}'

        class _LLM:
            def invoke(self, messages):
                captured["system"] = messages[0].content
                return R()

        monkeypatch.setattr(companion, "build_chat_openai", lambda **_kw: _LLM())
        companion.generate_companion_reply(
            user_message="how do I chase overdue approvals faster?",
            intent=intent, language="en", context={},
        )
        return captured["system"]

    def test_ask_is_told_to_answer_before_nudging(self, monkeypatch):
        system = self._system_prompt(monkeypatch, "ask")

        assert "Answer their question first" in system
        assert "Only after that" in system

    def test_other_intents_keep_the_nudge_front_and_centre(self, monkeypatch):
        system = self._system_prompt(monkeypatch, "share")

        assert "Answer their question first" not in system
        assert "add this to my interview" in system
