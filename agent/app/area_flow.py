"""The discovery interview flow: map, then branch.

  A. ORIENT — a warm interviewer spends a few turns surfacing the person's 2-3
     main role areas and writes them to the blackboard.
  B. BRANCH — rotate short threads across those areas, asking for whichever
     dossier slot is still missing, force-switching so no single area dominates.

This is now the only interview engine. The specialist queue it replaced marched
domain -> process -> technical on per-agent question budgets, which fixated on
handoffs around Q7 and — more importantly — could only ever end on a counter.

The flow stays deterministic: the model asks the question and names the areas;
what to ask next and when to stop is decided here, from the dossier.
"""

import re
from typing import Any

from app import dossier

MAX_AREAS = 3


def ensure_area_state(bb: dict[str, Any]) -> None:
    bb.setdefault("role_areas", [])
    bb.setdefault("orient_done", False)
    bb.setdefault("orient_asked", 0)
    bb.setdefault("current_area_idx", 0)
    bb.setdefault("area_streak", 0)


def prepare(bb: dict[str, Any], limits: dict[str, Any], question_count: int) -> dict[str, Any]:
    """Decide the turn. Always returns a decision — there is no fallback engine."""
    ensure_area_state(bb)
    threshold = limits["slot_confidence"]

    # 1. Hard ceiling. A backstop, not a target.
    if question_count >= limits["max_questions"]:
        return _close("ceiling")

    past_floor = question_count >= limits["min_questions"]

    # 2. Everything required is in.
    if past_floor and dossier.is_complete(bb, threshold):
        return _close("dossier_complete")

    # 3. Going nowhere.
    if past_floor and bb.get("stall_turns", 0) >= limits["stall_turns"]:
        return _close("stalled")

    # Phase A — orient. Keep going until we have areas, even past the nominal
    # orient budget, because branching needs something to branch on.
    if not bb["orient_done"]:
        if bb["orient_asked"] < limits["orient_questions"]:
            return {"phase": "orient", "beat": None, "should_close": False}
        bb["orient_done"] = True
        if not bb.get("role_areas"):
            _seed_areas_from_profile(bb)

    if not bb.get("role_areas"):
        # Orientation genuinely produced nothing nameable and the profile was empty
        # too. Rather than loop, end — there is nothing to ask about.
        return _close("dossier_complete" if past_floor else "stalled")

    # Phase B — branch on whatever the dossier still wants.
    beat = dossier.next_beat(bb, threshold, limits["switch_after"])
    if beat is None:
        return _close("dossier_complete")

    return {"phase": "branch", "beat": beat, "should_close": False}


def finalize(
    bb: dict[str, Any],
    llm_output: dict[str, Any],
    phase: str | None,
    beat: dict[str, Any] | None,
) -> None:
    ensure_area_state(bb)
    # `beat` here is the topic of the question just asked THIS turn -- the employee's
    # NEXT reply answers it. Stashed so next turn's prompt can grade that reply
    # against the slot it actually addresses, instead of whatever comes next.
    bb["last_beat"] = beat
    if phase == "orient":
        bb["orient_asked"] = bb.get("orient_asked", 0) + 1
        _merge_role_areas(bb, llm_output.get("role_areas"))
        # Areas named early means orientation is done early.
        if bb.get("role_areas") and bb["orient_asked"] >= 2:
            bb["orient_done"] = True
    elif phase == "branch":
        bb["area_streak"] = bb.get("area_streak", 0) + 1 if beat and beat.get("area") else 0
        # A named area can still surface during branching.
        _merge_role_areas(bb, llm_output.get("role_areas"))


def routing_decision(decision: dict[str, Any], previous_agent: str | None) -> dict[str, Any]:
    phase = decision.get("phase")
    beat = decision.get("beat") or {}
    agent = phase or "close"

    if decision.get("should_close"):
        action = "close"
    elif agent != previous_agent:
        action = "handoff"
    else:
        action = "continue"

    reason = {
        "orient": "mapping the person's main role areas",
        "branch": f"asking for '{beat.get('slot')}'"
        + (f" on '{beat.get('area')}'" if beat.get("area") else ""),
        "close": f"interview complete ({decision.get('close_reason')})",
    }.get(phase or "close", "")

    return {
        "action": action,
        "agent": agent,
        "reason": reason,
        "slot": beat.get("slot"),
        "area": beat.get("area"),
        "close_reason": decision.get("close_reason"),
    }


def _close(reason: str) -> dict[str, Any]:
    return {"phase": "close", "beat": None, "should_close": True, "close_reason": reason}


def _merge_role_areas(bb: dict[str, Any], raw: Any) -> None:
    if not isinstance(raw, list):
        return
    existing = {a.get("name", "").lower() for a in bb.get("role_areas", [])}
    for name in raw:
        n = str(name).strip()
        if n and n.lower() not in existing and len(bb["role_areas"]) < MAX_AREAS:
            bb["role_areas"].append({"name": n[:60]})
            existing.add(n.lower())


def _seed_areas_from_profile(bb: dict[str, Any]) -> None:
    """So branching always has something to explore even if orient named nothing —
    split the responsibilities the profiling step already captured, else fall back
    to the role title."""
    profile = bb.get("profile") or {}
    resp = profile.get("responsibilities") or ""
    parts = [p.strip() for p in re.split(r"[,;/]|\band\b", resp) if p.strip()]
    for p in parts[:MAX_AREAS]:
        bb["role_areas"].append({"name": p[:60]})
    if not bb["role_areas"] and profile.get("role_title"):
        bb["role_areas"].append({"name": str(profile["role_title"])[:60]})
