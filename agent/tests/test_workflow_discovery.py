"""Workflow discovery regressions: evidence, efficient gaps, correction and review."""
import copy

import pytest

from app import workflow
from app.interview_capture import normalise
from app.orchestrator import prepare_turn, record_reply
from app.state import resolve_limits


ANSWER = ("Each morning invoices arrive by email. I compare the purchase order and receipt in SAP, "
          "check totals in Excel, ask the buyer to approve mismatches, post the invoice in SAP, "
          "and send the posted invoice list to accounts payable. About 30 a day takes 90 minutes "
          "of my own work. Missing receipts go back to the buyer for approval. "
          "Duplicate entry is the main bottleneck, adding 10 minutes per day. "
          "I do not use AI. I would simplify duplicate entry to investigate unmatched invoices.")
VALUES = {
    "trigger_inputs": "Each morning invoices arrive by email.",
    "steps_decisions": "I compare the purchase order and receipt in SAP",
    "tools": "check totals in Excel",
    "frequency_volume": "About 30 a day",
    "active_effort": "90 minutes of my own work",
    "exceptions": "Missing receipts go back to the buyer for approval.",
    "dependencies": "ask the buyer to approve mismatches",
    "output_recipient": "send the posted invoice list to accounts payable",
}


def update(values=None, **kwargs):
    return {"name": "Supplier invoice processing", "evidence": "invoices arrive by email",
            "facts": {k: {"value": v, "evidence": v, "status": "known"}
                      for k, v in (VALUES if values is None else values).items()}, **kwargs}


def state(**kwargs):
    return {"user_message": ANSWER, "source_message_id": 123, "question_count": 1,
            "limits": resolve_limits(None), **kwargs}


def recorded(updates=None):
    updates = copy.deepcopy([update()] if updates is None else updates)
    if updates:
        updates[0].setdefault("facts", {})["bottlenecks"] = {"value": "Duplicate entry is the main bottleneck",
            "status": "known", "evidence": "Duplicate entry is the main bottleneck, adding 10 minutes per day.",
            "effort": {"frequency": {"as_said": "per day", "min": 1, "max": 1, "unit": "per_day"},
                       "duration": {"as_said": "10 minutes", "min": 10, "max": 10, "unit": "minutes"}, "effort_type": "active"}}
    return record_reply(state(), normalise({"workflow_updates": updates, "global_facts": {
        "ai_current_usage": {"value": "Does not use AI", "evidence": "I do not use AI.", "status": "known"},
        "role_potential": {"value": "Simplify duplicate entry to investigate unmatched invoices",
                           "evidence": "I would simplify duplicate entry to investigate unmatched invoices.", "status": "known"}}}))


def approval_state(bb, reply):
    return state(user_message=reply, history=[{"role": "assistant", "content": workflow.review_message(bb), "message_id": 600}])


def test_one_rich_answer_captures_all_workflow_details_and_goes_to_review():
    result = recorded()
    assert len(workflow.ledger(result["blackboard"])["tasks"]) == 1
    assert workflow.gaps(workflow.ledger(result["blackboard"])["tasks"][0]) == []
    assert prepare_turn(result)["phase"] == "review"  # no minimum question quota
    assert not prepare_turn(result)["should_close"]


def test_related_missing_details_are_grouped_without_asking_supplied_details():
    result = recorded([update({k: v for k, v in VALUES.items() if k not in ("active_effort", "frequency_volume")})])
    beat = prepare_turn(result)["beat"]
    assert beat["fields"] == ["frequency_volume", "active_effort"]
    assert "tools" not in beat["fields"]
    assert "how much" in workflow.fallback(beat)


def test_unrelated_reply_does_not_fill_any_gap_even_after_multiple_attempts():
    result = recorded([update({"steps_decisions": VALUES["steps_decisions"]})])
    for count in (2, 3):
        result = record_reply({**result, "question_count": count, "user_message": "I watched a long film yesterday"},
                              normalise({"workflow_updates": []}))
    assert workflow.gaps(workflow.ledger(result["blackboard"])["tasks"][0])
    assert not workflow.ledger(result["blackboard"])["confirmation"]


def test_invented_or_interviewer_sourced_facts_are_rejected():
    bad = update({"active_effort": "It takes 5 minutes"})
    result = record_reply(state(history=[{"role": "assistant", "content": "It takes 5 minutes"}]),
                          normalise({"workflow_updates": [bad]}))
    assert not workflow.ledger(result["blackboard"])["tasks"][0]["facts"]


def test_fact_retains_original_employee_message_identity():
    result = recorded()
    fact = workflow.ledger(result["blackboard"])["tasks"][0]["facts"]["tools"]
    assert fact["evidence"]["message_id"] == 123
    assert fact["evidence"]["quote"] in ANSWER


def test_correction_replaces_old_fact_and_invalidates_confirmation():
    result = recorded()
    bb = result["blackboard"]
    data = workflow.ledger(bb)
    data["confirmation"] = {"revision": data["revision"]}
    correction = {"id": "task-1", "name": "Supplier invoice processing", "facts": {
        "active_effort": {"value": "60 minutes", "evidence": "60 minutes", "correction": True}}}
    result = record_reply({**result, "question_count": 2, "user_message": "Correction: 60 minutes"},
                          normalise({"workflow_updates": [correction]}))
    data = workflow.ledger(result["blackboard"])
    fact = data["tasks"][0]["facts"]["active_effort"]
    assert fact["value"] == "60 minutes"
    assert fact["history"][0]["value"] == VALUES["active_effort"]
    assert data["confirmation"] is None


def test_reextraction_paraphrases_do_not_change_revision():
    result = recorded()
    bb = result["blackboard"]
    revision = workflow.ledger(bb)["revision"]
    revised = update()
    revised["facts"]["tools"]["value"] = "Excel spreadsheet"
    workflow.merge(bb, {"workflow_updates": [revised]}, state())
    assert workflow.ledger(bb)["revision"] == revision


@pytest.mark.parametrize("reply", ["yes", "That's correct.", "Confirmed", "نعم"])
def test_explicit_confirmation_only_after_summary_was_presented(reply):
    result = recorded()
    bb = result["blackboard"]
    workflow.next_decision(bb, resolve_limits(None), 1)
    bb["last_phase"] = "review"
    workflow.merge(bb, {"workflow_updates": []}, approval_state(bb, reply))
    decision = workflow.next_decision(bb, resolve_limits(None), 2)
    assert decision["should_close"]
    assert workflow.ledger(bb)["outcome"] == "successful"


@pytest.mark.parametrize("reply", ["maybe", "yes but that time is wrong", "no", "ok"])
def test_ambiguous_or_corrective_reply_never_confirms(reply):
    result = recorded()
    bb = result["blackboard"]
    workflow.next_decision(bb, resolve_limits(None), 1)
    bb["last_phase"] = "review"
    workflow.merge(bb, {"workflow_updates": [], "summary_confirmed": True}, approval_state(bb, reply))
    assert workflow.ledger(bb)["confirmation"] is None


def test_confirmation_without_review_cannot_complete():
    result = recorded()
    bb = result["blackboard"]
    workflow.merge(bb, {"workflow_updates": [], "summary_confirmed": True}, state(user_message="yes"))
    assert not workflow.ledger(bb)["confirmation"]


def test_new_periodic_work_during_review_is_explored():
    result = recorded()
    bb = result["blackboard"]
    workflow.next_decision(bb, resolve_limits(None), 1)
    bb["last_phase"] = "review"
    text = "I also match payments every Friday in Excel."
    workflow.merge(bb, {"workflow_updates": [{"name": "Weekly payment matching", "evidence": text,
                    "facts": {"frequency_volume": {"value": "every Friday", "evidence": "every Friday"}}}]},
                   state(user_message=text))
    decision = workflow.next_decision(bb, resolve_limits(None), 2)
    assert decision["phase"] == "branch"
    assert decision["beat"]["area"] == "Weekly payment matching"


def test_unknown_information_stays_unknown_without_repeated_questions():
    result = recorded([update({k: v for k, v in VALUES.items() if k != "active_effort"})])
    bb = result["blackboard"]
    text = "It varies and I cannot estimate my working time."
    workflow.merge(bb, {"workflow_updates": [{"id": "task-1", "name": "Supplier invoice processing",
        "facts": {"active_effort": {"value": text, "evidence": text, "status": "unavailable"}}}]}, state(user_message=text))
    assert workflow.next_decision(bb, resolve_limits(None), 2)["phase"] == "review"
    assert "unavailable" == workflow.ledger(bb)["tasks"][0]["facts"]["active_effort"]["status"]


@pytest.mark.parametrize("count,stall,reason", [(14, 0, "ceiling"), (4, 3, "stalled")])
def test_incomplete_terminal_exits_are_not_successful(count, stall, reason):
    result = recorded([update({"tools": VALUES["tools"]})])
    bb = result["blackboard"]
    bb["stall_turns"] = stall
    decision = workflow.next_decision(bb, resolve_limits(None), count)
    assert decision["close_reason"] == reason
    assert workflow.ledger(bb)["outcome"] == "needs_follow_up"
    assert workflow.ledger(bb)["follow_up"]


def test_supporting_chasing_is_not_another_full_questionnaire():
    result = recorded()
    bb = result["blackboard"]
    text = "Chasing the buyer is part of invoice processing, not another process."
    workflow.merge(bb, {"workflow_updates": [{"name": "Buyer chasing", "importance": "supporting", "evidence": text}]},
                   state(user_message=text))
    assert workflow.next_decision(bb, resolve_limits(None), 2)["phase"] == "review"


def test_contradiction_remains_a_gap_until_corrected():
    result = recorded()
    bb = result["blackboard"]
    text = "It takes 5 hours"
    workflow.merge(bb, {"workflow_updates": [{"id": "task-1", "name": "Supplier invoice processing",
        "facts": {"active_effort": {"value": text, "evidence": text, "contradiction": True}}}]}, state(user_message=text))
    assert "active_effort" in workflow.gaps(workflow.ledger(bb)["tasks"][0])


def test_imperfect_quote_retains_actual_source_message_without_fabricated_quote():
    anchor = workflow.evidence("90 minutes per day", state(), 123)
    assert anchor["message_id"] == 123
    assert anchor["quote"] == ANSWER
    assert anchor["match"] == "message_reference"
    assert workflow.evidence("invented words", state(), 999) is None


def test_schema_requires_explicit_fields_for_each_known_workflow():
    bb = recorded()["blackboard"]
    schema = workflow.capture_schema(bb)["json_schema"]["schema"]
    tasks = schema["properties"]["workflow_updates"]
    assert tasks["required"] == ["task-1"]
    assert set(tasks["properties"]["task-1"]["properties"]["facts"]["required"]) == set(workflow.FIELDS + workflow.DISCOVERY_FIELDS)


def test_legacy_work_areas_are_not_forgotten_when_adding_the_ledger():
    bb = {"role_areas": [{"name": "Payment matching"}, {"name": "Monthly reconciliation"}]}
    workflow.merge(bb, {"workflow_updates": []}, state())
    assert {t["name"] for t in workflow.ledger(bb)["tasks"]} == {"Payment matching", "Monthly reconciliation"}
    assert all(workflow.gaps(t) for t in workflow.ledger(bb)["tasks"])


def test_known_boundary_gaps_outrank_another_tasks_effort_question():
    result = recorded([update({k: v for k, v in VALUES.items() if k != "active_effort"})])
    bb = result["blackboard"]
    text = "I also match payments every Friday."
    workflow.merge(bb, {"workflow_updates": [{"name": "Payment matching", "evidence": text,
                    "facts": {"frequency_volume": {"value": "every Friday", "evidence": "every Friday"}}}]}, state(user_message=text))
    decision = workflow.next_decision(bb, resolve_limits(None), 2)
    assert decision["beat"]["area"] == "Payment matching"
    assert "steps_decisions" in decision["beat"]["fields"]


def test_unavailable_core_workflow_remains_follow_up_even_after_confirmation():
    result = recorded()
    bb = result["blackboard"]
    workflow.ledger(bb)["tasks"][0]["facts"]["steps_decisions"]["status"] = "unavailable"
    workflow.next_decision(bb, resolve_limits(None), 1)
    bb["last_phase"] = "review"
    workflow.merge(bb, {"workflow_updates": []}, approval_state(bb, "yes"))
    result = workflow.next_decision(bb, resolve_limits(None), 2)
    assert result["close_reason"] == "insufficient_information"
    assert workflow.ledger(bb)["outcome"] == "needs_follow_up"


def test_evidence_backfill_recovers_a_supplied_handoff_without_changing_other_facts(monkeypatch):
    from types import SimpleNamespace
    import json
    from app import interview_capture
    bb = recorded([update({k: v for k, v in VALUES.items() if k != "dependencies"})])["blackboard"]
    before = copy.deepcopy(workflow.ledger(bb)["tasks"][0]["facts"])
    response = {"task-1": {"dependencies": {"value": "The buyer approves mismatches", "status": "known",
                "evidence": VALUES["dependencies"], "source_message_id": 123, "correction": False, "contradiction": False}}}
    class Model:
        def invoke(self, messages):
            return SimpleNamespace(content=json.dumps(response), response_metadata={})
    monkeypatch.setattr(interview_capture, "_recording_model", lambda *args: Model())
    captured = interview_capture._recover_supplied_gaps(state(blackboard=bb), {"workflow_updates": []})
    workflow.merge(bb, captured, state())
    facts = workflow.ledger(bb)["tasks"][0]["facts"]
    assert "dependencies" in facts
    assert all(facts[field] == value for field, value in before.items())


def test_backfill_includes_an_empty_legacy_task_with_evidence_in_earlier_answers(monkeypatch):
    from types import SimpleNamespace
    import json
    from app import interview_capture
    bb = {"role_areas": [{"name": "Supplier invoice processing"}]}
    workflow.merge(bb, {"workflow_updates": []}, state())
    response = {"task-1": {field: {"value": value, "evidence": value, "source_message_id": 123,
                                   "status": "known", "correction": False, "contradiction": False}
                            for field, value in VALUES.items()}}
    class Model:
        def invoke(self, messages):
            return SimpleNamespace(content=json.dumps(response), response_metadata={})
    monkeypatch.setattr(interview_capture, "_recording_model", lambda *args: Model())
    captured = interview_capture._recover_supplied_gaps(state(blackboard=bb), {"workflow_updates": []})
    workflow.merge(bb, captured, state())
    assert workflow.gaps(workflow.ledger(bb)["tasks"][0]) == []


def test_current_workflow_effort_supersedes_stale_reporting_figures():
    result = recorded()
    bb = result["blackboard"]
    bb["dossier"]["slots"]["friction_cost::Supplier invoice processing"] = {
        "value": "old 45 minute estimate", "confidence": .9,
        "effort": {"frequency": {"min": 1, "unit": "per_day"}, "duration": {"min": 45, "unit": "minutes"}}}
    workflow.project_slots(bb)
    cost = bb["dossier"]["slots"]["friction_cost::Supplier invoice processing"]
    assert cost["value"] == "Duplicate entry is the main bottleneck"
    assert cost["effort"]["duration"]["min"] == 10  # bottleneck cost, not whole task


def test_numeric_batch_effort_is_preserved_for_existing_annual_hours_calculator():
    full = update()
    full["facts"]["active_effort"]["effort"] = {
        "frequency": {"as_said": "daily batch", "min": 1, "max": 1, "unit": "per_day"},
        "duration": {"as_said": "90 minutes", "min": 90, "max": 90, "unit": "minutes"}, "effort_type": "active"}
    result = recorded([full])
    cost = result["blackboard"]["dossier"]["slots"]["friction_cost::Supplier invoice processing"]
    assert cost["effort"]["frequency"]["min"] == 1
    assert cost["effort"]["duration"]["min"] == 10
    assert workflow.ledger(result["blackboard"])["tasks"][0]["facts"]["active_effort"]["effort"]["duration"]["min"] == 90


def test_handover_uses_current_facts_instead_of_superseded_historical_summaries():
    from app.package import _evidence, _evidence_text
    bb = recorded()["blackboard"]
    bb["conversation_summary"] = "Outdated estimate: 45 minutes"
    bb["shared_findings"] = [{"finding": "Old effort was 45 minutes"}]
    evidence = _evidence({"blackboard": bb, "insights": ["Previously said 45 minutes"]})
    assert "45" not in _evidence_text(evidence)
    assert "90 minutes" in _evidence_text(evidence)


def test_invoice_answer_cannot_fill_weekly_payment_workflow():
    bb = {"role_areas": [{"name": "Supplier invoice processing"}, {"name": "Weekly payment matching"}]}
    history = [{"role": "assistant", "content": "Walk me through invoice processing", "area": "Supplier invoice processing", "task_id": "task-1"},
               {"role": "user", "content": ANSWER, "message_id": 123}]
    s = state(blackboard=bb, history=history)
    wrong = update(id="task-2", name="Weekly payment matching")
    workflow.merge(bb, {"workflow_updates": [wrong]}, s)
    assert not workflow.ledger(bb)["tasks"][1]["facts"]
    assert workflow.next_decision(bb, resolve_limits(None), 1)["phase"] == "branch"


def test_previously_cross_assigned_facts_are_invalidated_before_confirmation():
    bb = recorded()["blackboard"]
    task = workflow.ledger(bb)["tasks"][0]
    history = [{"role": "assistant", "content": "Tell me about invoices", "area": "Supplier invoice processing", "task_id": "other-task"},
               {"role": "user", "content": ANSWER, "message_id": 123}]
    # The answer to an invoice question belongs to its invoice workflow.
    assert workflow.belongs_to_task(task["facts"]["tools"]["evidence"], task, state(history=history))
    task["name"] = "Weekly payment matching"
    history[0]["area"] = "Supplier invoice processing"
    workflow.merge(bb, {"workflow_updates": []}, state(history=history))
    assert not task["facts"]
    assert task["invalidated_facts"]


def test_an_answer_can_explicitly_describe_another_workflow_without_losing_its_facts():
    bb = {"role_areas": [{"name": "Invoice processing"}, {"name": "Weekly payment matching"}]}
    reply = "I also match payments every Friday in Excel."
    history = [{"role": "assistant", "content": "Tell me about invoices", "area": "Invoice processing", "task_id": "task-1"},
               {"role": "user", "content": reply, "message_id": 124}]
    workflow.merge(bb, {"workflow_updates": [{"id": "task-2", "name": "Weekly payment matching",
        "facts": {"frequency_volume": {"value": "every Friday", "evidence": "every Friday", "source_message_id": 124}}}]},
        state(blackboard=bb, user_message=reply, source_message_id=124, history=history))
    assert "frequency_volume" in workflow.ledger(bb)["tasks"][1]["facts"]


def test_approval_cannot_confirm_a_summary_that_was_never_delivered():
    bb = recorded()["blackboard"]
    workflow.next_decision(bb, resolve_limits(None), 1)
    workflow.review_message(bb)
    bb["last_phase"] = "review"
    workflow.merge(bb, {"workflow_updates": [], "summary_confirmed": True},
                   state(user_message="yes", history=[{"role": "assistant", "content": "An older question"}]))
    assert workflow.ledger(bb)["confirmation"] is None


def test_accounts_responsibility_list_is_not_effort_or_an_ordered_workflow():
    text = "Most of my time goes into processing supplier invoices, checking invoice details, updating records in Excel and SAP, and matching payments."
    bb = {}
    facts = {f: {"value": text, "status": "known", "evidence": text} for f in ("active_effort", "steps_decisions")}
    workflow.merge(bb, {"workflow_updates": [{"name": "Supplier invoice processing", "evidence": "supplier invoices", "facts": facts}]},
                   state(user_message=text))
    assert not workflow.ledger(bb)["tasks"][0]["facts"]


def test_current_prompt_context_excludes_old_summaries_and_superseded_facts():
    bb = recorded()["blackboard"]
    data = workflow.ledger(bb)
    data["presented_summary"] = {"text": "Superseded monthly task glued to invoices"}
    data["tasks"][0]["facts"]["active_effort"]["history"] = [{"value": "Old 45 minute estimate"}]
    context = workflow.prompt_context(bb)
    assert "Superseded" not in context and "Old 45 minute estimate" not in context
    assert "90 minutes" in context


def test_generated_kickoff_is_not_employee_evidence():
    s = state(question_count=0, user_message="A generated recap inferring invoices received by email", source_message_id=20,
              history=[{"role": "user", "content": "I handle invoices", "message_id": 19}])
    assert [source["id"] for source in workflow.sources(s)] == [19]
    assert workflow.evidence("invoices received by email", s, 20) is None


def test_steps_can_be_restructured_using_existing_evidence_without_explicit_correction_flag():
    result = recorded()
    bb = result["blackboard"]
    old = workflow.ledger(bb)["tasks"][0]["facts"]["steps_decisions"]
    revised = {"name": "Supplier invoice processing", "id": "task-1", "facts": {
        "steps_decisions": {"value": "Compare the PO and goods receipt in SAP; check totals in Excel; post approved invoices", "evidence": old["evidence"]["quote"]}}}
    workflow.merge(bb, {"workflow_updates": [revised]}, state())
    assert workflow.ledger(bb)["tasks"][0]["facts"]["steps_decisions"]["value"].startswith("Compare the PO")


def test_summary_organizes_current_facts_instead_of_repeating_responsibilities_as_time():
    bb = recorded()["blackboard"]
    message = workflow.review_message(bb)
    assert "Steps:" in message and "Active time:" in message and "Frequency / volume:" in message
    assert message.count(VALUES["active_effort"]) == 1


def test_monthly_report_announcement_is_not_its_preparation_workflow():
    text = "I also prepare a monthly summary of processed invoices and pending payments for the finance manager."
    bb = {}
    workflow.merge(bb, {"workflow_updates": [{"name": "Monthly reporting", "evidence": text,
        "facts": {"steps_decisions": {"value": "Compile SAP data in Excel and prepare the report", "evidence": text},
                  "output_recipient": {"value": "Finance manager receives monthly summary", "evidence": text}}}]},
        state(user_message=text))
    task = workflow.ledger(bb)["tasks"][0]
    assert "steps_decisions" not in task["facts"]
    assert "output_recipient" in task["facts"]


def test_profile_priority_is_not_frequency_and_task_name_is_not_a_trigger():
    text = "Most of my time goes into supplier invoices and matching payments."
    bb = {}
    workflow.merge(bb, {"workflow_updates": [{"name": "Supplier invoice processing", "evidence": "supplier invoices",
        "facts": {"frequency_volume": {"value": "/most of my time", "evidence": text},
                  "trigger_inputs": {"value": "supplier invoices", "evidence": text}}}]}, state(user_message=text))
    assert not workflow.ledger(bb)["tasks"][0]["facts"]


def test_finish_only_answer_does_not_claim_invoice_processing_steps():
    text = "Usually, I process invoices daily, around 40 to 50 a day. Once they're done, I update SAP and Excel and the finance manager reviews the records."
    bb = {"last_beat": {"task_id": "task-1", "area": "Supplier invoice processing"}}
    workflow.merge(bb, {"workflow_updates": [{"name": "Supplier invoice processing", "evidence": "invoices",
        "facts": {"steps_decisions": {"value": "Process invoices; update SAP and Excel; manager reviews", "evidence": text},
                  "frequency_volume": {"value": "40 to 50 invoices daily", "evidence": text}}}]}, state(user_message=text, blackboard=bb))
    facts = workflow.ledger(bb)["tasks"][0]["facts"]
    assert "steps_decisions" not in facts and "frequency_volume" in facts


def test_complete_basic_workflow_still_explores_avoidable_bottleneck():
    result = recorded()
    bb = result["blackboard"]
    del workflow.ledger(bb)["tasks"][0]["facts"]["bottlenecks"]
    beat = workflow.next_decision(bb, resolve_limits(None), 3)["beat"]
    assert beat["fields"] == ["bottlenecks"]
    assert beat["area"] is None  # compare workflows, not another form per task


def test_bottleneck_cost_follow_up_only_requests_missing_duration():
    bb = recorded()["blackboard"]
    fact = workflow.ledger(bb)["tasks"][0]["facts"]["bottlenecks"]
    fact["effort"]["duration"] = None
    beat = workflow.next_decision(bb, resolve_limits(None), 4)["beat"]
    assert beat["missing_half"] == "duration"
    assert "how often" not in workflow.fallback(beat).lower()


def test_task_time_is_not_published_as_friction_cost_when_bottleneck_cost_unknown():
    bb = recorded()["blackboard"]
    del workflow.ledger(bb)["tasks"][0]["facts"]["bottlenecks"]
    workflow.project_slots(bb)
    assert "friction_cost::Supplier invoice processing" not in bb["dossier"]["slots"]
    assert workflow.ledger(bb)["superseded_task_costs"]


def test_ordinary_tools_are_not_evidence_of_no_ai_use():
    bb = recorded()["blackboard"]
    del workflow.ledger(bb)["global_facts"]["ai_current_usage"]
    bb["dossier"]["slots"].pop("ai_current_usage", None)
    workflow.merge(bb, {"workflow_updates": [], "global_facts": {
        "ai_current_usage": {"value": "No AI", "evidence": "I use Excel and SAP", "source_message_id": 124}}},
        state(user_message="I use Excel and SAP", source_message_id=124))
    assert not workflow.global_answered(bb, "ai_current_usage")
    assert workflow.next_decision(bb, resolve_limits(None), 4)["beat"]["slot"] == "ai_current_usage"


def test_ai_and_improvement_already_supplied_are_not_asked_again():
    result = recorded()
    assert workflow.next_decision(result["blackboard"], resolve_limits(None), 3)["phase"] == "review"


def test_hypothetical_freed_time_activity_is_not_a_current_workflow():
    bb = recorded()["blackboard"]
    text = "I would investigate supplier trends if I had more time."
    workflow.merge(bb, {"workflow_updates": [{"name": "Supplier trend investigation", "evidence": text}]},
                   state(user_message=text))
    assert len(workflow.ledger(bb)["tasks"]) == 1


def test_related_supporting_steps_do_not_become_separate_summary_or_report_workflows():
    from app.package import _evidence
    bb = recorded()["blackboard"]
    workflow.merge(bb, {"workflow_updates": [{"name": "SAP checks", "importance": "supporting",
        "evidence": VALUES["steps_decisions"], "facts": {}}]}, state())
    workflow.project_slots(bb)
    assert len(workflow.ledger(bb)["tasks"]) == 2  # audit evidence retained
    assert "• SAP checks" not in workflow.review_message(bb)
    assert _evidence({"blackboard": bb})["areas"] == ["Supplier invoice processing"]
    assert bb["role_areas"] == [{"name": "Supplier invoice processing"}]


def test_no_bottlenecks_is_answered_without_forcing_a_cost_question():
    bb = recorded()["blackboard"]
    fact = workflow.ledger(bb)["tasks"][0]["facts"]["bottlenecks"]
    fact.update(status="not_applicable", value="No significant delays", effort=None)
    assert workflow.next_decision(bb, resolve_limits(None), 4)["phase"] == "review"
    workflow.project_slots(bb)
    assert "friction::Supplier invoice processing" not in bb["dossier"]["slots"]


def test_repeated_fallback_asks_for_concrete_example_instead_of_same_generic_question():
    from app.multi_agent_llm import fallback_question
    beat = {"slot": "workflow", "area": "Supplier invoice processing", "fields": ["steps_decisions"]}
    first = workflow.fallback(beat)
    question = fallback_question(state(beat=beat, phase="branch", history=[{"role": "assistant", "content": first}]))
    assert question != first and "recent example" in question


def test_repeated_answer_keeps_its_new_message_identity():
    text = "About 30 a day"
    s = state(user_message=text, source_message_id=125,
              history=[{"role": "user", "content": text, "message_id": 124}])
    assert [m["id"] for m in workflow.sources(s)] == [124, 125]
    assert workflow.evidence(text, s)["message_id"] == 125


@pytest.mark.parametrize("estimate", ["20 mins", "1.5h", "2 hrs", "30m", "half an hour"])
def test_natural_time_estimates_are_accepted_without_another_question(estimate):
    bb = recorded()["blackboard"]
    workflow.merge(bb, {"workflow_updates": [{"id": "task-1", "name": "Supplier invoice processing",
        "facts": {"active_effort": {"value": estimate, "evidence": estimate, "correction": True}}}]},
        state(user_message=f"Correction: {estimate}", source_message_id=126))
    assert workflow.ledger(bb)["tasks"][0]["facts"]["active_effort"]["value"] == estimate


def test_ai_contradiction_needs_clarification_and_correction_preserves_history():
    bb = recorded()["blackboard"]
    text = "I use Copilot every day"
    fact = {"value": text, "evidence": text, "contradiction": True}
    workflow.merge(bb, {"workflow_updates": [], "global_facts": {"ai_current_usage": fact}}, state(user_message=text))
    assert not workflow.global_answered(bb, "ai_current_usage")
    assert workflow.next_decision(bb, resolve_limits(None), 4)["beat"]["slot"] == "ai_current_usage"
    fact["correction"] = True
    workflow.merge(bb, {"workflow_updates": [], "global_facts": {"ai_current_usage": fact}}, state(user_message=text))
    current = workflow.ledger(bb)["global_facts"]["ai_current_usage"]
    assert current["status"] == "known" and len(current["history"]) == 2
    assert "Does not use AI" not in workflow.prompt_context(bb)


def test_exception_followup_also_explores_friction_without_extra_broad_pass():
    bb = recorded()["blackboard"]
    facts = workflow.ledger(bb)["tasks"][0]["facts"]
    del facts["exceptions"]
    del facts["bottlenecks"]
    beat = workflow.next_decision(bb, resolve_limits(None), 4)["beat"]
    assert beat["fields"] == ["exceptions", "bottlenecks"]
    assert "who else" not in workflow.fallback(beat)  # handoff already captured
    assert "avoidable" in workflow.fallback(beat)


def test_null_backfill_does_not_erase_captured_uncertain_ai_answer(monkeypatch):
    from types import SimpleNamespace
    from app import interview_capture
    bb = recorded()["blackboard"]
    del workflow.ledger(bb)["global_facts"]["ai_current_usage"]
    bb["dossier"]["slots"].pop("ai_current_usage", None)
    fact = {"value": "Not sure whether the built-in suggestions use AI", "status": "uncertain",
            "evidence": "Not sure whether the built-in suggestions use AI"}
    class Model:
        def invoke(self, messages):
            return SimpleNamespace(content='{"global_facts":{"ai_current_usage":null}}', response_metadata={})
    monkeypatch.setattr(interview_capture, "_recording_model", lambda *args: Model())
    captured = interview_capture._recover_supplied_gaps(state(blackboard=bb, user_message=fact["evidence"]),
        {"workflow_updates": [], "global_facts": {"ai_current_usage": fact}})
    assert captured["global_facts"]["ai_current_usage"] == fact


def test_exact_generated_question_repeat_is_replaced_by_contextual_clarification(monkeypatch):
    from app import multi_agent_llm
    beat = {"slot": "workflow", "area": "Supplier invoice processing", "fields": ["active_effort"]}
    question = workflow.fallback(beat)
    monkeypatch.setattr(multi_agent_llm, "llm_configured", lambda: True)
    monkeypatch.setattr(multi_agent_llm, "_talk", lambda *args: question)
    result = multi_agent_llm.write_question(state(blackboard=recorded()["blackboard"], beat=beat,
        phase="branch", history=[{"role": "assistant", "content": question}]))
    assert result["fallback_reason"] == "repeated_question"
    assert result["assistant_message"] != question
    assert "working time" in result["assistant_message"]


def test_same_bottleneck_evidence_cannot_be_copied_into_a_second_process():
    bb = recorded()["blackboard"]
    first = workflow.ledger(bb)["tasks"][0]
    quote = first["facts"]["bottlenecks"]["evidence"]["quote"]
    workflow.merge(bb, {"workflow_updates": [{"name": "Payment reconciliation", "evidence": quote,
        "facts": {"bottlenecks": {"value": "Duplicate entry wastes time", "evidence": quote}}}]}, state())
    assert "bottlenecks" not in workflow.ledger(bb)["tasks"][1]["facts"]


def test_unclear_summary_reply_does_not_reprint_summary_and_later_approval_is_valid():
    from app.multi_agent_llm import write_question
    bb = recorded()["blackboard"]
    workflow.next_decision(bb, resolve_limits(None), 3)
    summary = workflow.review_message(bb)
    history = [{"role": "assistant", "content": summary, "message_id": 600}]
    clarification = write_question(state(blackboard=bb, phase="review", history=history))["assistant_message"]
    assert summary not in clarification and "summary above" in clarification
    bb["last_phase"] = "review"
    history += [{"role": "user", "content": "I just check them", "message_id": 601},
                {"role": "assistant", "content": clarification, "message_id": 602}]
    workflow.merge(bb, {"workflow_updates": [], "summary_confirmed": True},
                   state(blackboard=bb, user_message="Yes, that is correct.", history=history))
    assert workflow.ledger(bb)["confirmation"]["summary_message_id"] == 600


def test_scoped_vague_answer_is_not_a_workflow_walkthrough():
    bb = recorded()["blackboard"]
    task = workflow.ledger(bb)["tasks"][0]
    del task["facts"]["steps_decisions"]
    bb["last_beat"] = {"area": task["name"], "task_id": task["id"]}
    workflow.merge(bb, {"workflow_updates": [{"id": task["id"], "name": task["name"],
        "facts": {"steps_decisions": {"value": "Checks invoices", "evidence": "I just check them."}}}]},
        state(blackboard=bb, user_message="I just check them.", source_message_id=127))
    assert "steps_decisions" in workflow.gaps(task)


def test_explicit_no_bottleneck_does_not_require_a_time_estimate_even_if_model_labels_it_known():
    bb = recorded()["blackboard"]
    text = "There is no significant bottleneck in invoice processing."
    workflow.merge(bb, {"workflow_updates": [{"id": "task-1", "name": "Supplier invoice processing",
        "facts": {"bottlenecks": {"value": "No significant bottleneck", "status": "known", "evidence": text,
                                  "correction": True}}}]}, state(user_message=text, source_message_id=128))
    fact = workflow.ledger(bb)["tasks"][0]["facts"]["bottlenecks"]
    assert fact["status"] == "not_applicable" and not fact.get("effort")
    assert workflow.next_decision(bb, resolve_limits(None), 4)["phase"] == "review"


FINANCE_CONFIRMATIONS = [
    "Yeah, that looks accurate to me. I think you've covered both my daily invoice work and the monthly reconciliation process. Nothing major to add right now.",
    "yes, it reflects",
    "yes, looks good, nothing else to add",
]


@pytest.mark.parametrize("reply", FINANCE_CONFIRMATIONS)
def test_finance_officer_confirmation_closes_on_first_reply_even_at_stall_or_ceiling(reply, monkeypatch):
    from app import multi_agent_graph
    bb = recorded()["blackboard"]
    workflow.next_decision(bb, resolve_limits(None), 7)
    bb["last_phase"] = "review"
    bb["stall_turns"] = 2
    shown = workflow.review_message(bb)
    monkeypatch.setattr(multi_agent_graph, "capture_reply", lambda *a, **k: pytest.fail("Pure confirmation should not be re-extracted"))
    out = multi_agent_graph.execute_multi_agent_turn(state(blackboard=bb, user_message=reply,
        question_count=14, history=[{"role": "assistant", "content": shown, "message_id": 600}]))
    data = workflow.ledger(out["blackboard"])
    assert out["completed"] and data["outcome"] == "successful"
    assert data["confirmation"]["summary_message_id"] == 600
    assert "confirmed and saved" in out["assistant_message"]
    assert "?" not in out["assistant_message"]


@pytest.mark.parametrize("reply", ["Yes, but I also prepare payroll", "That looks accurate except the time is wrong",
                                  "Yeah, mostly accurate", "Yes. I also approve payments.", "Yes, it reflects. Please change the hours.",
                                  "Yes. I think you've covered invoices but monthly payroll is missing."])
def test_agreement_with_new_information_or_correction_is_not_pure_confirmation(reply):
    assert not workflow.explicit_approval(reply)


def test_invoice_delay_cannot_become_an_invented_improvement_preference():
    bb = recorded()["blackboard"]
    del workflow.ledger(bb)["global_facts"]["role_potential"]
    bb["dossier"]["slots"].pop("role_potential", None)
    text = "I have to contact the department that sent it and get it corrected. That back-and-forth takes the most time, especially when I'm waiting for someone to respond or approve it."
    invented = {"value": "I want simplified work processes and freed time would allow me to focus more on verifying transactions and improving accuracy.",
                "evidence": "invented preference", "source_message_id": 674, "status": "known"}
    workflow.merge(bb, {"workflow_updates": [], "global_facts": {"role_potential": invented}},
                   state(user_message=text, source_message_id=674))
    assert not workflow.global_answered(bb, "role_potential")
    summary = workflow.review_message(bb)
    assert invented["value"] not in summary
    assert "Improvement priority: Unknown" in summary


def test_historical_unsupported_preference_is_removed_from_ledger_and_legacy_projection():
    bb = recorded()["blackboard"]
    data = workflow.ledger(bb)
    bad = {"value": "I want more accuracy", "status": "known", "evidence": {
        "quote": "Waiting for approvals takes time", "match": "message_reference", "message_id": 674}}
    data["global_facts"]["role_potential"] = copy.deepcopy(bad)
    bb["dossier"]["slots"]["role_potential"] = {"value": bad["value"], "confidence": .8}
    workflow.merge(bb, {"workflow_updates": []}, state())
    assert "role_potential" not in data["global_facts"]
    assert "role_potential" not in bb["dossier"]["slots"]
    assert data["invalidated_globals"][-1]["fact"] == bad


def test_direct_short_preference_persists_without_invented_explanation():
    bb = recorded()["blackboard"]
    bb["last_beat"] = {"slot": "role_potential"}
    text = "Duplicate entry"
    workflow.merge(bb, {"workflow_updates": [], "global_facts": {"role_potential": {
        "value": "Automate duplicate entry to focus on financial strategy", "evidence": text, "status": "known"}}},
        state(blackboard=bb, user_message=text, source_message_id=130))
    bb["last_beat"] = {"slot": "workflow_review"}
    workflow.merge(bb, {"workflow_updates": []}, state(user_message="yes", source_message_id=131))
    assert workflow.ledger(bb)["global_facts"]["role_potential"]["value"] == text


def test_missing_optional_handoff_does_not_extend_a_sufficient_eight_question_interview():
    bb = recorded()["blackboard"]
    facts = workflow.ledger(bb)["tasks"][0]["facts"]
    del facts["dependencies"]
    assert workflow.next_decision(bb, resolve_limits(None), 8)["phase"] == "review"
    # Actual process understanding cannot be skipped to meet the target.
    del facts["steps_decisions"]
    decision = workflow.next_decision(bb, resolve_limits(None), 9)
    assert decision["phase"] == "branch" and decision["beat"]["fields"] == ["steps_decisions"]


def test_finance_role_description_does_not_replace_an_actual_invoice_walkthrough():
    text = "I mostly deal with invoices, process payments, and keep financial records updated. I also spend quite a bit of time checking transactions and making sure everything matches properly."
    bb = {}
    workflow.merge(bb, {"workflow_updates": [{"name": "Invoice processing", "evidence": text,
        "facts": {"steps_decisions": {"value": "Receive invoices, check transactions, update records", "evidence": text}}}]},
        state(user_message=text))
    assert "steps_decisions" in workflow.gaps(workflow.ledger(bb)["tasks"][0])


def test_unknown_optional_priority_and_cost_do_not_block_confirmation_after_eight_questions():
    bb = recorded()["blackboard"]
    data = workflow.ledger(bb)
    del data["global_facts"]["role_potential"]
    bb["dossier"]["slots"].pop("role_potential", None)
    data["tasks"][0]["facts"]["bottlenecks"].pop("effort")
    assert workflow.next_decision(bb, resolve_limits(None), 8)["phase"] == "review"
    bb["last_phase"] = "review"
    summary = workflow.review_message(bb)
    assert "Improvement priority: Unknown" in summary
    workflow.merge(bb, {"workflow_updates": []}, state(blackboard=bb, user_message=FINANCE_CONFIRMATIONS[0],
        history=[{"role": "assistant", "content": summary, "message_id": 900}]))
    assert workflow.next_decision(bb, resolve_limits(None), 9)["close_reason"] == "dossier_complete"
    assert data["outcome"] == "successful"


def test_volunteered_unknown_improvement_preference_is_not_asked_again_when_extraction_omits_it():
    bb = recorded()["blackboard"]
    text = "I do not have an improvement preference to share. Please leave that unknown."
    workflow.merge(bb, {"workflow_updates": [], "global_facts": {}}, state(user_message=text, source_message_id=140))
    preference = workflow.ledger(bb)["global_facts"]["role_potential"]
    assert preference["status"] == "unavailable" and preference["value"] == text
    assert workflow.next_decision(bb, resolve_limits(None), 4)["phase"] == "review"


def test_month_end_record_pull_is_supported_trigger_and_input():
    text = "At month end I pull payment records from Excel and our accounting system."
    bb = {}
    workflow.merge(bb, {"workflow_updates": [{"name": "Monthly reconciliation", "evidence": text,
        "facts": {"trigger_inputs": {"value": "Month-end payment records from Excel and accounting system", "evidence": text}}}]},
        state(user_message=text))
    assert "trigger_inputs" not in workflow.gaps(workflow.ledger(bb)["tasks"][0])


def test_longer_quote_does_not_reassign_an_invoice_bottleneck_to_monthly_work():
    text = "Invoice corrections involve waiting for the department to respond. At month end I prepare expense summaries."
    bb = {}
    workflow.merge(bb, {"workflow_updates": [
        {"name": "Invoice processing", "evidence": "Invoice corrections", "facts": {
            "bottlenecks": {"value": "Waiting for corrections", "evidence": "waiting for the department to respond"}}},
        {"name": "Monthly summary", "evidence": "At month end I prepare expense summaries", "facts": {
            "bottlenecks": {"value": "Waiting for invoice corrections", "evidence": "Invoice corrections involve waiting for the department to respond."}}}
    ]}, state(user_message=text))
    assert "bottlenecks" not in workflow.ledger(bb)["tasks"][1]["facts"]


def test_waiting_cost_is_not_labelled_as_extra_active_work():
    bb = recorded()["blackboard"]
    fact = workflow.ledger(bb)["tasks"][0]["facts"]["bottlenecks"]
    fact["effort"] = {"effort_type": "waiting", "duration": {"as_said": "waiting for approval"}}
    assert "Waiting time: waiting for approval" in workflow.review_message(bb)


def test_explicit_inability_to_estimate_a_bottleneck_cost_is_not_repeatedly_questioned():
    bb = recorded()["blackboard"]
    text = "Discrepancies take extra time to fix; I cannot estimate that extra time separately."
    workflow.merge(bb, {"workflow_updates": [{"id": "task-1", "name": "Supplier invoice processing", "facts": {
        "bottlenecks": {"value": "Discrepancies take extra time to fix", "evidence": "Discrepancies take extra time to fix", "correction": True}}}]},
        state(user_message=text, source_message_id=150))
    fact = workflow.ledger(bb)["tasks"][0]["facts"]["bottlenecks"]
    assert fact["cost_unavailable"]
    assert workflow.next_decision(bb, resolve_limits(None), 4)["phase"] == "review"


LATEST_CONFIRMATION = "Yes, that looks accurate to me. You've covered all three processes pretty well, and I don't have anything major to add."


def test_latest_finance_confirmation_completes_without_a_second_summary_or_model_call(monkeypatch):
    from app import multi_agent_graph
    bb = recorded()["blackboard"]
    workflow.next_decision(bb, resolve_limits(None), 8)
    summary = workflow.review_message(bb)
    bb["last_phase"] = "review"
    # Reproduce the real snapshot's audit-only revision increment.
    workflow.ledger(bb)["revision"] += 1
    monkeypatch.setattr(multi_agent_graph, "capture_reply", lambda *a, **k: pytest.fail("Confirmation re-extracted"))
    monkeypatch.setattr(multi_agent_graph, "write_question", lambda *a, **k: pytest.fail("Summary or question repeated"))
    out = multi_agent_graph.execute_multi_agent_turn(state(blackboard=bb, user_message=LATEST_CONFIRMATION,
        question_count=9, history=[{"role": "assistant", "content": summary, "message_id": 800}]))
    assert out["completed"] and workflow.ledger(out["blackboard"])["outcome"] == "successful"
    assert "Here’s my understanding" not in out["assistant_message"]
    assert workflow.ledger(out["blackboard"])["confirmation"]["summary_message_id"] == 800


def test_confirmation_tail_with_a_correction_is_not_accepted():
    assert not workflow.explicit_approval("Yes, that looks accurate. You've covered invoices but the reporting time is wrong, and I don't have anything major to add.")


def test_identical_summary_is_not_displayed_again_after_an_audit_revision_change():
    from app.multi_agent_llm import write_question
    bb = recorded()["blackboard"]
    summary = workflow.review_message(bb)
    workflow.ledger(bb)["revision"] += 1
    result = write_question(state(blackboard=bb, phase="review", history=[{"role": "assistant", "content": summary}]))
    assert "Here’s my understanding" not in result["assistant_message"]


def test_punctuation_only_restructure_retains_audit_without_invalidating_summary():
    bb = recorded()["blackboard"]
    data = workflow.ledger(bb)
    revision = data["revision"]
    old = data["tasks"][0]["facts"]["steps_decisions"]
    data["confirmation"] = {"revision": revision}
    workflow.merge(bb, {"workflow_updates": [{"id": "task-1", "name": "Supplier invoice processing", "facts": {
        "steps_decisions": {"value": old["value"] + ".", "evidence": old["evidence"]["quote"]}}}]}, state())
    assert data["revision"] == revision and data["confirmation"]["revision"] == revision
    assert data["tasks"][0]["facts"]["steps_decisions"]["history"]


def test_capitalization_only_change_does_not_present_the_full_summary_again():
    from app.multi_agent_llm import write_question
    bb=recorded()["blackboard"]
    summary=workflow.review_message(bb)
    workflow.ledger(bb)["tasks"][0]["facts"]["tools"]["value"]="CHECK TOTALS IN EXCEL"
    result=write_question(state(blackboard=bb,phase="review",history=[{"role":"assistant","content":summary}]))
    assert "Here’s my understanding" not in result["assistant_message"]


def test_real_correction_replaces_summary_once_then_confirms_without_repeating_it():
    from app.multi_agent_llm import write_question
    bb = recorded()["blackboard"]
    workflow.next_decision(bb, resolve_limits(None), 8)
    first = workflow.review_message(bb)
    bb["last_phase"] = "review"
    workflow.merge(bb, {"workflow_updates": [{"id": "task-1", "name": "Supplier invoice processing", "facts": {
        "active_effort": {"value": "60 minutes daily", "evidence": "60 minutes daily", "correction": True}}}]},
        state(user_message="Correction: 60 minutes daily", source_message_id=200))
    workflow.next_decision(bb, resolve_limits(None), 9)
    second = write_question(state(blackboard=bb, phase="review", history=[{"role":"assistant","content":first}]))["assistant_message"]
    assert "60 minutes daily" in second and "90 minutes" not in second
    workflow.merge(bb, {"workflow_updates": []}, state(blackboard=bb, user_message=LATEST_CONFIRMATION,
        history=[{"role":"assistant","content":second,"message_id":801}]))
    assert workflow.next_decision(bb, resolve_limits(None), 10)["should_close"]


@pytest.mark.parametrize("text", [
    "Invoices usually come in through email from vendors or other departments.",
    "They come in by email, and I check the supplier and purchase order.",
])
def test_already_explained_email_arrival_is_not_rejected_as_a_trigger(text):
    bb = recorded()["blackboard"]
    task = workflow.ledger(bb)["tasks"][0]
    task["facts"].pop("trigger_inputs")
    workflow.merge(bb, {"workflow_updates": [{"id":task["id"],"name":task["name"],"facts":{
        "trigger_inputs":{"value":"Invoices come in by email","evidence":text}}}]},state(user_message=text,source_message_id=201))
    assert "trigger_inputs" not in workflow.gaps(task)
    assert workflow.next_decision(bb, resolve_limits(None), 8)["phase"] == "review"


def test_checks_do_not_imply_an_exception_resolution_or_the_absence_of_bottlenecks():
    bb = recorded()["blackboard"]
    facts = workflow.ledger(bb)["tasks"][0]["facts"]
    facts.pop("exceptions");facts.pop("bottlenecks")
    bb["last_beat"] = {"task_id":"task-1","area":"Supplier invoice processing"}
    text = "I check the details and approvals, enter them into our accounting system, and process the payment."
    workflow.merge(bb, {"workflow_updates":[{"id":"task-1","name":"Supplier invoice processing","facts":{
        "steps_decisions":{"value":text,"evidence":text,"status":"known"},
        "exceptions":{"value":"Implied handling of incorrect details","evidence":text,"status":"known"},
        "bottlenecks":{"value":"No bottlenecks mentioned","evidence":text,"status":"not_applicable"}}}]},
        state(blackboard=bb,user_message=text,source_message_id=202))
    assert "exceptions" not in facts and "bottlenecks" not in facts
    beat = workflow.next_decision(bb, resolve_limits(None), 8)["beat"]
    assert "exceptions" in beat["fields"]
    assert "required approval" in workflow.fallback(beat)


def test_fix_mismatches_needs_a_targeted_resolution_followup_not_a_new_walkthrough():
    bb = recorded()["blackboard"]
    task = workflow.ledger(bb)["tasks"][0]
    task["facts"].pop("exceptions")
    task["facts"]["steps_decisions"]["value"] = "Compare figures, fix mismatches and prepare the summary"
    text = "I compare the figures, fix any mismatches, and prepare a summary of total expenses."
    workflow.merge(bb, {"workflow_updates":[{"id":"task-1","name":task["name"],"facts":{
        "exceptions":{"value":"Fix mismatches","evidence":text,"status":"known"}}}]},state(user_message=text,source_message_id=203))
    beat=workflow.next_decision(bb,resolve_limits(None),9)["beat"]
    assert beat["fields"] == ["exceptions"]
    assert "figures or records" in workflow.fallback(beat)


def test_missing_time_is_not_misclassified_as_an_employee_unavailable_estimate():
    bb=recorded()["blackboard"]
    task=workflow.ledger(bb)["tasks"][0]
    task["facts"].pop("active_effort")
    text="At the end of each month, I collect records and prepare a summary for the finance manager."
    workflow.merge(bb,{"workflow_updates":[{"id":"task-1","name":task["name"],"facts":{
        "active_effort":{"value":"Not specified","status":"unavailable","evidence":text}}}]},state(user_message=text,source_message_id=204))
    assert "active_effort" in workflow.gaps(task)
    assert "active_effort" in workflow.next_decision(bb,resolve_limits(None),8)["beat"]["fields"]
    text="I can't estimate how much active time it takes."
    workflow.merge(bb,{"workflow_updates":[{"id":"task-1","name":task["name"],"facts":{
        "active_effort":{"value":"Cannot estimate","status":"unavailable","evidence":text}}}]},state(user_message=text,source_message_id=205))
    assert "active_effort" not in workflow.gaps(task)
