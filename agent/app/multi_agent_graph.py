"""Discovery interview graph.

    record (model call 1: what did the reply supply?) -> prepare (deterministic: what
    to ask next, or whether to stop) -> talk (model call 2: write the question)
                                     \\-> close (farewell)

Recording runs first so that the choice of what to ask next sees the answer it is
reacting to. On the opening turn it reads the kickoff synthesised from the
employee's profile, which is where role areas usually first appear.

The graph is stateless across turns: the blackboard travels in/out via Rails.
"""

import logging
from typing import Any

from langgraph.graph import END, StateGraph

from app.interview_capture import EMPTY_CAPTURE, capture_reply
from app.llm import OpenAIUnavailable
from app.multi_agent_llm import closing_message, write_farewell, write_question
from app.orchestrator import finalize_turn, needs_summary_refresh, prepare_turn, record_reply
from app.state import MultiTurnState


def _record(state: MultiTurnState) -> MultiTurnState:
    current = dict(state)
    # The opening turn is recorded too: its "message" is the kickoff built from the
    # profile ("I'm Shiv, a Procurement Officer… supplier price updates, purchase
    # orders…"), which is the best early source of role areas there is. Skipping it
    # cost the interview areas the person had already named.
    if not str(current.get("user_message") or "").strip():
        return {**current, "insight": dict(EMPTY_CAPTURE["insight"]), "capture_status": "skipped"}
    capture = capture_reply(current, refresh_summary=needs_summary_refresh(current))
    return record_reply(current, capture)


def _prepare(state: MultiTurnState) -> MultiTurnState:
    return prepare_turn(dict(state))


def _talk(state: MultiTurnState) -> MultiTurnState:
    current = dict(state)
    return finalize_turn(current, write_question(current))


def _close(state: MultiTurnState) -> MultiTurnState:
    reason = state.get("close_reason") or "dossier_complete"
    if reason == "employee_ended":
        message = write_farewell(dict(state))
    else:
        message = closing_message(state.get("preferred_language", "en"), state.get("employee_name", ""))
    bb = state.get("blackboard") or {}
    # Why the interview ended is worth keeping: a high rate of "ceiling" means the
    # dossier is asking for more than an interview can reasonably get.
    bb["close_reason"] = reason
    return {
        **state,
        "assistant_message": message,
        # The last reply's insight is real evidence; keep it rather than blanking it.
        "insight": state.get("insight") or {"summary": "", "topics": []},
        "completed": True,
        "blackboard": bb,
    }


def _route_after_prepare(state: MultiTurnState) -> str:
    return "close" if state.get("should_close") else "talk"


def build_multi_agent_graph():
    graph = StateGraph(MultiTurnState)
    graph.add_node("record", _record)
    graph.add_node("prepare", _prepare)
    graph.add_node("talk", _talk)
    graph.add_node("close", _close)
    graph.set_entry_point("record")
    graph.add_edge("record", "prepare")
    graph.add_conditional_edges("prepare", _route_after_prepare, {"talk": "talk", "close": "close"})
    graph.add_edge("talk", END)
    graph.add_edge("close", END)
    return graph.compile()


multi_agent_graph = build_multi_agent_graph()


def execute_multi_agent_turn(state: dict[str, Any]) -> dict[str, Any]:
    try:
        return multi_agent_graph.invoke(state)
    except OpenAIUnavailable as exc:
        # Rails only ever saw a bare 503 "openai_unavailable", so every failure mode
        # — truncated JSON, a refused request, a real outage — looked identical from
        # the outside. Log the reason; it is the difference between a five-minute
        # diagnosis and an afternoon of guessing.
        logging.getLogger("uvicorn.error").warning("discovery turn failed: %s", exc)
        return {**state, "error": "openai_unavailable", "assistant_message": "", "error_detail": str(exc)}
