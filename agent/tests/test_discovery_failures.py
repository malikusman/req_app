from unittest.mock import Mock

import httpx
import pytest
from fastapi.testclient import TestClient
from openai import RateLimitError, APITimeoutError

from app import interview_capture, main, multi_agent_graph, multi_agent_llm
from app.llm import OpenAIUnavailable


def quota_error(code="organization_spend_limit_exceeded"):
    response = httpx.Response(429, request=httpx.Request("POST", "https://api.openai.com/v1/chat/completions"))
    return RateLimitError("Spend limit exceeded", response=response,
                          body={"type": "insufficient_quota", "code": code})


@pytest.mark.parametrize("code", ["organization_spend_limit_exceeded", "insufficient_quota"])
def test_quota_is_not_a_transient_rate_limit(code):
    error = OpenAIUnavailable.from_exception(quota_error(code))
    assert error.code == "openai_quota_exceeded"
    assert not error.retryable


@pytest.mark.usefixtures("with_model")
def test_recorder_stops_immediately_on_quota_without_tripping_breaker(monkeypatch):
    model = Mock()
    model.invoke.side_effect = quota_error()
    monkeypatch.setattr(interview_capture, "_recording_model", lambda *args: model)
    failure = Mock()
    monkeypatch.setattr(interview_capture, "record_failure", failure)
    with pytest.raises(OpenAIUnavailable) as caught:
        interview_capture.capture_reply({"user_message": "outlook, Excel and our system"}, refresh_summary=False)
    assert not caught.value.retryable
    assert model.invoke.call_count == 1
    failure.assert_not_called()


@pytest.mark.usefixtures("with_model")
def test_question_writer_preserves_quota_classification(monkeypatch):
    model = Mock()
    model.invoke.side_effect = quota_error()
    monkeypatch.setattr(multi_agent_llm, "build_chat_openai", lambda **kwargs: model)
    with pytest.raises(OpenAIUnavailable) as caught:
        multi_agent_llm._talk("Ask one question", {"user_message": "helping the HR?"})
    assert caught.value.code == "openai_quota_exceeded"
    assert model.invoke.call_count == 1


def test_timeout_remains_retryable():
    error = OpenAIUnavailable.from_exception(APITimeoutError(request=httpx.Request("POST", "https://api.openai.com")))
    assert error.retryable
    assert error.code == "openai_unavailable"


def test_graph_and_http_endpoint_preserve_failure_reason(monkeypatch):
    graph = Mock()
    graph.invoke.side_effect = OpenAIUnavailable.from_exception(quota_error())
    monkeypatch.setattr(multi_agent_graph, "multi_agent_graph", graph)
    monkeypatch.setattr(main, "is_open", lambda: False)
    async def fake_executor(thread, source, state, multi, deadline, identity, revision):
        return multi_agent_graph.execute_multi_agent_turn(state)
    monkeypatch.setattr(main, "run_isolated", fake_executor)
    response = TestClient(main.app).post("/v1/threads/regression/turn", json={
        "user_message": "helping the HR? I mainly use outlook, Excel and our system",
        "source_message_id": 875, "multi_agent": True,
        "playbook": {"prompt_block": "Ask about daily work"},
    })
    assert response.status_code == 503
    assert response.json()["detail"] == {
        "error": "openai_quota_exceeded", "retryable": False,
        "reason": "OpenAI organization quota or spend limit exhausted",
    }


def test_short_answers_progress_across_consecutive_real_graph_turns():
    state = {"playbook_block": "Ask about daily work", "playbook_version": 1,
             "preferred_language": "en", "question_count": 0, "history": [],
             "profile": {"responsibilities": "helping the HR?", "primary_tools": ["outlook", "Excel", "our system"]}}
    for answer in ["helping the HR?", "outlook, Excel and our system", "I update employee records"]:
        before = state["question_count"]
        result = multi_agent_graph.execute_multi_agent_turn({**state, "user_message": answer})
        assert not result.get("error")
        assert result["assistant_message"]
        assert not result["completed"]
        assert result["question_count"] == before + 1
        state = {**state, **result, "history": state["history"] + [
            {"role": "user", "content": answer},
            {"role": "assistant", "content": result["assistant_message"]}]}


def test_schema_compaction_preserves_shape_and_reduces_repetition():
    import copy
    import json
    from app.workflow import capture_schema
    bb = {"dossier": {"workflow": {"tasks": [{"id": f"task-{i}"} for i in range(6)]}}}
    original = capture_schema(bb)
    compact = interview_capture._compact_schema(original)
    root = compact["json_schema"]["schema"]
    def expand(node):
        if isinstance(node, dict):
            if "$ref" in node:
                return expand(root["$defs"][node["$ref"].split("/")[-1]])
            return {k: expand(v) for k, v in node.items() if k != "$defs"}
        return [expand(v) for v in node] if isinstance(node, list) else node
    assert expand(root) == original["json_schema"]["schema"]
    assert len(json.dumps(compact)) < len(json.dumps(original)) * 0.4


@pytest.mark.usefixtures("with_model")
def test_sdk_truncation_increases_budget_instead_of_repeating_same_request(monkeypatch):
    from openai import LengthFinishReasonError
    from types import SimpleNamespace
    caps = []
    truncated_completion = SimpleNamespace(usage=None)
    def recording_model(state, cap, schema=None):
        caps.append(cap)
        model = Mock()
        if len(caps) == 1:
            model.invoke.side_effect = LengthFinishReasonError(completion=truncated_completion)
        else:
            model.invoke.return_value = SimpleNamespace(content='{"workflow_updates": {}, "new_tasks": []}', response_metadata={})
        return model
    monkeypatch.setattr(interview_capture, "_recording_model", recording_model)
    monkeypatch.setattr(interview_capture, "_recover_supplied_gaps", lambda state, result: result)
    monkeypatch.setattr(interview_capture, "record_failure", Mock())
    interview_capture.capture_reply({"user_message": "I coordinate recruitment"}, refresh_summary=False)
    assert caps == [6000, 12000]
    interview_capture.record_failure.assert_not_called()


@pytest.mark.usefixtures("with_model")
def test_repeated_truncation_holds_answer_for_manual_recovery(monkeypatch):
    from openai import LengthFinishReasonError
    from types import SimpleNamespace
    model = Mock()
    model.invoke.side_effect = LengthFinishReasonError(completion=SimpleNamespace(usage=None))
    monkeypatch.setattr(interview_capture, "_recording_model", lambda *args: model)
    with pytest.raises(OpenAIUnavailable) as error:
        interview_capture.capture_reply({"user_message": "recruitment"}, refresh_summary=False)
    assert error.value.code == "structured_output_truncated"
    assert not error.value.retryable
    assert model.invoke.call_count == 2


def test_same_source_concurrent_requests_share_successful_graph_execution():
    from concurrent.futures import ThreadPoolExecutor
    from app.turn_runtime import run_turn_once
    import time
    execute = Mock(side_effect=lambda: (time.sleep(0.03) or {"assistant_message": "Next?"}))
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda _: run_turn_once("test-thread", 999, execute), range(2)))
    assert results[0] == results[1]
    execute.assert_called_once()


def test_processing_budget_prevents_another_provider_call(monkeypatch):
    from app import turn_runtime
    import time
    token = turn_runtime._deadline.set(time.monotonic() - 1)
    model = Mock()
    try:
        with pytest.raises(TimeoutError):
            turn_runtime.invoke(model, [])
        model.invoke.assert_not_called()
    finally:
        turn_runtime._deadline.reset(token)


def test_provider_timeout_uses_remaining_turn_budget():
    from app import turn_runtime
    import time
    token = turn_runtime._deadline.set(time.monotonic() + 10)
    model = Mock()
    try:
        turn_runtime.invoke(model, [])
        assert 0 < model.invoke.call_args.kwargs["timeout"] <= 10
    finally:
        turn_runtime._deadline.reset(token)


def test_failed_execution_is_not_cached_and_can_recover():
    from app.turn_runtime import run_turn_once
    execute = Mock(side_effect=[{"error": "openai_unavailable"}, {"assistant_message": "Next?"}])
    assert run_turn_once("failed-thread", 10, execute)["error"]
    assert run_turn_once("failed-thread", 10, execute)["assistant_message"] == "Next?"
    assert execute.call_count == 2


@pytest.mark.usefixtures("with_model")
def test_question_writer_does_not_duplicate_latest_saved_answer(monkeypatch):
    from types import SimpleNamespace
    model = Mock()
    model.invoke.return_value = SimpleNamespace(content="Which task comes next?", response_metadata={})
    monkeypatch.setattr(multi_agent_llm, "build_chat_openai", lambda **kwargs: model)
    multi_agent_llm._talk("Ask one question", {"user_message": "Recruitment", "history": [{"role": "user", "content": "Recruitment"}]})
    messages = model.invoke.call_args.args[0]
    assert sum(m.content == "Recruitment" for m in messages) == 1


def test_recorder_keeps_full_evidence_without_duplicate_current_answer():
    state = {"user_message": "Recruitment", "source_message_id": 5,
             "history": [{"role": "user", "content": "Earlier fact", "message_id": 4},
                         {"role": "user", "content": "Recruitment", "message_id": 5}]}
    text = interview_capture._turn_block(state)
    assert "Earlier fact" in text
    assert text.count("Recruitment") == 1
    assert "Current reply source ID: 5" in text


@pytest.mark.usefixtures("with_model")
def test_recording_token_override_cannot_exceed_absolute_cap(monkeypatch):
    from openai import LengthFinishReasonError
    from types import SimpleNamespace
    caps = []
    monkeypatch.setattr(interview_capture.settings, 'openai_max_tokens', 50000)
    def model(state, cap, schema=None):
        caps.append(cap)
        result = Mock()
        result.invoke.side_effect = LengthFinishReasonError(completion=SimpleNamespace(usage=None))
        return result
    monkeypatch.setattr(interview_capture, '_recording_model', model)
    with pytest.raises(OpenAIUnavailable):
        interview_capture.capture_reply({'user_message':'Recruitment'}, refresh_summary=False)
    assert caps == [12000]


@pytest.mark.usefixtures("with_model")
def test_json_repair_with_length_finish_reason_is_held_not_accepted(monkeypatch):
    from types import SimpleNamespace
    model = Mock()
    model.invoke.side_effect = [SimpleNamespace(content='not JSON', response_metadata={}),
        SimpleNamespace(content='{}', response_metadata={'finish_reason': 'length'})]
    monkeypatch.setattr(interview_capture, '_recording_model', lambda *args: model)
    with pytest.raises(OpenAIUnavailable) as caught:
        interview_capture.capture_reply({'user_message': 'Recruitment'}, refresh_summary=False)
    assert caught.value.code == 'structured_output_truncated'
    assert not caught.value.retryable
    assert model.invoke.call_count == 2
