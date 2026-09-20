"""The role dossier — what the interview is trying to learn, and whether it has.

Discovery used to end on arithmetic: `question_count >= question_target`. Coverage
existed (`topics_covered`) but nothing read it to decide completion, so every
interview ran to the counter regardless of how much had been learned.

This replaces the counter with a set of named slots. A slot is filled when the
employee's answer supplied it, at a confidence the model reports. The interview
ends when every REQUIRED slot is filled — usually well before the ceiling.

Everything here is pure and deterministic: the model reports what an answer
supplied, and this module decides what that means and what to ask next. No LLM
call is needed to evaluate completeness.
"""

from typing import Any

SEP = "::"

# Asked once for the whole interview.
#
# Having named role areas is also required, but it is NOT a slot: it is derivable
# from bb["role_areas"], and is_complete() enforces it directly. Making it a slot
# meant it could only be satisfied by the model volunteering a slots_filled entry
# for it, so an otherwise-finished interview ran to the ceiling instead.
GLOBAL_REQUIRED = ["ai_current_usage"]
# volume_or_frequency used to live here as an opportunistic "take it if they offer
# it, never chase it" slot. It is gone: friction_cost below strictly supersedes it
# (targeted at a named friction rather than the role generally, and shaped to
# produce an annualisable figure), and two near-identical slots invited the model
# to fill the wrong one — slot fidelity is already the weakest link in the turn.
GLOBAL_OPPORTUNISTIC: list[str] = []

# Asked per role area.
AREA_REQUIRED = ["how_it_works", "friction"]
AREA_OPPORTUNISTIC = ["ai_openness"]

# Required only once its trigger slot is filled, keyed slot -> trigger.
#
# Why conditional rather than simply required: asking how long something takes
# before you know what "it" is makes no sense, and chasing a cost for an area whose
# friction was never captured spends the interview's only scarce resource (turns)
# on nothing. Unlocking on `friction` means we ask exactly when the question has
# become answerable.
AREA_CONDITIONAL = {"friction_cost": "friction"}

# How many areas get their friction quantified in the interview itself.
#
# Without a cap this scales with MAX_AREAS: three areas would add three more
# required slots and push a normal interview into the ceiling every time. Two keeps
# the added burden at +2 questions no matter how many areas a person has, and the
# consultant-guided follow-up covers anything else worth costing — that path can be
# aimed at the frictions that actually reached the report, which an interview
# cannot know yet.
MAX_QUANTIFIED_AREAS = 2

# What the interviewer is actually curious about for each slot. Phrased as intent,
# not as a script — the model writes the question.
SLOT_INTENT = {
    "how_it_works": (
        "how this part of their work actually gets done day to day, and which tools they use for it"
    ),
    "friction": (
        "what's slow, manual, annoying or error-prone about this part — where it snags"
    ),
    "ai_openness": (
        "whether they'd hand a boring slice of this to software or AI, and what they'd try — "
        "asked lightly, out of genuine curiosity, never as a pitch"
    ),
    "ai_current_usage": (
        "whether they already use any AI tools in their day-to-day work and what for — "
        "a plain, easy question, no jargon, no judgement either way"
    ),
    "friction_cost": (
        "what the friction they just described actually costs them in time — how often it "
        "comes up and how long it takes — in whatever terms they would naturally use "
        "(\"about an hour a day\", \"twenty minutes each, maybe thirty a week\"). Ask it as "
        "ONE natural question about time, not as two; their own phrasing is what we want"
    ),
}

# Cap so a chatty interview can't grow the blackboard without bound.
MAX_PARKED = 12


def empty_dossier() -> dict[str, Any]:
    return {"slots": {}, "parked": []}


def ensure_dossier(bb: dict[str, Any]) -> dict[str, Any]:
    dossier = bb.setdefault("dossier", empty_dossier())
    dossier.setdefault("slots", {})
    dossier.setdefault("parked", [])
    return dossier


def slot_key(slot: str, area: str | None = None) -> str:
    if not area:
        return slot
    # Area names come from the model, so keep the separator unambiguous.
    return f"{slot}{SEP}{str(area).replace(SEP, ' ')}"


def area_names(bb: dict[str, Any]) -> list[str]:
    return [a.get("name", "") for a in (bb.get("role_areas") or []) if a.get("name")]


def required_keys(bb: dict[str, Any], threshold: float | None = None) -> list[str]:
    """Required slots depend on the areas discovered, so this grows during orient.

    threshold=None means "every key that could EVER be required", ignoring whether a
    conditional slot's trigger has fired. That is what merge_slots wants when it asks
    "was this turn progress?" — a conditional filled early still counts. Pass a real
    threshold to ask the narrower question "what is required right now?", which is
    what completion and the next-beat decision need.
    """
    keys = list(GLOBAL_REQUIRED)
    dossier = ensure_dossier(bb)
    quantified = 0

    for area in area_names(bb):
        keys.extend(slot_key(slot, area) for slot in AREA_REQUIRED)

        # The cap governs what we CHASE, not what counts as progress — so it only
        # applies when a threshold was given. Without one the caller is asking
        # "could this ever be required?", and a cost filled for a fourth area is
        # still progress, not a stall.
        if threshold is not None and quantified >= MAX_QUANTIFIED_AREAS:
            continue
        for slot, trigger in AREA_CONDITIONAL.items():
            if threshold is not None and not is_filled(dossier, slot_key(trigger, area), threshold):
                continue
            keys.append(slot_key(slot, area))
            quantified += 1

    return keys


def is_filled(dossier: dict[str, Any], key: str, threshold: float) -> bool:
    entry = (dossier.get("slots") or {}).get(key)
    return bool(entry) and float(entry.get("confidence") or 0) >= threshold


def missing_required(bb: dict[str, Any], threshold: float) -> list[str]:
    dossier = ensure_dossier(bb)
    return [k for k in required_keys(bb, threshold) if not is_filled(dossier, k, threshold)]


def is_complete(bb: dict[str, Any], threshold: float) -> bool:
    """Named areas are themselves a requirement: without one, an interview that
    never got going would look complete on the global slots alone."""
    if not area_names(bb):
        return False
    return not missing_required(bb, threshold)


def merge_slots(bb: dict[str, Any], reported: Any, turn: int, threshold: float) -> int:
    """Fold the model's `slots_filled` into the dossier. Returns how many required
    slots this turn newly filled (or meaningfully strengthened) — the signal the
    stall detector reads."""
    dossier = ensure_dossier(bb)
    slots = dossier["slots"]
    if not isinstance(reported, list):
        return 0

    known_required = set(required_keys(bb))
    progress = 0

    for item in reported:
        if not isinstance(item, dict):
            continue
        name = str(item.get("slot") or "").strip()
        if name not in SLOT_INTENT:
            continue

        area = item.get("area") or None
        # Per-area slots must attach to an area we actually know about, otherwise a
        # hallucinated area name would create a required slot nobody can fill.
        if name in AREA_REQUIRED or name in AREA_OPPORTUNISTIC or name in AREA_CONDITIONAL:
            if not area or area not in area_names(bb):
                continue
        else:
            area = None

        key = slot_key(name, area)
        confidence = float(item.get("confidence") or 0)
        existing = slots.get(key)
        was_filled = bool(existing) and float(existing.get("confidence") or 0) >= threshold

        if existing and float(existing.get("confidence") or 0) >= confidence:
            continue  # keep the stronger answer

        slots[key] = {
            "value": str(item.get("value") or "")[:400],
            "confidence": confidence,
            "turn": turn,
        }
        if key in known_required and not was_filled and confidence >= threshold:
            progress += 1

    return progress


def park(bb: dict[str, Any], note: Any, turn: int, area: str | None = None) -> None:
    """Capture an interesting aside without drilling into it now.

    This is what makes "breadth before depth" real rather than aspirational: the
    agent records the thread and moves on, and the parked items become the raw
    material for the follow-up questions in the discovery package.
    """
    text = str(note or "").strip()
    if not text:
        return
    dossier = ensure_dossier(bb)
    parked = dossier["parked"]
    if any(p.get("note") == text[:300] for p in parked):
        return
    if len(parked) >= MAX_PARKED:
        return
    parked.append({"note": text[:300], "turn": turn, "area": area or ""})


def next_beat(bb: dict[str, Any], threshold: float, switch_after: int) -> dict[str, Any] | None:
    """Pick what to ask next, or None when the dossier has nothing left to want.

    Priority, in order:
      1. required slots for the current area (rotating, force-switched)
      2. ai_current_usage, once one area is fully understood
      3. opportunistic slots
    """
    dossier = ensure_dossier(bb)
    areas = area_names(bb)
    if not areas:
        return None

    idx = bb.get("current_area_idx", 0) % len(areas)
    streak = bb.get("area_streak", 0)

    # Static slots first, so an area is understood before it is costed; the unlocked
    # cost slot then trails it. Ordering matters because next_beat takes missing[0].
    quantifiable = _quantifiable_areas(bb, dossier, threshold)

    def area_missing(area: str) -> list[str]:
        missing = [s for s in AREA_REQUIRED if not is_filled(dossier, slot_key(s, area), threshold)]
        if area in quantifiable:
            missing += [
                slot
                for slot, trigger in AREA_CONDITIONAL.items()
                if is_filled(dossier, slot_key(trigger, area), threshold)
                and not is_filled(dossier, slot_key(slot, area), threshold)
            ]
        return missing

    # Force-switch off an area that has had its turn, or one that's done. The
    # current area is excluded from the candidates — otherwise it sorts first again
    # and the switch never happens, which is how a single lens came to dominate.
    if streak >= switch_after or not area_missing(areas[idx]):
        others = [i for i in range(len(areas)) if i != idx and area_missing(areas[i])]
        # Least-covered first, so attention spreads instead of finishing one area.
        others.sort(key=lambda i: (-len(area_missing(areas[i])), i))
        if others:
            idx, streak = others[0], 0
        elif not area_missing(areas[idx]):
            # Nowhere left to go and this area is done — let the caller fall
            # through to the global and opportunistic slots below.
            pass

    area = areas[idx]
    missing = area_missing(area)
    if missing:
        bb["current_area_idx"], bb["area_streak"] = idx, streak
        slot = missing[0]
        return {"slot": slot, "area": area, "intent": SLOT_INTENT[slot]}

    # Every area's required slots are in. Ask the one global slot that's left.
    if not is_filled(dossier, "ai_current_usage", threshold):
        return {"slot": "ai_current_usage", "area": None, "intent": SLOT_INTENT["ai_current_usage"]}

    # Nothing required left — take an opportunistic slot if one is open.
    for area in areas:
        for slot in AREA_OPPORTUNISTIC:
            if not is_filled(dossier, slot_key(slot, area), threshold):
                return {"slot": slot, "area": area, "intent": SLOT_INTENT[slot]}
    for slot in GLOBAL_OPPORTUNISTIC:
        if not is_filled(dossier, slot, threshold):
            return {"slot": slot, "area": None, "intent": SLOT_INTENT[slot]}

    return None


def _quantifiable_areas(bb: dict[str, Any], dossier: dict[str, Any], threshold: float) -> set[str]:
    """The first MAX_QUANTIFIED_AREAS areas whose friction is captured.

    Deterministic and explainable: areas in discovery order, so the same interview
    state always picks the same ones, and required_keys agrees with next_beat about
    which areas are in scope.
    """
    chosen = set()
    for area in area_names(bb):
        if len(chosen) >= MAX_QUANTIFIED_AREAS:
            break
        for trigger in AREA_CONDITIONAL.values():
            if is_filled(dossier, slot_key(trigger, area), threshold):
                chosen.add(area)
                break
    return chosen


def summary_for_prompt(bb: dict[str, Any], threshold: float) -> str:
    """What's still wanted, in words the prompt can use."""
    missing = missing_required(bb, threshold)
    if not missing:
        return "everything required is covered"
    parts = []
    for key in missing[:6]:
        slot, _, area = key.partition(SEP)
        parts.append(f"{slot.replace('_', ' ')}{f' for {area}' if area else ''}")
    return "; ".join(parts)
