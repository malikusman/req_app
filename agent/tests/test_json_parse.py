"""Unit tests for tolerant LLM JSON parsing (FEAT-AGENTS)."""

from app.json_parse import LlmJsonParseError, extract_json_object


def test_parses_plain_object():
    assert extract_json_object('{"assistant_message": "hi"}')["assistant_message"] == "hi"


def test_strips_markdown_fence():
    raw = '```json\n{"assistant_message": "ok", "completed": false}\n```'
    assert extract_json_object(raw)["assistant_message"] == "ok"


def test_extracts_embedded_object():
    raw = 'Sure!\n{"assistant_message": "next", "completed": false}\nThanks'
    assert extract_json_object(raw)["assistant_message"] == "next"


def test_rejects_non_object():
    try:
        extract_json_object("[1, 2]")
        assert False, "expected LlmJsonParseError"
    except LlmJsonParseError:
        pass
