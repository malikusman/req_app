"""The package is the consultant's only view of an interview, so what it drops and
what it keeps matters more than how it reads."""

from app import package

BB = {
    "role_areas": [{"name": "invoice processing"}, {"name": "month-end close"}],
    "conversation_summary": "Layla keys invoices into SAP and reconciles at month end.",
    "close_reason": "dossier_complete",
    "shared_findings": [{"finding": "Invoices are keyed into SAP then matched in Excel", "confidence": 0.8, "turn": 3}],
    "dossier": {
        "slots": {
            "how_it_works::invoice processing": {"value": "SAP, then match POs in Excel", "confidence": 0.8, "turn": 3},
            "friction::invoice processing": {"value": "Manual copy-paste, about 2 hours a day", "confidence": 0.9, "turn": 4},
            "friction::month-end close": {"value": "Approvals drag on", "confidence": 0.8, "turn": 6},
            "ai_current_usage": {"value": "No AI tools at work", "confidence": 0.9, "turn": 7},
        },
        "parked": [{"note": "a shadow spreadsheet nobody owns", "turn": 4, "area": "invoice processing"}],
    },
}
PAYLOAD = {
    "blackboard": BB,
    "profile": {"name": "Layla", "role_title": "AP Specialist", "department": "finance"},
    "company_name": "Acme",
    "language": "en",
    "insights": [],
}


def allowed():
    return package._allowed_numbers(package._evidence(PAYLOAD))


class TestGrounding:
    def test_internal_confidence_scores_are_not_grounded_figures(self):
        # Dumping the whole evidence object made the dossier's own confidences
        # (0.7/0.8/0.9) count as evidence, so "0.8%" would have passed the guard.
        assert allowed() == {"2hour"}

    def test_keeps_a_figure_that_appears_in_the_evidence(self):
        assert package._grounded("Matching takes about 2 hours a day.", allowed())

    def test_drops_an_invented_duration(self):
        # A bare integer with a unit is the shape a model invents here.
        assert package._grounded("This wastes 14 hours a week.", allowed()) is None

    def test_drops_a_real_number_with_the_wrong_unit(self):
        # Evidence says 2 hours; that does not license 2 days.
        assert package._grounded("Approvals take 2 days.", allowed()) is None

    def test_drops_an_invented_percentage(self):
        assert package._grounded("Cuts effort by 40%.", allowed()) is None

    def test_keeps_prose_with_no_figures(self):
        assert package._grounded("Approvals are slow and drag on.", allowed())


class TestNormalize:
    def test_an_ungrounded_recommendation_makes_the_package_unusable(self):
        # Falls back to deterministic rather than shipping an invented headline.
        out = package._normalize({"recommendation": "Saves 999 hours a month."}, package._evidence(PAYLOAD))
        assert out is None

    def test_drops_only_the_ungrounded_items(self):
        out = package._normalize(
            {
                "recommendation": "Start with invoice matching.",
                "issues": [
                    {"title": "Copy-paste", "body": "Manual copy-paste, about 2 hours a day.", "impact": "high"},
                    {"title": "Invented", "body": "Costs 30 hours a week.", "impact": "high"},
                ],
            },
            package._evidence(PAYLOAD),
        )
        assert [i["title"] for i in out["issues"]] == ["Copy-paste"]

    def test_rejects_a_bad_impact_band(self):
        out = package._normalize(
            {"recommendation": "Do the thing.",
             "issues": [{"title": "x", "body": "slow approvals", "impact": "catastrophic"}]},
            package._evidence(PAYLOAD),
        )
        assert out["issues"][0]["impact"] is None

    def test_tolerates_junk(self):
        ev = package._evidence(PAYLOAD)
        assert package._normalize(None, ev) is None
        assert package._normalize("nonsense", ev) is None
        assert package._normalize({"recommendation": "ok", "issues": "not a list"}, ev)["issues"] == []


class TestDeterministicFallback:
    def test_builds_a_real_package_without_a_model(self):
        out = package.build_package(PAYLOAD)

        assert out["generated_by"] == "deterministic"
        assert out["fallback_reason"] == "no_model"
        assert "invoice processing" in out["recommendation"]
        # Issues come from recorded friction, strongest first.
        assert len(out["issues"]) == 2
        # No solutions: inventing a remedy without a model would be guessing, and an
        # empty list is honest.
        assert out["solutions"] == []
        # The parked aside becomes the follow-up question.
        assert out["followup_questions"][0]["from_parked"] == "a shadow spreadsheet nobody owns"

    def test_says_so_when_the_interview_found_little(self):
        thin = {**PAYLOAD, "blackboard": {"role_areas": [{"name": "admin"}], "dossier": {"slots": {}, "parked": []}}}
        out = package.build_package(thin)

        assert "did not surface clear friction" in out["recommendation"]
        assert out["confidence"] <= 0.5
