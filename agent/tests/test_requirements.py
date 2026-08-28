"""The two halves fail safe in OPPOSITE directions, deliberately — that is the part
worth testing without a model."""

from app import requirements


class TestDraftFallback:
    def test_builds_a_question_from_the_consultant_own_words(self):
        # A consultant who stated a need and got nothing would have to state it again.
        out = requirements.draft_questions(
            {"statement": "I need to know who signs off on approvals.", "max_questions": 2}
        )

        assert out["generated_by"] == "deterministic"
        assert out["fallback_reason"] == "no_model"
        assert len(out["questions"]) == 1
        # Quotes rather than paraphrases: without a model a paraphrase is a guess.
        assert "who signs off on approvals" in out["questions"][0]["body"]

    def test_uses_only_the_first_sentence(self):
        out = requirements.draft_questions(
            {"statement": "I need the approval owner. Also the SLA. And the tooling.",
             "max_questions": 1}
        )

        body = out["questions"][0]["body"]
        assert "approval owner" in body
        assert "SLA" not in body

    def test_survives_an_empty_statement(self):
        out = requirements.draft_questions({"statement": "", "max_questions": 1})

        assert len(out["questions"]) == 1
        assert out["questions"][0]["body"]

    def test_never_exceeds_the_hard_draft_cap(self):
        out = requirements.draft_questions({"statement": "Need lots.", "max_questions": 99})

        assert len(out["questions"]) <= requirements.MAX_DRAFT


class TestEvaluateFallback:
    def test_no_answers_is_not_satisfied(self):
        out = requirements.evaluate_requirement({"statement": "Who approves?", "answers": []})

        assert out["satisfied"] is False

    def test_fails_to_not_satisfied_without_a_model(self):
        # Wrongly closing a requirement loses the consultant's question silently;
        # wrongly leaving it open costs at most one more question, and the caps
        # bound that. So the fallback must be "not satisfied".
        out = requirements.evaluate_requirement(
            {"statement": "Who approves?", "answers": [{"question": "Who?", "answer": "Sara does."}]}
        )

        assert out["satisfied"] is False
        assert out["missing_aspects"]
        assert out["generated_by"] == "deterministic"

    def test_ignores_answers_with_no_content(self):
        out = requirements.evaluate_requirement(
            {"statement": "Who approves?", "answers": [{"question": "Who?", "answer": ""}]}
        )

        assert out["satisfied"] is False
        assert "No answer received yet." in out["missing_aspects"]
