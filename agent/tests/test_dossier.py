"""The dossier decides how long an interview runs, so it is tested without a model."""

from app import dossier

THRESHOLD = 0.6


def bb_with(areas, slots=None):
    bb = {"role_areas": [{"name": a} for a in areas]}
    dossier.ensure_dossier(bb)
    for key, conf in (slots or {}).items():
        bb["dossier"]["slots"][key] = {"value": "x", "confidence": conf, "turn": 1}
    return bb


class TestRequiredKeys:
    def test_grows_with_each_area(self):
        assert dossier.required_keys(bb_with([]), THRESHOLD) == ["ai_current_usage"]

        keys = dossier.required_keys(bb_with(["Invoicing"]), THRESHOLD)
        assert "how_it_works::Invoicing" in keys
        assert "friction::Invoicing" in keys
        # friction_cost is not required yet -- its trigger has not fired.
        assert "friction_cost::Invoicing" not in keys
        assert len(keys) == 3

    def test_two_areas_yield_five_required_slots(self):
        assert len(dossier.required_keys(bb_with(["Invoicing", "Month-end"]), THRESHOLD)) == 5

    # A cost slot unlocks only once that area's friction is captured: asking how
    # long something takes before you know what it is makes no sense.
    def test_cost_becomes_required_once_friction_is_captured(self):
        bb = bb_with(["Invoicing"], {"friction::Invoicing": 0.8})

        assert "friction_cost::Invoicing" in dossier.required_keys(bb, THRESHOLD)

    def test_cost_stays_locked_while_friction_is_only_weakly_answered(self):
        bb = bb_with(["Invoicing"], {"friction::Invoicing": 0.4})

        assert "friction_cost::Invoicing" not in dossier.required_keys(bb, THRESHOLD)

    # Without a cap this scales with the area count and every interview hits the
    # ceiling; the consultant-guided follow-up covers anything beyond two.
    def test_at_most_two_areas_get_costed(self):
        bb = bb_with(
            ["Invoicing", "Month-end", "Reporting"],
            {
                "friction::Invoicing": 0.8,
                "friction::Month-end": 0.8,
                "friction::Reporting": 0.8,
            },
        )

        costed = [k for k in dossier.required_keys(bb, THRESHOLD) if k.startswith("friction_cost")]
        assert len(costed) == dossier.MAX_QUANTIFIED_AREAS

    # merge_slots asks "could this ever be required?" when counting progress, so a
    # cost filled for a third area must still register rather than read as a stall.
    def test_without_a_threshold_every_cost_slot_counts_as_required(self):
        bb = bb_with(["A", "B", "C"])

        keys = dossier.required_keys(bb)
        assert len([k for k in keys if k.startswith("friction_cost")]) == 3


class TestCompleteness:
    def test_never_complete_without_an_area(self):
        # Named areas are themselves a requirement.
        bb = bb_with([], {"ai_current_usage": 0.9})
        assert not dossier.is_complete(bb, THRESHOLD)

    def test_complete_when_every_required_slot_is_filled(self):
        bb = bb_with(
            ["Invoicing"],
            {
                "ai_current_usage": 0.8,
                "how_it_works::Invoicing": 0.8,
                "friction::Invoicing": 0.7,
                "friction_cost::Invoicing": 0.7,
            },
        )
        assert dossier.is_complete(bb, THRESHOLD)

    def test_captured_friction_with_no_cost_is_not_complete(self):
        bb = bb_with(
            ["Invoicing"],
            {
                "ai_current_usage": 0.8,
                "how_it_works::Invoicing": 0.8,
                "friction::Invoicing": 0.8,
            },
        )

        assert not dossier.is_complete(bb, THRESHOLD)
        assert dossier.missing_required(bb, THRESHOLD) == ["friction_cost::Invoicing"]

    def test_low_confidence_does_not_count_as_filled(self):
        bb = bb_with(
            ["Invoicing"],
            {
                "ai_current_usage": 0.8,
                "how_it_works::Invoicing": 0.8,
                "friction::Invoicing": 0.4,
            },
        )
        assert not dossier.is_complete(bb, THRESHOLD)
        assert dossier.missing_required(bb, THRESHOLD) == ["friction::Invoicing"]

    def test_opportunistic_slots_never_hold_the_interview_open(self):
        bb = bb_with(
            ["Invoicing"],
            {
                "ai_current_usage": 0.8,
                "how_it_works::Invoicing": 0.8,
                "friction::Invoicing": 0.8,
                "friction_cost::Invoicing": 0.8,
            },
        )
        # ai_openness is unfilled, yet the dossier is done.
        assert dossier.is_complete(bb, THRESHOLD)


class TestMergeSlots:
    def test_counts_newly_filled_required_slots_as_progress(self):
        bb = bb_with(["Invoicing"])
        progress = dossier.merge_slots(
            bb,
            [{"slot": "how_it_works", "area": "Invoicing", "value": "SAP then Excel", "confidence": 0.8}],
            turn=2,
            threshold=THRESHOLD,
        )
        assert progress == 1
        assert dossier.is_filled(bb["dossier"], "how_it_works::Invoicing", THRESHOLD)

    def test_refilling_the_same_slot_is_not_progress(self):
        bb = bb_with(["Invoicing"], {"how_it_works::Invoicing": 0.8})
        progress = dossier.merge_slots(
            bb,
            [{"slot": "how_it_works", "area": "Invoicing", "value": "more detail", "confidence": 0.9}],
            turn=3,
            threshold=THRESHOLD,
        )
        assert progress == 0

    def test_a_weaker_answer_does_not_overwrite_a_stronger_one(self):
        bb = bb_with(["Invoicing"], {"friction::Invoicing": 0.9})
        dossier.merge_slots(
            bb,
            [{"slot": "friction", "area": "Invoicing", "value": "vague", "confidence": 0.3}],
            turn=4,
            threshold=THRESHOLD,
        )
        assert bb["dossier"]["slots"]["friction::Invoicing"]["confidence"] == 0.9

    def test_ignores_a_per_area_slot_for_an_unknown_area(self):
        # A hallucinated area name would otherwise create a required slot that
        # nothing can ever fill, and the interview would run to the ceiling.
        bb = bb_with(["Invoicing"])
        dossier.merge_slots(
            bb,
            [{"slot": "friction", "area": "Something Invented", "value": "x", "confidence": 0.9}],
            turn=2,
            threshold=THRESHOLD,
        )
        assert bb["dossier"]["slots"] == {}

    def test_ignores_unknown_slot_names(self):
        bb = bb_with(["Invoicing"])
        dossier.merge_slots(
            bb, [{"slot": "not_a_slot", "value": "x", "confidence": 0.9}], turn=2, threshold=THRESHOLD
        )
        assert bb["dossier"]["slots"] == {}

    def test_tolerates_junk(self):
        bb = bb_with(["Invoicing"])
        assert dossier.merge_slots(bb, None, 1, THRESHOLD) == 0
        assert dossier.merge_slots(bb, "nonsense", 1, THRESHOLD) == 0
        assert dossier.merge_slots(bb, [None, 3, "x"], 1, THRESHOLD) == 0


class TestParked:
    def test_captures_an_aside_once(self):
        bb = bb_with(["Invoicing"])
        dossier.park(bb, "they mentioned a shadow spreadsheet", 3, area="Invoicing")
        dossier.park(bb, "they mentioned a shadow spreadsheet", 4, area="Invoicing")
        assert len(bb["dossier"]["parked"]) == 1

    def test_ignores_empty_notes(self):
        bb = bb_with(["Invoicing"])
        dossier.park(bb, None, 1)
        dossier.park(bb, "   ", 1)
        assert bb["dossier"]["parked"] == []

    def test_is_bounded(self):
        bb = bb_with(["Invoicing"])
        for i in range(dossier.MAX_PARKED + 5):
            dossier.park(bb, f"note {i}", i)
        assert len(bb["dossier"]["parked"]) == dossier.MAX_PARKED


class TestNextBeat:
    def test_asks_required_slots_before_opportunistic_ones(self):
        bb = bb_with(["Invoicing"])
        beat = dossier.next_beat(bb, THRESHOLD, switch_after=3)
        assert beat["slot"] == "how_it_works"
        assert beat["area"] == "Invoicing"

    def test_moves_to_friction_once_how_it_works_is_in(self):
        bb = bb_with(["Invoicing"], {"how_it_works::Invoicing": 0.8})
        assert dossier.next_beat(bb, THRESHOLD, 3)["slot"] == "friction"

    # Captured friction unlocks the cost question, so it lands before the switch.
    def test_costs_the_friction_it_just_heard_about(self):
        bb = bb_with(
            ["Invoicing", "Month-end"],
            {"how_it_works::Invoicing": 0.8, "friction::Invoicing": 0.8},
        )
        beat = dossier.next_beat(bb, THRESHOLD, 3)
        assert beat["slot"] == "friction_cost"
        assert beat["area"] == "Invoicing"

    def test_switches_area_when_the_current_one_is_done(self):
        bb = bb_with(
            ["Invoicing", "Month-end"],
            {
                "how_it_works::Invoicing": 0.8,
                "friction::Invoicing": 0.8,
                "friction_cost::Invoicing": 0.8,
            },
        )
        assert dossier.next_beat(bb, THRESHOLD, 3)["area"] == "Month-end"

    def test_force_switches_after_a_streak(self):
        bb = bb_with(["Invoicing", "Month-end"])
        bb["area_streak"] = 3
        assert dossier.next_beat(bb, THRESHOLD, switch_after=3)["area"] == "Month-end"

    def test_asks_ai_usage_once_every_area_is_understood(self):
        bb = bb_with(
            ["Invoicing"],
            {
                "how_it_works::Invoicing": 0.8,
                "friction::Invoicing": 0.8,
                "friction_cost::Invoicing": 0.8,
            },
        )
        assert dossier.next_beat(bb, THRESHOLD, 3)["slot"] == "ai_current_usage"

    def test_falls_through_to_opportunistic_slots(self):
        bb = bb_with(
            ["Invoicing"],
            {
                "how_it_works::Invoicing": 0.8,
                "friction::Invoicing": 0.8,
                "friction_cost::Invoicing": 0.8,
                "ai_current_usage": 0.8,
            },
        )
        assert dossier.next_beat(bb, THRESHOLD, 3)["slot"] == "ai_openness"

    def test_returns_none_when_nothing_is_left_to_want(self):
        bb = bb_with(
            ["Invoicing"],
            {
                "how_it_works::Invoicing": 0.8,
                "friction::Invoicing": 0.8,
                "friction_cost::Invoicing": 0.8,
                "ai_current_usage": 0.8,
                "ai_openness::Invoicing": 0.8,
            },
        )
        assert dossier.next_beat(bb, THRESHOLD, 3) is None

    def test_does_not_chase_a_third_area_cost(self):
        filled = {"ai_current_usage": 0.8}
        for area in ("A", "B", "C"):
            filled[f"how_it_works::{area}"] = 0.8
            filled[f"friction::{area}"] = 0.8
            filled[f"ai_openness::{area}"] = 0.8
        filled["friction_cost::A"] = 0.8
        filled["friction_cost::B"] = 0.8
        bb = bb_with(["A", "B", "C"], filled)

        # C's friction is captured, but the cap has been spent on A and B.
        assert dossier.next_beat(bb, THRESHOLD, 3) is None

    def test_returns_none_without_areas(self):
        assert dossier.next_beat(bb_with([]), THRESHOLD, 3) is None
