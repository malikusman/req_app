"""The four ways an interview ends, the order a turn runs in, and the guarantee
the interview neither runs long nor ends before there is anything worth packaging."""

from app import area_flow, dossier, interview_capture, multi_agent_graph, multi_agent_llm
from app.orchestrator import finalize_turn, prepare_turn, record_reply
from app.state import resolve_limits

LIMITS = {"max_questions": 8, "min_questions": 4, "stall_turns": 2, "slot_confidence": 0.6,
          "orient_questions": 3, "switch_after": 3}


# A cost answered in full (both halves, here in words) — what "filled" means for a
# friction_cost slot.
COMPLETE_EFFORT = {"frequency": {"as_said": "every day"}, "duration": {"as_said": "an hour"}, "effort_type": "active"}


def filled(areas, slots):
    bb = {"role_areas": [{"name": a} for a in areas], "orient_done": True}
    dossier.ensure_dossier(bb)
    for key, conf in slots.items():
        bb["dossier"]["slots"][key] = {"value": "x", "confidence": conf, "turn": 1}
        if key.startswith("friction_cost::"):
            bb["dossier"]["slots"][key]["effort"] = dict(COMPLETE_EFFORT)
    return bb


def complete_bb():
    return filled(
        ["Invoicing"],
        {
            "ai_current_usage": 0.8,
            "role_potential": 0.8,
            "how_it_works::Invoicing": 0.8,
            "friction::Invoicing": 0.8,
            # Captured friction unlocks the cost slot, so a complete dossier needs it.
            "friction_cost::Invoicing": 0.8,
        },
    )


class TestTermination:
    def test_ceiling_closes_even_with_an_empty_dossier(self):
        d = area_flow.prepare({}, resolve_limits(LIMITS), question_count=8)
        assert d["should_close"] and d["close_reason"] == "ceiling"

    def test_a_dossier_completed_by_the_last_allowed_answer_is_complete_not_ceiling(self):
        # The reply is recorded before this decision now, so the answer to the final
        # allowed question can complete the dossier. Calling that "ceiling" would
        # corrupt close_reason, the interview's one health metric.
        d = area_flow.prepare(complete_bb(), resolve_limits(LIMITS), question_count=8)
        assert d["close_reason"] == "dossier_complete"

    def test_ceiling_still_beats_a_stall(self):
        bb = filled(["Invoicing"], {})
        bb["stall_turns"] = 5
        d = area_flow.prepare(bb, resolve_limits(LIMITS), question_count=8)
        assert d["close_reason"] == "ceiling"

    def test_complete_dossier_closes_early(self):
        d = area_flow.prepare(complete_bb(), resolve_limits(LIMITS), question_count=5)
        assert d["should_close"] and d["close_reason"] == "dossier_complete"

    def test_below_the_floor_the_completion_exit_does_not_fire(self):
        # A terse employee must not end the interview at question 2 on the strength of
        # a dossier that merely looks complete — while there is still a real question
        # to ask, it is asked.
        bb = complete_bb()
        del bb["dossier"]["slots"]["role_potential"]
        d = area_flow.prepare(bb, resolve_limits(LIMITS), question_count=2)
        assert not d["should_close"]
        assert d["beat"]["slot"] == "role_potential"

    def test_below_the_floor_with_nothing_left_it_broadens_instead_of_closing(self):
        # One rich answer can fill several slots; ending at question 2 would have mapped
        # very little. Ask what else the work involves.
        d = area_flow.prepare(complete_bb(), resolve_limits(LIMITS), question_count=2)
        assert not d["should_close"]
        assert d["phase"] == "orient"

    def test_with_every_area_slot_used_it_closes_even_below_the_floor(self):
        bb = complete_bb()
        bb["role_areas"] = [{"name": "Invoicing"}, {"name": "B"}, {"name": "C"}]
        for area in ("B", "C"):
            for slot in ("how_it_works", "friction"):
                bb["dossier"]["slots"][f"{slot}::{area}"] = {"value": "x", "confidence": 0.8, "turn": 1}
        bb["dossier"]["slots"]["friction_cost::B"] = {"value": "x", "confidence": 0.8, "turn": 1,
                                                      "effort": dict(COMPLETE_EFFORT)}
        d = area_flow.prepare(bb, resolve_limits(LIMITS), question_count=2)
        assert d["should_close"] and d["close_reason"] == "dossier_complete"

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
        bb = {"role_areas": [], "orient_asked": 2}
        area_flow.record_reply(bb, ["Invoicing", "Month-end"])
        assert bb["orient_done"] is True

    def test_one_orient_answer_is_not_enough_to_stop_orienting(self):
        bb = {"role_areas": [], "orient_asked": 1}
        area_flow.record_reply(bb, ["Invoicing"])
        assert bb["orient_done"] is False


def branch_state(stall_turns=0, last_beat=None):
    bb = {"role_areas": [{"name": "Invoicing"}], "orient_done": True, "stall_turns": stall_turns}
    if last_beat:
        bb["last_beat"] = last_beat
    return {"blackboard": bb, "limits": LIMITS, "question_count": 3}


def capture(**overrides):
    return {**interview_capture.EMPTY_CAPTURE, "fallback_reason": None, **overrides}


class TestStallCounter:
    def test_resets_when_a_required_slot_is_filled(self):
        out = record_reply(
            branch_state(stall_turns=1),
            capture(slots_filled=[{"slot": "how_it_works", "area": "Invoicing", "value": "SAP", "confidence": 0.8}]),
        )
        assert out["blackboard"]["stall_turns"] == 0

    def test_increments_when_a_reply_supplies_nothing(self):
        out = record_reply(branch_state(stall_turns=1), capture())
        assert out["blackboard"]["stall_turns"] == 2

    def test_naming_a_new_area_counts_as_progress(self):
        out = record_reply(branch_state(stall_turns=1), capture(role_areas=["Month-end"]))
        assert out["blackboard"]["stall_turns"] == 0

    def test_the_kickoff_is_never_a_stalled_turn(self):
        state = {**branch_state(stall_turns=0), "question_count": 0}
        out = record_reply(state, capture())
        assert out["blackboard"]["stall_turns"] == 0


class TestParkingNotDrilling:
    def test_an_aside_is_parked_rather_than_chased(self):
        last = {"slot": "how_it_works", "area": "Invoicing", "intent": "how it works"}
        out = record_reply(
            branch_state(last_beat=last),
            capture(
                slots_filled=[{"slot": "how_it_works", "area": "Invoicing", "value": "SAP", "confidence": 0.8}],
                parked="mentioned a shadow spreadsheet nobody owns",
            ),
        )
        parked = out["blackboard"]["dossier"]["parked"]
        assert parked[0]["note"] == "mentioned a shadow spreadsheet nobody owns"
        assert parked[0]["area"] == "Invoicing"
        # The next beat moves on to the next required slot rather than the aside.
        assert prepare_turn(out)["beat"]["slot"] == "friction"


class TestAskTwiceThenTakeWhatTheyGave:
    def _after_two_attempts(self, reply):
        beat = {"slot": "friction_cost", "area": "Invoicing", "intent": "time"}
        bb = {"role_areas": [{"name": "Invoicing"}], "orient_done": True,
              "dossier": {"slots": {"friction::Invoicing": {"value": "x", "confidence": 0.8, "turn": 1}}, "parked": []}}
        area_flow.after_ask(bb, "branch", beat)
        area_flow.after_ask(bb, "branch", beat)
        return record_reply({"blackboard": bb, "limits": LIMITS, "question_count": 5, "user_message": reply}, capture())

    def test_a_second_vague_answer_to_a_time_question_is_accepted_as_unknown(self):
        out = self._after_two_attempts("It really depends on the season, hard to say.")
        entry = out["blackboard"]["dossier"]["slots"]["friction_cost::Invoicing"]
        assert entry["accepted_after_retry"] is True
        assert entry["effort"]["frequency"]["min"] is None  # words kept, number never guessed
        assert out["blackboard"]["stall_turns"] == 0
        # ...so the interview moves on rather than asking a third time.
        assert prepare_turn(out)["beat"]["slot"] != "friction_cost"

    def test_a_disengaged_reply_is_not_accepted(self):
        out = self._after_two_attempts("not sure")
        assert "friction_cost::Invoicing" not in out["blackboard"]["dossier"]["slots"]

    def test_the_first_attempt_is_never_short_circuited(self):
        beat = {"slot": "friction_cost", "area": "Invoicing", "intent": "time"}
        bb = {"role_areas": [{"name": "Invoicing"}], "orient_done": True}
        area_flow.after_ask(bb, "branch", beat)
        out = record_reply({"blackboard": bb, "limits": LIMITS, "question_count": 4,
                            "user_message": "It really depends on the season, hard to say."}, capture())
        assert "friction_cost::Invoicing" not in out["blackboard"]["dossier"]["slots"]


class TestAskTwiceKeepsHalfACost:
    def test_the_half_already_given_survives_a_second_vague_answer(self):
        beat = {"slot": "friction_cost", "area": "Invoicing", "intent": "time"}
        bb = {"role_areas": [{"name": "Invoicing"}], "orient_done": True,
              "dossier": {"slots": {
                  "friction::Invoicing": {"value": "x", "confidence": 0.8, "turn": 1},
                  "friction_cost::Invoicing": {"value": "every morning", "confidence": 0.8, "turn": 2,
                                               "effort": {"frequency": {"as_said": "every morning", "min": 1,
                                                                        "unit": "per_day"}}},
              }, "parked": []}}
        area_flow.after_ask(bb, "branch", beat)
        area_flow.after_ask(bb, "branch", beat)
        out = record_reply({"blackboard": bb, "limits": LIMITS, "question_count": 5,
                            "user_message": "Honestly it really varies from day to day."}, capture())
        entry = out["blackboard"]["dossier"]["slots"]["friction_cost::Invoicing"]
        assert entry["accepted_after_retry"] is True
        assert entry["effort"]["frequency"]["min"] == 1  # not overwritten by the vague reply
        assert prepare_turn(out)["beat"]["slot"] != "friction_cost"


class TestFutureWorkIsNotCurrentWork:
    def test_what_they_would_do_with_more_time_is_not_a_role_area(self):
        last = {"slot": "role_potential", "area": None, "intent": "more time"}
        out = record_reply(
            branch_state(last_beat=last),
            capture(
                role_areas=["vendor master data"],
                slots_filled=[
                    {"slot": "role_potential", "value": "Clean up vendor master data", "confidence": 0.8},
                    {"slot": "friction", "area": "vendor master data", "value": "never gets done", "confidence": 0.8},
                ],
            ),
        )
        bb = out["blackboard"]
        assert [a["name"] for a in bb["role_areas"]] == ["Invoicing"]
        assert "role_potential" in bb["dossier"]["slots"]
        assert "friction::vendor master data" not in bb["dossier"]["slots"]

    def test_the_ai_tools_they_use_are_not_a_role_area(self):
        last = {"slot": "ai_current_usage", "area": None, "intent": "ai"}
        out = record_reply(branch_state(last_beat=last), capture(role_areas=["AI tool experimentation"]))
        assert [a["name"] for a in out["blackboard"]["role_areas"]] == ["Invoicing"]

    def test_areas_named_in_answer_to_any_other_question_still_count(self):
        last = {"slot": "friction", "area": "Invoicing", "intent": "friction"}
        out = record_reply(branch_state(last_beat=last), capture(role_areas=["Month-end"]))
        assert "Month-end" in [a["name"] for a in out["blackboard"]["role_areas"]]


class TestAreasAreNotNamedTwice:
    def test_a_narrower_name_for_an_existing_area_is_skipped(self):
        bb = {"role_areas": [{"name": "customer enquiries and complaints"}]}
        area_flow.record_reply(bb, ["customer enquiries", "stock checks"])
        assert [a["name"] for a in bb["role_areas"]] == ["customer enquiries and complaints", "stock checks"]


class TestTurnOrder:
    """The reply is recorded BEFORE the next question is chosen."""

    def test_the_next_question_is_chosen_from_a_dossier_that_includes_this_reply(self):
        last = {"slot": "how_it_works", "area": "Invoicing", "intent": "how it works"}
        recorded = record_reply(
            branch_state(last_beat=last),
            capture(slots_filled=[{"slot": "how_it_works", "area": "Invoicing", "value": "SAP", "confidence": 0.8}]),
        )
        # Were the decision made first, it would ask how_it_works a second time.
        assert prepare_turn(recorded)["beat"]["slot"] == "friction"

    def test_the_answer_that_completes_the_dossier_closes_straight_away(self):
        bb = complete_bb()
        del bb["dossier"]["slots"]["role_potential"]
        bb["last_beat"] = {"slot": "role_potential", "area": None, "intent": "…"}
        recorded = record_reply(
            {"blackboard": bb, "limits": LIMITS, "question_count": 6},
            capture(slots_filled=[{"slot": "role_potential", "area": None,
                                   "value": "developing new suppliers", "confidence": 0.8}]),
        )
        decision = prepare_turn(recorded)
        assert decision["should_close"] and decision["close_reason"] == "dossier_complete"

    def test_asking_to_stop_closes_as_employee_ended(self):
        recorded = record_reply(branch_state(), capture(wants_to_stop=True))
        decision = prepare_turn(recorded)
        assert decision["should_close"] and decision["close_reason"] == "employee_ended"

    def test_a_degraded_capture_is_stamped_on_the_routing_decision(self):
        recorded = record_reply(branch_state(), capture(fallback_reason="unparseable: no JSON"))
        assert prepare_turn(recorded)["routing_decision"]["capture"] == "fallback: unparseable: no JSON"


class TestLastBeatTracking:
    """`last_beat` is what the NEXT reply is graded against: the question the employee
    will be answering, not the one after it."""

    def test_after_ask_stashes_the_beat_just_used(self):
        bb = {"role_areas": [{"name": "Invoicing"}], "orient_done": True}
        beat = {"slot": "how_it_works", "area": "Invoicing", "intent": "how it works"}
        area_flow.after_ask(bb, "branch", beat)
        assert bb["last_beat"] == beat
        assert bb["last_phase"] == "branch"

    def test_orient_questions_leave_last_beat_empty_and_count_up(self):
        bb = {"role_areas": [], "orient_asked": 0}
        area_flow.after_ask(bb, "orient", None)
        assert bb["last_beat"] is None
        assert bb["orient_asked"] == 1

    def test_finalize_counts_the_question_just_asked(self):
        state = prepare_turn(branch_state())
        out = finalize_turn(state, {"assistant_message": "How does invoicing get done?", "fallback_reason": None})
        assert out["question_count"] == 4
        assert out["blackboard"]["last_beat"]["slot"] == "how_it_works"
        assert out["assistant_message"] == "How does invoicing get done?"


class TestCapturePromptGradesAgainstTheQuestionAsked:
    def _state(self, last_beat=None):
        bb = {
            "role_areas": [{"name": "Invoicing"}], "orient_done": True,
            "profile": {}, "shared_findings": [], "dossier": {"slots": {}, "parked": []},
        }
        if last_beat is not None:
            bb["last_beat"] = last_beat
        return {"blackboard": bb, "limits": LIMITS}

    def test_names_the_slot_the_reply_is_answering(self):
        prev = {"slot": "friction", "area": "Invoicing", "intent": "what snags"}
        prompt = interview_capture._system_prompt(self._state(last_beat=prev), refresh_summary=False)
        assert "targeted the 'friction' slot for the area 'Invoicing'" in prompt

    def test_after_orientation_it_claims_no_particular_slot(self):
        prompt = interview_capture._system_prompt(self._state(), refresh_summary=False)
        assert "not about any one slot yet" in prompt

    def test_it_is_told_to_record_and_never_calculate(self):
        prompt = interview_capture._system_prompt(self._state(), refresh_summary=False)
        assert "Never compute totals" in prompt
        assert "averaged" in prompt


class TestCaptureNormalisation:
    def test_unknown_slots_and_junk_are_dropped_not_guessed(self):
        out = interview_capture.normalise({
            "slots_filled": [
                {"slot": "how_it_works", "area": "Invoicing", "value": "SAP", "confidence": "0.9"},
                {"slot": "ai_openness", "area": "Invoicing", "value": "sure", "confidence": 0.9},
                "not a dict",
            ],
            "parked": "null",
            "wants_to_stop": "yes",
        })
        assert [s["slot"] for s in out["slots_filled"]] == ["how_it_works"]
        assert out["slots_filled"][0]["confidence"] == 0.9
        assert out["parked"] is None
        # Only a real boolean true ends an interview.
        assert out["wants_to_stop"] is False


class TestTalking:
    def test_a_reply_wrapped_in_a_label_quotes_or_json_comes_out_clean(self):
        assert multi_agent_llm.clean_reply('Interviewer: "How does that usually go?"') == "How does that usually go?"
        assert multi_agent_llm.clean_reply('{"assistant_message": "What snags?"}') == "What snags?"

    def test_the_prompt_carries_the_language_rule(self):
        state = {
            "blackboard": {"profile": {}, "role_areas": [{"name": "Invoicing"}], "dossier": {"slots": {}, "parked": []}},
            "phase": "branch",
            "beat": {"slot": "friction", "area": "Invoicing", "intent": "what snags"},
            "limits": LIMITS, "preferred_language": "ar", "company_name": "Acme", "question_count": 3,
        }
        prompt = multi_agent_llm._build_talk_prompt(state)
        assert "Modern Standard Arabic" in prompt
        assert "ONLY if they are writing in that dialect" in prompt
        assert "Never suggest their work could be automated" in prompt

    def test_there_is_an_arabic_closing_message(self):
        assert "شكراً" in multi_agent_llm.closing_message("ar", "Sara")


class TestWholeInterviewWithoutAModel:
    """Mock mode end to end: the graph records, decides and talks, and closes on a
    filled dossier with role potential asked last."""

    def test_runs_to_dossier_complete(self):
        bb = {"profile": {"name": "Sara", "role_title": "AP clerk", "responsibilities": "invoices and month-end"}}
        limits = resolve_limits(None)  # the real ceiling: a two-area interview is ten questions
        state = {"blackboard": bb, "limits": limits, "question_count": 0, "history": [],
                 "preferred_language": "en", "employee_name": "Sara", "company_name": "Acme",
                 "user_message": "I'm Sara, an AP clerk. invoices and month-end"}
        slots_asked = []
        for _ in range(limits["max_questions"] + 2):
            out = multi_agent_graph.execute_multi_agent_turn(state)
            if out.get("completed"):
                break
            slots_asked.append((out.get("routing_decision") or {}).get("slot"))
            state = {**state, "blackboard": out["blackboard"], "question_count": out["question_count"],
                     "history": state["history"] + [{"role": "user", "content": state["user_message"]},
                                                    {"role": "assistant", "content": out["assistant_message"]}],
                     "user_message": "It is all done by hand in the ERP, checking every line twice."}

        assert out["completed"] is True
        assert out["blackboard"]["close_reason"] == "dossier_complete"
        assert slots_asked[-1] == "role_potential"
        # Two orient questions, three slots on each of two areas, AI use, role potential.
        assert out["question_count"] == 10


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
