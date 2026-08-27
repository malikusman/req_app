"""Deterministic orchestration around the per-turn LLM call.

prepare_turn: make sure the blackboard is in shape, decide what to ask next from
the dossier, and decide whether the interview should end before asking anything.

finalize_turn: fold the model's structured output back into the blackboard —
dossier slots, parked asides, findings, rolling summary — and track the stall
counter that ends a conversation going nowhere.

The interview ends for one of four reasons, in this precedence:

  1. ceiling        — question_count reached max_questions. A backstop; if this
                      fires often, the dossier is mis-specified.
  2. dossier_complete — every required slot filled. The intended exit.
  3. stalled        — stall_turns consecutive turns filled no new required slot.
                      This is what stops an uncapped interview circling.
  4. employee_ended — the model set completed=true (they asked to stop). Handled
                      in finalize, because its message doubles as the farewell.

2 and 3 are both gated on min_questions, so a terse employee can't end the
interview before there is anything worth packaging.
"""

import copy
from typing import Any

from app import area_flow, dossier
from app.state import Blackboard, resolve_limits

SUMMARY_REFRESH_EVERY = 3


def ensure_blackboard(blackboard: Blackboard | None, profile: dict[str, Any]) -> Blackboard:
    """Also upgrades a blackboard written by the retired specialist-queue engine.

    In-flight conversations at deploy time carry `agent_queue` / `agent_states` and
    no dossier. Those keys are simply left alone (harmless, and they keep the
    provenance view honest about how the interview started) while the area and
    dossier state they lack is seeded, so a mid-interview employee is not dropped.
    """
    bb: Blackboard = copy.deepcopy(blackboard) if blackboard else {}
    bb.setdefault("profile", profile or {})
    bb.setdefault("shared_findings", [])
    bb.setdefault("conversation_summary", "")
    bb.setdefault("summary_through_turn", 0)
    bb.setdefault("stall_turns", 0)
    area_flow.ensure_area_state(bb)
    dossier.ensure_dossier(bb)

    # Carried over from the queue engine: it had already asked real questions, so
    # don't restart orientation from zero.
    if bb.get("agent_states") and not bb.get("role_areas") and not bb.get("orient_done"):
        asked = sum(s.get("questions_asked", 0) for s in bb["agent_states"].values())
        bb["orient_asked"] = max(bb.get("orient_asked", 0), min(asked, 3))

    return bb


def prepare_turn(state: dict[str, Any]) -> dict[str, Any]:
    limits = resolve_limits(state.get("limits"))
    bb = ensure_blackboard(state.get("blackboard"), state.get("profile") or {})
    question_count = state.get("question_count", 0)

    decision = area_flow.prepare(bb, limits, question_count)
    previous = (bb.get("last_routing_decision") or {}).get("agent")
    routing = area_flow.routing_decision(decision, previous)
    bb["last_routing_decision"] = routing
    if decision.get("should_close"):
        bb["close_reason"] = decision.get("close_reason", "")

    return {
        **state,
        "blackboard": bb,
        "limits": limits,
        "beat": decision.get("beat"),
        "phase": decision.get("phase"),
        "should_close": bool(decision.get("should_close")),
        "close_reason": decision.get("close_reason", ""),
        "routing_decision": routing,
        # Provenance: Rails stamps this onto messages.agent_id, so a stored turn
        # still says which phase produced it.
        "active_agent_id": decision.get("phase"),
    }


def finalize_turn(state: dict[str, Any], llm_output: dict[str, Any]) -> dict[str, Any]:
    bb: Blackboard = state["blackboard"]
    limits = state["limits"]
    question_count = state.get("question_count", 0)
    turn_number = question_count + 1
    threshold = limits["slot_confidence"]

    area_flow.finalize(bb, llm_output, state.get("phase"), state.get("beat"))

    progress = dossier.merge_slots(bb, llm_output.get("slots_filled"), turn_number, threshold)
    dossier.park(
        bb,
        llm_output.get("parked"),
        turn_number,
        area=(state.get("beat") or {}).get("area"),
    )

    # Stall detection. A turn that fills nothing required is not automatically a
    # problem — the answer may have been a clarification — but several in a row
    # means the conversation is going nowhere and should end warmly.
    bb["stall_turns"] = 0 if progress else bb.get("stall_turns", 0) + 1

    finding = llm_output.get("finding")
    if finding and finding.get("content"):
        bb["shared_findings"].append(
            {
                "agent": "interviewer",
                "finding": finding["content"],
                "confidence": float(finding.get("confidence") or 0.5),
                "turn": turn_number,
            }
        )

    updated_summary = llm_output.get("updated_summary")
    if updated_summary:
        bb["conversation_summary"] = updated_summary
        bb["summary_through_turn"] = turn_number

    # Closing on a filled dossier or a stall is prepare's job on the NEXT turn —
    # completing here would orphan the question we just asked. Only the employee
    # asking to stop ends the interview mid-turn, because the model's
    # assistant_message doubles as the farewell.
    completed = bool(llm_output.get("completed"))
    if completed:
        bb["close_reason"] = "employee_ended"

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
