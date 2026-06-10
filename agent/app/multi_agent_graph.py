"""Multi-agent supervisor graph.

prepare (deterministic orchestration) -> interview (one LLM call as the active
specialist) -> finalize (deterministic blackboard update), with a conditional
edge to close when the interview is done before asking another question.

The graph is stateless across turns: the blackboard travels in/out via Rails.
"""

from typing import Any

from langgraph.graph import END, StateGraph

from app.llm import OpenAIUnavailable
from app.multi_agent_llm import closing_message, run_agent_turn
from app.orchestrator import finalize_turn, prepare_turn
from app.state import MultiTurnState


def _prepare(state: MultiTurnState) -> MultiTurnState:
    return prepare_turn(dict(state))


def _interview(state: MultiTurnState) -> MultiTurnState:
    llm_output = run_agent_turn(dict(state))
    return finalize_turn(dict(state), llm_output)


def _close(state: MultiTurnState) -> MultiTurnState:
    message = closing_message(
        state.get("preferred_language", "en"),
        state.get("employee_name", ""),
    )
    bb = state.get("blackboard") or {}
    return {
        **state,
        "assistant_message": message,
        "insight": {"summary": "", "topics": []},
        "completed": True,
        "blackboard": bb,
    }


def _route_after_prepare(state: MultiTurnState) -> str:
    return "close" if state.get("should_close") else "interview"


def build_multi_agent_graph():
    graph = StateGraph(MultiTurnState)
    graph.add_node("prepare", _prepare)
    graph.add_node("interview", _interview)
    graph.add_node("close", _close)
    graph.set_entry_point("prepare")
    graph.add_conditional_edges("prepare", _route_after_prepare, {"interview": "interview", "close": "close"})
    graph.add_edge("interview", END)
    graph.add_edge("close", END)
    return graph.compile()


multi_agent_graph = build_multi_agent_graph()


def execute_multi_agent_turn(state: dict[str, Any]) -> dict[str, Any]:
    try:
        return multi_agent_graph.invoke(state)
    except OpenAIUnavailable:
        return {**state, "error": "openai_unavailable", "assistant_message": ""}
