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
        assert dossier.required_keys(bb_with([])) == ["ai_current_usage"]

        keys = dossier.required_keys(bb_with(["Invoicing"]))
        assert "how_it_works::Invoicing" in keys
        assert "friction::Invoicing" in keys
        assert len(keys) == 3

    def test_two_areas_yield_five_required_slots(self):
        assert len(dossier.required_keys(bb_with(["Invoicing", "Month-end"]))) == 5


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
            },
        )
        assert dossier.is_complete(bb, THRESHOLD)

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
            },
        )
        # ai_openness and volume_or_frequency are unfilled, yet the dossier is done.
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

    def test_switches_area_when_the_current_one_is_done(self):
        bb = bb_with(
            ["Invoicing", "Month-end"],
            {"how_it_works::Invoicing": 0.8, "friction::Invoicing": 0.8},
        )
        assert dossier.next_beat(bb, THRESHOLD, 3)["area"] == "Month-end"

    def test_force_switches_after_a_streak(self):
        bb = bb_with(["Invoicing", "Month-end"])
        bb["area_streak"] = 3
        assert dossier.next_beat(bb, THRESHOLD, switch_after=3)["area"] == "Month-end"

    def test_asks_ai_usage_once_every_area_is_understood(self):
        bb = bb_with(
            ["Invoicing"],
            {"how_it_works::Invoicing": 0.8, "friction::Invoicing": 0.8},
        )
        assert dossier.next_beat(bb, THRESHOLD, 3)["slot"] == "ai_current_usage"

    def test_falls_through_to_opportunistic_slots(self):
        bb = bb_with(
            ["Invoicing"],
            {
                "how_it_works::Invoicing": 0.8,
                "friction::Invoicing": 0.8,
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
                "ai_current_usage": 0.8,
                "ai_openness::Invoicing": 0.8,
                "volume_or_frequency": 0.8,
            },
        )
        assert dossier.next_beat(bb, THRESHOLD, 3) is None

    def test_returns_none_without_areas(self):
        assert dossier.next_beat(bb_with([]), THRESHOLD, 3) is None
