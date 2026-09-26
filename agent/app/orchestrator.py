"""Deterministic orchestration around the two per-turn model calls.

A turn runs in this order:

  record_reply  — fold the recording call's output (app/interview_capture) into the
                  blackboard: dossier slots, role areas, parked asides, findings,
                  rolling summary, and the stall counter.
  prepare_turn  — decide what to ask next from the UPDATED dossier, or whether to end.
  finalize_turn — book-keeping for the question the talking call just wrote.

Recording before deciding is the point. When one call both recorded the reply and
asked the next question, the next question was chosen from state that did not yet
include the answer it was reacting to, and a dossier completed by the final answer
could only close one question later.

The interview ends for one of four reasons, in this precedence:

  1. dossier_complete — every required slot filled. The intended exit.
  2. ceiling        — question_count reached max_questions. A backstop; if this
                      fires often, the dossier is mis-specified.
  3. stalled        — stall_turns consecutive replies filled no new required slot.
                      This is what stops an uncapped interview circling.
  4. employee_ended — the recording call reported they asked to stop.

1 and 3 are both gated on min_questions, so a terse employee can't end the
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


def record_reply(state: dict[str, Any], capture: dict[str, Any]) -> dict[str, Any]:
    """Fold what the employee's latest reply supplied into the blackboard."""
    limits = resolve_limits(state.get("limits"))
    bb = ensure_blackboard(state.get("blackboard"), state.get("profile") or {})
    # The reply answers the question most recently asked, which is question number
    # question_count (the counter has already moved past it).
    turn_number = state.get("question_count", 0)
    threshold = limits["slot_confidence"]

    areas_before = len(bb.get("role_areas") or [])
    area_flow.record_reply(bb, capture.get("role_areas"))
    progress = dossier.merge_slots(bb, capture.get("slots_filled"), turn_number, threshold)
    # Naming a new role area is progress too. Orientation replies exist to name areas,
    # not fill slots; counting them as "nothing new" let a terse interview reach the
    # stall exit at question 4 while it was still, correctly, mapping the role.
    progress += len(bb.get("role_areas") or []) - areas_before
    dossier.park(
        bb,
        capture.get("parked"),
        turn_number,
        area=(bb.get("last_beat") or {}).get("area"),
    )

    progress += _accept_on_second_attempt(bb, state.get("user_message"), turn_number, threshold)

    # A reply that fills nothing required is not automatically a problem — it may
    # have been a clarification — but several in a row means the conversation is
    # going nowhere and should end warmly.
    # The opening turn records the kickoff built from the profile, not a reply to any
    # question, so it can never be a stalled turn.
    if turn_number > 0:
        bb["stall_turns"] = 0 if progress else bb.get("stall_turns", 0) + 1

    finding = capture.get("finding")
    if finding and finding.get("content"):
        bb["shared_findings"].append(
            {
                "agent": "interviewer",
                "finding": finding["content"],
                "confidence": float(finding.get("confidence") or 0.5),
                "turn": turn_number,
            }
        )

    if capture.get("updated_summary"):
        bb["conversation_summary"] = capture["updated_summary"]
        bb["summary_through_turn"] = turn_number

    return {
        **state,
        "blackboard": bb,
        "limits": limits,
        "insight": capture.get("insight") or {"summary": "", "topics": []},
        # Returned for diagnosis (the replay harness reads it); Rails does not store it.
        "capture": {k: v for k, v in capture.items() if k != "insight"},
        "employee_ended": bool(capture.get("wants_to_stop")),
        # "recorded", or why the record is empty — stamped on the routing decision so
        # a degraded capture is visible on the message, not silent.
        "capture_status": (
            f"fallback: {capture['fallback_reason']}" if capture.get("fallback_reason") else "recorded"
        ),
    }


MAX_SLOT_ATTEMPTS = 2


def _accept_on_second_attempt(bb: Blackboard, reply: Any, turn: int, threshold: float) -> int:
    """Ask twice, then take what they gave.

    Someone who says "it depends on the season" twice when asked how long something
    takes has answered — they cannot put a number on it. Asking a third time wastes
    their goodwill, and letting the stall exit fire instead ends the interview before
    the easy closing questions are asked. So a real reply to a second attempt at the
    same slot is recorded as that slot's answer, at the threshold confidence, marked
    as accepted rather than clearly given; for a time question the words are kept
    and the numbers left empty (unknown, never guessed). The deep dive refines it.

    A reply of a few words ("ok", "not sure") is not accepted — that is disengagement,
    and the stall exit is the right response to it.
    """
    beat = bb.get("last_beat") or {}
    text = str(reply or "").strip()
    if not beat.get("slot") or len(text.split()) < 4:
        return 0
    key = dossier.slot_key(beat["slot"], beat.get("area"))
    dos = dossier.ensure_dossier(bb)
    if dossier.is_filled(dos, key, threshold):
        return 0
    if (bb.get("slot_attempts") or {}).get(key, 0) < MAX_SLOT_ATTEMPTS:
        return 0
    entry = {"value": text[:400], "confidence": threshold, "turn": turn, "accepted_after_retry": True}
    if beat["slot"] == "friction_cost":
        entry["effort"] = {
            "frequency": {"as_said": text[:160], "min": None, "max": None, "unit": None},
            "duration": None,
            "effort_type": "unknown",
        }
    dos["slots"][key] = entry
    return 1


def prepare_turn(state: dict[str, Any]) -> dict[str, Any]:
    limits = resolve_limits(state.get("limits"))
    bb = ensure_blackboard(state.get("blackboard"), state.get("profile") or {})
    question_count = state.get("question_count", 0)

    if state.get("employee_ended"):
        decision = {"phase": "close", "beat": None, "should_close": True, "close_reason": "employee_ended"}
    else:
        decision = area_flow.prepare(bb, limits, question_count)
    previous = (bb.get("last_routing_decision") or {}).get("agent")
    routing = area_flow.routing_decision(decision, previous)
    routing["capture"] = state.get("capture_status") or "skipped"
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


def finalize_turn(state: dict[str, Any], reply: dict[str, Any]) -> dict[str, Any]:
    """After the talking call: book the question just asked."""
    bb: Blackboard = state["blackboard"]
    area_flow.after_ask(bb, state.get("phase"), state.get("beat"))
    if reply.get("fallback_reason"):
        state["routing_decision"] = {**(state.get("routing_decision") or {}), "reply": f"fallback: {reply['fallback_reason']}"}
        bb["last_routing_decision"] = state["routing_decision"]

    return {
        **state,
        "blackboard": bb,
        "assistant_message": reply.get("assistant_message", ""),
        "completed": False,
        "question_count": state.get("question_count", 0) + 1,
    }


def needs_summary_refresh(state: dict[str, Any]) -> bool:
    bb = state.get("blackboard") or {}
    question_count = state.get("question_count", 0)
    return question_count - bb.get("summary_through_turn", 0) >= SUMMARY_REFRESH_EVERY
