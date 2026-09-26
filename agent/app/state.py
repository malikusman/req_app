"""Shared state types for the discovery interview.

The blackboard is the cross-turn state surface. It is owned by Rails (persisted in
conversations.state_snapshot) and passed in/out on every turn — the agent service
itself stays stateless.
"""

from typing import Any, TypedDict


class RoleArea(TypedDict, total=False):
    name: str


class SlotEntry(TypedDict, total=False):
    value: str
    confidence: float
    turn: int


class ParkedItem(TypedDict, total=False):
    note: str
    turn: int
    area: str


class Dossier(TypedDict, total=False):
    # Keyed by slot name, or "slot::area" for per-area slots. See app/dossier.py.
    slots: dict[str, SlotEntry]
    parked: list[ParkedItem]


class Blackboard(TypedDict, total=False):
    profile: dict[str, Any]
    role_areas: list[RoleArea]
    orient_done: bool
    orient_asked: int
    current_area_idx: int
    area_streak: int
    dossier: Dossier
    # Consecutive turns that filled no new required slot. Drives the stall exit.
    stall_turns: int
    shared_findings: list[dict[str, Any]]
    conversation_summary: str
    summary_through_turn: int
    last_routing_decision: dict[str, Any]
    # Reason the interview ended: dossier_complete | stalled | ceiling | employee_ended
    close_reason: str


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
    profile: dict[str, Any]
    blackboard: Blackboard
    limits: dict[str, Any]
    memory_facts: list[dict[str, Any]]
    document_snippets: list[str]
    knowledge_snippets: list[str]
    media_context: dict[str, Any] | None
    media_snippets: list[str]
    # Company context for the talking call. These were passed in by main.py but never
    # declared here, so LangGraph dropped them before any node ran and the "company
    # profile context" block of the interview prompt was always empty.
    company_profile: dict[str, Any]
    industry: str
    size_band: str
    region: str
    business_goals: Any
    question_target: int

    # Orchestration decisions (prepare node).
    # NOTE: LangGraph only propagates keys declared here between nodes. A decision
    # left off this list is silently dropped, which is subtle and expensive to
    # debug — `phase` missing made the interview never merge role areas.
    phase: str
    beat: dict[str, Any] | None
    should_close: bool
    close_reason: str
    routing_decision: dict[str, Any]
    active_agent_id: str

    # Recording step (record node).
    employee_ended: bool
    # "recorded", "skipped" (no message) or "fallback: <reason>".
    capture_status: str
    capture: dict[str, Any]

    # Outputs
    assistant_message: str
    insight: dict[str, Any]
    completed: bool
    error: str
    error_detail: str


def default_limits() -> dict[str, Any]:
    """Mirrors the Rails-side defaults in Discovery::ContextBuilder. Rails is the
    authority; these apply only when a limit is absent from the payload.

    max_questions is a BACKSTOP, not a target. A well-run interview closes on a
    filled dossier several questions earlier. Raised 8 -> 12 when friction_cost was
    added, and 12 -> 14 when role_potential was. The arithmetic: 2 orient turns, 2
    static slots per area, a cost slot for up to 2 areas, ai_current_usage and
    role_potential. That is 10 questions for a typical two-area person and 12 for
    three areas; 14 leaves a three-area interview two turns of slack for replies
    that clarify rather than fill a slot. min_questions exists because without
    it a terse employee trips the stall detector at turn 3 and the discovery
    package gets built on almost nothing.
    """
    return {
        "max_questions": 14,
        "min_questions": 4,
        "stall_turns": 2,
        "slot_confidence": 0.6,
        "orient_questions": 3,
        "switch_after": 3,
    }


def resolve_limits(raw: dict[str, Any] | None) -> dict[str, Any]:
    merged = {**default_limits(), **(raw or {})}
    ints = ("max_questions", "min_questions", "stall_turns", "orient_questions", "switch_after")
    for key in ints:
        try:
            merged[key] = int(merged[key])
        except (TypeError, ValueError):
            merged[key] = default_limits()[key]
    try:
        merged["slot_confidence"] = float(merged["slot_confidence"])
    except (TypeError, ValueError):
        merged["slot_confidence"] = default_limits()["slot_confidence"]

    # A floor above the ceiling would deadlock the exit conditions.
    merged["min_questions"] = min(merged["min_questions"], merged["max_questions"])
    return merged
