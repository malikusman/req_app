"""Deterministic orchestration around the per-turn LLM call.

prepare_turn: ensure queue/states exist, pick the active agent, enforce limits,
decide whether the interview should close before asking another question.

finalize_turn: fold the agent's structured output back into the blackboard —
question counts, open follow-up threads (depth-capped), findings, coverage,
rolling summary — and decide handoff/completion.
"""

import copy
from typing import Any

from app.router import build_agent_queue
from app.state import Blackboard, default_limits, empty_coverage

SUMMARY_REFRESH_EVERY = 3


def ensure_blackboard(
    blackboard: Blackboard | None,
    profile: dict[str, Any],
    limits: dict[str, int],
    question_target: int,
) -> Blackboard:
    bb: Blackboard = copy.deepcopy(blackboard) if blackboard else {}
    bb.setdefault("profile", profile or {})

    if not bb.get("agent_queue"):
        routed = build_agent_queue(bb.get("profile") or {}, limits, question_target)
        bb["agent_queue"] = routed["agents"]
        bb.setdefault("skipped_agents", routed["skipped"])
        bb.setdefault("total_budget", routed["total_budget"])

    states = bb.setdefault("agent_states", {})
    for entry in bb["agent_queue"]:
        states.setdefault(
            entry["id"],
            {
                "questions_asked": 0,
                "question_budget": entry.get("question_budget", 4),
                "status": "active",
                "open_threads": [],
            },
        )

    bb.setdefault("coverage", empty_coverage())
    bb.setdefault("shared_findings", [])
    bb.setdefault("conversation_summary", "")
    bb.setdefault("summary_through_turn", 0)
    return bb


def pick_active_agent(bb: Blackboard) -> str | None:
    """Lowest-priority-number agent in the queue that still has budget."""
    states = bb.get("agent_states", {})
    for entry in sorted(bb.get("agent_queue", []), key=lambda a: a.get("priority", 99)):
        state = states.get(entry["id"], {})
        if state.get("status") == "complete":
            continue
        if state.get("questions_asked", 0) >= state.get("question_budget", 0):
            continue
        return entry["id"]
    return None


def prepare_turn(state: dict[str, Any]) -> dict[str, Any]:
    limits = {**default_limits(), **(state.get("limits") or {})}
    question_target = state.get("question_target", 12)
    bb = ensure_blackboard(state.get("blackboard"), state.get("profile") or {}, limits, question_target)

    question_count = state.get("question_count", 0)
    active_id = pick_active_agent(bb)

    should_close = question_count >= question_target or active_id is None

    followup_allowed = False
    followup_topic = ""
    if active_id and not should_close:
        agent_state = bb["agent_states"][active_id]
        open_threads = [t for t in agent_state.get("open_threads", []) if t.get("needs_followup")]
        if open_threads:
            thread = open_threads[0]
            if thread.get("depth", 0) < limits["max_followup_depth"]:
                followup_allowed = True
                followup_topic = thread.get("topic", "")

    previous_active = bb.get("active_agent_id")
    routing_decision = {
        "action": "close" if should_close else ("handoff" if active_id != previous_active else "continue"),
        "agent": active_id,
        "reason": (
            "question target reached or all agents complete"
            if should_close
            else f"active agent {active_id} has budget remaining"
        ),
    }
    bb["active_agent_id"] = active_id or previous_active or ""
    bb["last_routing_decision"] = routing_decision

    return {
        **state,
        "blackboard": bb,
        "limits": limits,
        "active_agent_id": active_id or "",
        "followup_allowed": followup_allowed,
        "followup_topic": followup_topic,
        "should_close": should_close,
        "routing_decision": routing_decision,
    }


def finalize_turn(state: dict[str, Any], llm_output: dict[str, Any]) -> dict[str, Any]:
    bb: Blackboard = state["blackboard"]
    limits = state["limits"]
    active_id = state["active_agent_id"]
    question_count = state.get("question_count", 0)
    turn_number = question_count + 1

    agent_state = bb["agent_states"].get(active_id)
    if agent_state is not None:
        agent_state["questions_asked"] = agent_state.get("questions_asked", 0) + 1

        followup = llm_output.get("followup") or {}
        threads = agent_state.setdefault("open_threads", [])
        if followup.get("topic"):
            existing = next((t for t in threads if t.get("topic") == followup["topic"]), None)
            if existing:
                existing["depth"] = existing.get("depth", 0) + 1
                existing["needs_followup"] = (
                    bool(followup.get("needed")) and existing["depth"] < limits["max_followup_depth"]
                )
            else:
                threads.append(
                    {
                        "topic": followup["topic"],
                        "depth": 1,
                        "needs_followup": bool(followup.get("needed")),
                    }
                )
        else:
            for thread in threads:
                thread["needs_followup"] = False

        if agent_state["questions_asked"] >= agent_state.get("question_budget", 0):
            agent_state["status"] = "complete"

    finding = llm_output.get("finding")
    if finding and finding.get("content"):
        bb["shared_findings"].append(
            {
                "agent": active_id,
                "finding": finding["content"],
                "confidence": float(finding.get("confidence") or 0.5),
                "turn": turn_number,
            }
        )

    covered = llm_output.get("topics_covered") or []
    coverage = bb["coverage"]
    for topic in covered:
        if topic in coverage.get("topics_required", []) and topic not in coverage.get("topics_covered", []):
            coverage.setdefault("topics_covered", []).append(topic)

    updated_summary = llm_output.get("updated_summary")
    if updated_summary:
        bb["conversation_summary"] = updated_summary
        bb["summary_through_turn"] = turn_number

    # Closure on budget/target exhaustion is prepare's job (close node next turn):
    # completing here would orphan the question we just asked. Only the LLM may end
    # the interview mid-turn, because its assistant_message doubles as the farewell.
    completed = bool(llm_output.get("completed"))

    return {
        **state,
        "blackboard": bb,
        "assistant_message": llm_output.get("assistant_message", ""),
        "insight": llm_output.get("insight") or {"summary": "", "topics": []},
        "completed": completed,
        "question_count": question_count if completed else question_count + 1,
    }


def needs_summary_refresh(state: dict[str, Any]) -> bool:
    bb = state.get("blackboard") or {}
    question_count = state.get("question_count", 0)
    return question_count - bb.get("summary_through_turn", 0) >= SUMMARY_REFRESH_EVERY
