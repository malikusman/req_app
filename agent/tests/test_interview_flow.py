"""The four ways an interview ends, and the guarantee it neither runs long nor
ends before there is anything worth packaging."""

from app import area_flow, dossier
from app.orchestrator import finalize_turn, prepare_turn
from app.state import resolve_limits

LIMITS = {"max_questions": 8, "min_questions": 4, "stall_turns": 2, "slot_confidence": 0.6,
          "orient_questions": 3, "switch_after": 3}


def filled(areas, slots):
    bb = {"role_areas": [{"name": a} for a in areas], "orient_done": True}
    dossier.ensure_dossier(bb)
    for key, conf in slots.items():
        bb["dossier"]["slots"][key] = {"value": "x", "confidence": conf, "turn": 1}
    return bb


def complete_bb():
    return filled(
        ["Invoicing"],
        {
                "ai_current_usage": 0.8,
            "how_it_works::Invoicing": 0.8,
            "friction::Invoicing": 0.8,
        },
    )


class TestTermination:
    def test_ceiling_closes_even_with_an_empty_dossier(self):
        d = area_flow.prepare({}, resolve_limits(LIMITS), question_count=8)
        assert d["should_close"] and d["close_reason"] == "ceiling"

    def test_ceiling_takes_precedence_over_everything(self):
        d = area_flow.prepare(complete_bb(), resolve_limits(LIMITS), question_count=8)
        assert d["close_reason"] == "ceiling"

    def test_complete_dossier_closes_early(self):
        d = area_flow.prepare(complete_bb(), resolve_limits(LIMITS), question_count=5)
        assert d["should_close"] and d["close_reason"] == "dossier_complete"

    def test_a_complete_dossier_below_the_floor_keeps_going(self):
        # A terse employee must not end the interview at question 2 — the package
        # would be built on almost nothing.
        d = area_flow.prepare(complete_bb(), resolve_limits(LIMITS), question_count=2)
        assert not d["should_close"]

    def test_stall_closes(self):
        bb = filled(["Invoicing"], {})
        bb["stall_turns"] = 2
        d = area_flow.prepare(bb, resolve_limits(LIMITS), question_count=5)
        assert d["should_close"] and d["close_reason"] == "stalled"

    def test_stall_below_the_floor_keeps_going(self):
        bb = filled(["Invoicing"], {})
        bb["stall_turns"] = 3
        d = area_flow.prepare(bb, resolve_limits(LIMITS), question_count=3)
        assert not d["should_close"]

    def test_a_floor_above_the_ceiling_cannot_deadlock(self):
        limits = resolve_limits({**LIMITS, "min_questions": 20, "max_questions": 6})
        assert limits["min_questions"] == 6
        d = area_flow.prepare(complete_bb(), limits, question_count=6)
        assert d["should_close"]


class TestOrient:
    def test_orients_first(self):
        d = area_flow.prepare({}, resolve_limits(LIMITS), question_count=0)
        assert d["phase"] == "orient"

    def test_branches_once_areas_are_known(self):
        bb = {"role_areas": [{"name": "Invoicing"}], "orient_done": True}
        d = area_flow.prepare(bb, resolve_limits(LIMITS), question_count=3)
        assert d["phase"] == "branch"
        assert d["beat"]["area"] == "Invoicing"

    def test_seeds_areas_from_the_profile_when_orient_named_none(self):
        bb = {
            "orient_asked": 3,
            "profile": {"responsibilities": "invoice processing and month-end close"},
        }
        d = area_flow.prepare(bb, resolve_limits(LIMITS), question_count=3)
        assert d["phase"] == "branch"
        assert [a["name"] for a in bb["role_areas"]] == ["invoice processing", "month-end close"]

    def test_ends_rather_than_looping_when_there_is_nothing_to_ask_about(self):
        bb = {"orient_asked": 3, "profile": {}}
        d = area_flow.prepare(bb, resolve_limits(LIMITS), question_count=5)
        assert d["should_close"]

    def test_orientation_ends_early_once_areas_are_named(self):
        bb = {"role_areas": [], "orient_asked": 1}
        area_flow.finalize(bb, {"role_areas": ["Invoicing", "Month-end"]}, "orient", None)
        assert bb["orient_asked"] == 2
        assert bb["orient_done"] is True


class TestStallCounter:
    def test_resets_when_a_required_slot_is_filled(self):
        state = prepare_turn(
            {
                "blackboard": {"role_areas": [{"name": "Invoicing"}], "orient_done": True, "stall_turns": 1},
                "limits": LIMITS,
                "question_count": 3,
            }
        )
        out = finalize_turn(
            state,
            {
                "assistant_message": "q",
                "slots_filled": [
                    {"slot": "how_it_works", "area": "Invoicing", "value": "SAP", "confidence": 0.8}
                ],
            },
        )
        assert out["blackboard"]["stall_turns"] == 0

    def test_increments_when_a_turn_supplies_nothing(self):
        state = prepare_turn(
            {
                "blackboard": {"role_areas": [{"name": "Invoicing"}], "orient_done": True, "stall_turns": 1},
                "limits": LIMITS,
                "question_count": 3,
            }
        )
        out = finalize_turn(state, {"assistant_message": "q", "slots_filled": []})
        assert out["blackboard"]["stall_turns"] == 2


class TestParkingNotDrilling:
    def test_an_aside_is_parked_rather_than_chased(self):
        state = prepare_turn(
            {
                "blackboard": {"role_areas": [{"name": "Invoicing"}], "orient_done": True},
                "limits": LIMITS,
                "question_count": 3,
            }
        )
        out = finalize_turn(
            state,
            {
                "assistant_message": "q",
                "slots_filled": [
                    {"slot": "how_it_works", "area": "Invoicing", "value": "SAP", "confidence": 0.8}
                ],
                "parked": "mentioned a shadow spreadsheet nobody owns",
            },
        )
        parked = out["blackboard"]["dossier"]["parked"]
        assert parked[0]["note"] == "mentioned a shadow spreadsheet nobody owns"
        assert parked[0]["area"] == "Invoicing"
        # The next beat moves on to the next required slot rather than the aside.
        nxt = prepare_turn({**out, "question_count": 4})
        assert nxt["beat"]["slot"] == "friction"


class TestLegacyBlackboardUpgrade:
    def test_a_specialist_queue_blackboard_still_works(self):
        # In-flight conversations at deploy time carry the retired engine's shape.
        legacy = {
            "profile": {"role_title": "AP Clerk", "responsibilities": "invoices and approvals"},
            "agent_queue": [{"id": "domain_finance", "priority": 1, "question_budget": 4}],
            "agent_states": {"domain_finance": {"questions_asked": 3, "question_budget": 4}},
            "coverage": {"topics_required": ["daily_workflow"], "topics_covered": ["daily_workflow"]},
            "conversation_summary": "Talked about invoices.",
        }
        state = prepare_turn({"blackboard": legacy, "limits": LIMITS, "question_count": 3})

        assert not state["should_close"]
        assert "dossier" in state["blackboard"]
        # It had already asked real questions, so orientation is not restarted.
        assert state["blackboard"]["orient_asked"] == 3
        assert state["blackboard"]["conversation_summary"] == "Talked about invoices."
