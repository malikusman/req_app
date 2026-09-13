"""Suggestions are what a consultant sees before deciding what to ask, so the
fallback matters as much as the model path: a review with no suggestions and no
explanation is indistinguishable from a review where nothing was worth asking."""

from app import deep_dive


def dossier_with(slots):
    return {"slots": {k: {"value": v, "confidence": 0.8, "turn": 1} for k, v in slots.items()}}


class TestQuantificationGaps:
    def test_finds_a_friction_with_no_cost_attached(self):
        d = dossier_with({
            "friction::Invoicing": "re-keying every invoice by hand",
            "how_it_works::Invoicing": "PDFs into Zoho",
        })

        gaps = deep_dive._quantification_gaps(d)
        assert [g["area"] for g in gaps] == ["Invoicing"]
        assert "re-keying" in gaps[0]["friction"]

    def test_ignores_a_friction_that_was_costed(self):
        d = dossier_with({
            "friction::Invoicing": "re-keying",
            "friction_cost::Invoicing": "20 minutes each, 30 a week",
        })

        assert deep_dive._quantification_gaps(d) == []

    def test_reports_each_uncosted_area_separately(self):
        d = dossier_with({
            "friction::Invoicing": "re-keying",
            "friction::Month-end": "chasing goods receipts",
            "friction_cost::Invoicing": "20 minutes each",
        })

        assert [g["area"] for g in deep_dive._quantification_gaps(d)] == ["Month-end"]

    def test_ignores_non_friction_slots(self):
        assert deep_dive._quantification_gaps(dossier_with({"how_it_works::A": "x"})) == []

    def test_tolerates_an_empty_dossier(self):
        assert deep_dive._quantification_gaps({}) == []


class TestWithoutAModel:
    def payload(self, slots):
        return {"dossier": dossier_with(slots), "max_suggestions": 3}

    def test_proposes_the_uncosted_friction(self):
        out = deep_dive.suggest_questions(self.payload({"friction::Invoicing": "re-keying"}))

        assert out["generated_by"] == "deterministic"
        assert out["fallback_reason"] == "no_model"
        assert len(out["suggestions"]) == 1
        assert out["suggestions"][0]["kind"] == "quantify"

    # The reason is the whole point: without it the consultant cannot judge whether
    # a question is worth one of the employee's few remaining answers.
    def test_every_suggestion_carries_a_reason(self):
        out = deep_dive.suggest_questions(self.payload({"friction::Invoicing": "re-keying"}))

        rationale = out["suggestions"][0]["rationale"]
        assert "never put a time to it" in rationale
        assert "Invoicing" in rationale
        assert "re-keying" in rationale

    # body goes to the employee; it must not leak the review context.
    def test_the_question_reads_as_one_addressed_to_the_employee(self):
        out = deep_dive.suggest_questions(self.payload({"friction::Invoicing": "re-keying"}))

        body = out["suggestions"][0]["body"].lower()
        assert body.startswith("roughly how much time")
        for leak in ("consultant", "report", "review", "requirement"):
            assert leak not in body

    # The friction is the employee's own mid-conversation clause, so it is quoted to
    # the consultant in the rationale rather than spliced into the question -- that
    # splice is what produced broken grammar in the requirement drafter.
    def test_asks_about_the_area_and_quotes_the_friction_to_the_consultant(self):
        out = deep_dive.suggest_questions(
            self.payload({"friction::Invoicing": "the re-keying is the worst part of it and it drags"})
        )
        suggestion = out["suggestions"][0]

        assert "the invoicing work" in suggestion["body"]
        assert "the re-keying is the worst part" in suggestion["rationale"]

    def test_trims_a_long_friction_in_the_rationale(self):
        out = deep_dive.suggest_questions(
            self.payload({"friction::Invoicing": "x " * 80})
        )

        assert out["suggestions"][0]["rationale"].count("...") == 1

    def test_suggests_nothing_when_everything_is_costed(self):
        out = deep_dive.suggest_questions(
            self.payload({"friction::A": "x", "friction_cost::A": "an hour a day"})
        )

        assert out["suggestions"] == []

    def test_respects_the_requested_limit(self):
        out = deep_dive.suggest_questions({
            "dossier": dossier_with({f"friction::Area{i}": "x" for i in range(5)}),
            "max_suggestions": 2,
        })

        assert len(out["suggestions"]) == 2


class TestModelOutputHandling:
    def call_with(self, monkeypatch, payload_out):
        monkeypatch.setattr(deep_dive, "llm_configured", lambda: True)
        monkeypatch.setattr(deep_dive, "_call", lambda _prompt: payload_out)
        return deep_dive.suggest_questions({
            "dossier": dossier_with({"friction::Invoicing": "re-keying"}),
            "max_suggestions": 3,
        })

    def test_keeps_a_well_formed_suggestion(self, monkeypatch):
        out = self.call_with(monkeypatch, {
            "suggestions": [
                {"body": "How many invoices land in a week?", "rationale": "Sizes the re-keying.",
                 "kind": "scale"}
            ]
        })

        assert out["generated_by"] == "llm"
        assert out["suggestions"][0]["kind"] == "scale"

    def test_drops_a_suggestion_with_no_reason(self, monkeypatch):
        out = self.call_with(monkeypatch, {"suggestions": [{"body": "How many?", "rationale": ""}]})

        # Nothing usable came back, so the deterministic gap stands in rather than
        # leaving the consultant with an empty list and no explanation.
        assert out["generated_by"] == "deterministic"
        assert out["fallback_reason"] == "empty_llm_output"

    def test_normalises_an_unknown_kind(self, monkeypatch):
        out = self.call_with(monkeypatch, {
            "suggestions": [{"body": "How?", "rationale": "Because.", "kind": "vibes"}]
        })

        assert out["suggestions"][0]["kind"] == deep_dive.DEFAULT_KIND

    def test_falls_back_when_the_model_raises(self, monkeypatch):
        monkeypatch.setattr(deep_dive, "llm_configured", lambda: True)

        def boom(_prompt):
            raise RuntimeError("upstream is down")

        monkeypatch.setattr(deep_dive, "_call", boom)
        out = deep_dive.suggest_questions({
            "dossier": dossier_with({"friction::Invoicing": "re-keying"}),
        })

        assert out["generated_by"] == "deterministic"
        assert "RuntimeError" in out["fallback_reason"]
