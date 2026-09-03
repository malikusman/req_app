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


class TestFallbackPhrasing:
    """The fallback question goes to the EMPLOYEE, but the consultant states the need
    in the first person. Splicing it in verbatim produced "Could you tell me a bit
    more about i need to know who signs off...?" — broken grammar, and it reads as
    the consultant's private note rather than a question addressed to the employee.
    """

    def _body(self, statement):
        out = requirements._fallback_draft({"statement": statement}, reason="test")
        return out["questions"][0]["body"]

    def test_strips_first_person_need_framing(self):
        body = self._body("I need to know who signs off on a PI once a mismatch is found.")
        assert "i need to know" not in body.lower()
        assert "who signs off" in body.lower()

    def test_handles_the_other_common_framings(self):
        for statement in (
            "I want to understand how approvals actually work.",
            "Can you find out whether they can hold the payment.",
            "Please confirm who owns the spreadsheet.",
            "Find out how often this happens.",
        ):
            body = self._body(statement)
            lowered = body.lower()
            assert not lowered.startswith("could you tell me a bit more about i ")
            assert not lowered.startswith("could you tell me a bit more about can you")
            assert not lowered.startswith("could you tell me a bit more about please")

    def test_falls_back_to_something_sane_when_nothing_is_left(self):
        assert self._body("") == "Could you tell me a bit more about how that part of your work runs?"

    def test_keeps_a_statement_that_is_already_a_plain_subject(self):
        body = self._body("the approval threshold for supplier invoices")
        assert "approval threshold" in body.lower()

    def test_marks_itself_as_deterministic(self):
        out = requirements._fallback_draft({"statement": "I need to know X."}, reason="llm_failed: Timeout")
        assert out["generated_by"] == "deterministic"
        assert out["fallback_reason"] == "llm_failed: Timeout"
