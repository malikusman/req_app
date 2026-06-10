"""Shared state types for the multi-agent discovery system.

The blackboard is the cross-agent collaboration surface. It is owned by Rails
(persisted in conversations.state_snapshot) and passed in/out on every turn —
the agent service itself stays stateless.
"""

from typing import Any, TypedDict

COVERAGE_TOPICS = [
    "daily_workflow",
    "tools",
    "pain_points",
    "handoffs",
    "approvals",
]


class AgentQueueEntry(TypedDict, total=False):
    id: str
    priority: int
    question_budget: int
    reason: str


class OpenThread(TypedDict, total=False):
    topic: str
    depth: int
    needs_followup: bool


class AgentState(TypedDict, total=False):
    questions_asked: int
    question_budget: int
    status: str  # active | complete
    open_threads: list[OpenThread]


class Blackboard(TypedDict, total=False):
    profile: dict[str, Any]
    agent_queue: list[AgentQueueEntry]
    skipped_agents: list[dict[str, Any]]
    total_budget: int
    active_agent_id: str
    agent_states: dict[str, AgentState]
    coverage: dict[str, list[str]]
    shared_findings: list[dict[str, Any]]
    conversation_summary: str
    summary_through_turn: int
    last_routing_decision: dict[str, Any]


class MultiTurnState(TypedDict, total=False):
    # Inputs
    user_message: str
    history: list[dict[str, str]]
    playbook_block: str
    playbook_version: int
    preferred_language: str
    company_name: str
    employee_name: str
    department: str
    question_count: int
    question_target: int
    profile: dict[str, Any]
    blackboard: Blackboard
    limits: dict[str, int]
    memory_facts: list[dict[str, Any]]
    document_snippets: list[str]

    # Orchestration decisions (prepare node)
    active_agent_id: str
    followup_allowed: bool
    followup_topic: str
    should_close: bool
    routing_decision: dict[str, Any]

    # Outputs
    assistant_message: str
    insight: dict[str, Any]
    completed: bool
    error: str


def default_limits() -> dict[str, int]:
    return {
        "max_followup_depth": 2,
        "max_questions_per_agent": 5,
        "max_active_agents": 4,
    }


def empty_coverage() -> dict[str, list[str]]:
    return {"topics_required": list(COVERAGE_TOPICS), "topics_covered": []}
