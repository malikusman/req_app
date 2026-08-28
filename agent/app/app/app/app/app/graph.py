from typing import Any, TypedDict

from langgraph.graph import END, StateGraph

from app.llm import OpenAIUnavailable, run_discovery_turn


class TurnState(TypedDict, total=False):
    playbook_block: str
    playbook_version: int
    preferred_language: str
    company_name: str
    employee_name: str
    department: str
    question_count: int
    question_target: int
    user_message: str
    history: list[dict[str, str]]
    assistant_message: str
    insight: dict[str, Any]
    completed: bool
    error: str


def _run_turn(state: TurnState) -> TurnState:
    result = run_discovery_turn(
        playbook_block=state["playbook_block"],
        preferred_language=state.get("preferred_language", "en"),
        company_name=state.get("company_name", ""),
        employee_name=state.get("employee_name", ""),
        department=state.get("department", "default"),
        question_count=state.get("question_count", 0),
        question_target=state.get("question_target", 10),
        user_message=state["user_message"],
        history=state.get("history", []),
        industry=state.get("industry"),
        size_band=state.get("size_band"),
        region=state.get("region"),
        business_goals=state.get("business_goals"),
        website_url=state.get("website_url"),
        known_systems=state.get("known_systems"),
    )
    return {
        **state,
        "assistant_message": result["assistant_message"],
        "insight": result["insight"],
        "completed": result["completed"],
        "question_count": result["question_count"],
    }


def build_graph():
    graph = StateGraph(TurnState)
    graph.add_node("run_turn", _run_turn)
    graph.set_entry_point("run_turn")
    graph.add_edge("run_turn", END)
    return graph.compile()


discovery_graph = build_graph()


def execute_turn(state: TurnState) -> TurnState:
    try:
        return discovery_graph.invoke(state)
    except OpenAIUnavailable as exc:
        return {**state, "error": "openai_unavailable", "assistant_message": ""}
