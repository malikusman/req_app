"""Phase 3 — map-then-branch discovery flow (gated by state['area_routing']).

Instead of marching one narrow specialist (domain -> process -> technical) which
fixates on handoffs around Q7, this:

  A. ORIENT (first few turns): a warm interviewer surfaces the person's 2-3 main
     role areas and writes them to the blackboard.
  B. BRANCH: rotate short threads across those areas, each cycling how -> pain ->
     ai, force-switching after a couple of questions so no single area (or the
     handoffs lens) can dominate.

Kept deterministic; the LLM only asks the question and (during orient) names the
areas. Falls back to the specialist queue if no areas were discovered.
"""

import re
from typing import Any

AREA_BEATS = ["how", "pain", "ai"]
DEFAULT_ORIENT_QUESTIONS = 3
DEFAULT_SWITCH_AFTER = 2
MAX_AREAS = 3

BEAT_INTENT = {
    "how": "how this part of their work actually gets done day to day, and which tools they use for it",
    "pain": "what's slow, manual, annoying or error-prone about this part — where it snags",
    "ai": (
        "whether they've ever thought about letting software or AI take a boring slice of this "
        "off their plate, and what they'd try — asked lightly, out of genuine curiosity, never as a pitch"
    ),
}


def area_limits(limits: dict[str, Any] | None) -> dict[str, int]:
    limits = limits or {}
    return {
        "orient_questions": int(limits.get("orient_questions", DEFAULT_ORIENT_QUESTIONS)),
        "switch_after": int(limits.get("switch_after", DEFAULT_SWITCH_AFTER)),
    }


def ensure_area_state(bb: dict[str, Any]) -> None:
    bb.setdefault("role_areas", [])
    bb.setdefault("orient_done", False)
    bb.setdefault("orient_asked", 0)
    bb.setdefault("current_area_idx", 0)
    bb.setdefault("area_streak", 0)


def prepare(state: dict[str, Any], bb: dict[str, Any], limits: dict[str, Any], question_target: int) -> dict[str, Any] | None:
    """Decide the turn. Returns a decision dict, or None to fall back to the
    specialist queue (only when orient produced no areas)."""
    ensure_area_state(bb)
    al = area_limits(limits)
    qc = state.get("question_count", 0)
    if qc >= question_target:
        return {"phase": "close", "active": None, "should_close": True}

    # Phase A — orient
    if not bb["orient_done"]:
        if bb["orient_asked"] < al["orient_questions"]:
            return {"phase": "orient", "active": "orient", "should_close": False}
        bb["orient_done"] = True

    # Phase B — branch (needs areas)
    areas = bb.get("role_areas") or []
    if not areas:
        return None  # safety: fall back to specialist routing

    idx = bb.get("current_area_idx", 0) % len(areas)
    streak = bb.get("area_streak", 0)
    cur = areas[idx]
    undone = [b for b in AREA_BEATS if b not in (cur.get("beats_done") or [])]

    # Force-switch after a couple of questions in one area, or when it's exhausted.
    if streak >= al["switch_after"] or not undone:
        order = sorted(range(len(areas)), key=lambda i: (len(areas[i].get("beats_done") or []), i))
        nxt = next((i for i in order if len(areas[i].get("beats_done") or []) < len(AREA_BEATS)), None)
        if nxt is None:
            return {"phase": "close", "active": None, "should_close": True}  # every area fully explored
        idx, streak = nxt, 0
        cur = areas[idx]
        undone = [b for b in AREA_BEATS if b not in (cur.get("beats_done") or [])]

    bb["current_area_idx"] = idx
    bb["area_streak"] = streak
    return {
        "phase": "branch",
        "active": "area",
        "should_close": False,
        "current_area": cur.get("name", ""),
        "current_beat": undone[0],
        "beat_intent": BEAT_INTENT.get(undone[0], ""),
    }


def finalize(state: dict[str, Any], bb: dict[str, Any], llm_output: dict[str, Any], decision: dict[str, Any]) -> None:
    ensure_area_state(bb)
    phase = decision.get("phase")
    if phase == "orient":
        bb["orient_asked"] = bb.get("orient_asked", 0) + 1
        _merge_role_areas(bb, llm_output.get("role_areas"))
        al = area_limits(state.get("limits") or {})
        if bb["orient_asked"] >= al["orient_questions"]:
            bb["orient_done"] = True
            if not bb.get("role_areas"):
                _seed_areas_from_profile(bb)
    elif phase == "branch":
        idx = bb.get("current_area_idx", 0)
        areas = bb.get("role_areas") or []
        if 0 <= idx < len(areas):
            done = areas[idx].setdefault("beats_done", [])
            beat = decision.get("current_beat")
            if beat and beat not in done:
                done.append(beat)
        bb["area_streak"] = bb.get("area_streak", 0) + 1


def routing_decision(decision: dict[str, Any], previous_active: str) -> dict[str, Any]:
    active = decision.get("active")
    if decision.get("should_close"):
        action = "close"
    elif active != previous_active:
        action = "handoff"
    else:
        action = "continue"
    reason = {
        "orient": "mapping the person's main role areas",
        "branch": f"exploring '{decision.get('current_area')}' ({decision.get('current_beat')})",
        "close": "interview complete",
    }.get(decision.get("phase"), "")
    return {"action": action, "agent": active, "reason": reason,
            "area": decision.get("current_area"), "beat": decision.get("current_beat")}


def _merge_role_areas(bb: dict[str, Any], raw: Any) -> None:
    if not isinstance(raw, list):
        return
    existing = {a.get("name", "").lower() for a in bb.get("role_areas", [])}
    for name in raw:
        n = str(name).strip()
        if n and n.lower() not in existing and len(bb["role_areas"]) < MAX_AREAS:
            bb["role_areas"].append({"name": n[:60], "beats_done": []})
            existing.add(n.lower())


def _seed_areas_from_profile(bb: dict[str, Any]) -> None:
    """Fallback so branching always has something to explore even if orient
    failed to name areas — split responsibilities, else use the role title."""
    profile = bb.get("profile") or {}
    resp = profile.get("responsibilities") or ""
    parts = [p.strip() for p in re.split(r"[,;/]|\band\b", resp) if p.strip()]
    for p in parts[:MAX_AREAS]:
        bb["role_areas"].append({"name": p[:60], "beats_done": []})
    if not bb["role_areas"]:
        bb["role_areas"].append({"name": profile.get("role_title") or "their main work", "beats_done": []})
