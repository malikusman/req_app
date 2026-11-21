import copy
import json
import hashlib
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from app import employee_discovery_v2 as v2, multi_agent_graph
from app.llm import OpenAIUnavailable


def fact(text, source=1, status='REPORTED', **extra):
    return {'value': text if status == 'REPORTED' else None, 'fact_status': status,
            'quote': text, 'source_message_id': source, 'correction': False, **extra}


def activity(text='Review invoices', source=1, id=None, **extra):
    return {'id': id, 'description': fact(text, source), 'frequency': None, 'effort': None,
            'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': False, **extra}


def capture(**kwargs):
    return v2.Capture.model_validate({'activities': [], 'checks': [], 'invisible_work': [], 'shadow_ai': [], 'removed_activities': [], **kwargs})


def initial(**kwargs):
    return {'engine_version': 2, 'blackboard': {}, 'question_count': 0, 'history': [], 'user_message': 'Profile recap',
            'preferred_language': 'en', 'context_policy': {'stage_id': 'EMPLOYEE_DISCOVERY',
                'object_filters': {'company_id': 1, 'participant_id': 2, 'conversation_id': 3}}, **kwargs}


def reply(state, text, recorded, monkeypatch):
    state = copy.deepcopy(state)
    source = len([m for m in state['history'] if m['role'] == 'user']) + 1
    state.update(user_message=text, source_message_id=source)
    state['history'].append({'role': 'user', 'content': text, 'message_id': source})
    monkeypatch.setattr(v2, 'extract', lambda _: recorded(source))
    state = v2.discovery_graph.invoke(state)
    state['history'].append({'role': 'assistant', 'content': state['assistant_message']})
    return state


def covered_data():
    data = v2.initial()
    data['checks'] = {key: fact('No other work') for key in v2.CHECKS}
    data['work_items'] = [{'id': 'work-1', 'description': fact('Review invoices'), 'frequency': fact('daily'),
        'effort': fact('20 to 30 minutes', minimum=20., maximum=30., unit='minutes'),
        'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': False}]
    return data


def test_complete_four_phase_flow_including_invisible_work_and_readback(monkeypatch):
    state = v2.discovery_graph.invoke(initial())
    assert state['active_agent_id'] == 'anchor'
    assert 'last working day' in state['assistant_message']
    phases = ['anchor']
    for key in v2.CHECKS:
        text = 'Review invoices daily for 20 to 30 minutes' if key == 'anchor' else 'No other work' if key != 'OUTSIDE_SYSTEMS' else 'I also retype prices in Excel'
        def recorded(source, key=key, text=text):
            activities = []
            if key == 'anchor':
                activities = [activity(source=source, frequency=fact('daily', source),
                    effort=fact('20 to 30 minutes', source, minimum=20., maximum=30., unit='minutes'))]
            elif key == 'OUTSIDE_SYSTEMS':
                activities = [activity('retype prices in Excel', source)]
            return capture(activities=activities, checks=[{'name': key, 'fact': fact(text, source)}])
        state = reply(state, text, recorded, monkeypatch)
        phases.append(state['active_agent_id'])
    assert {'anchor', 'inventory', 'invisible_work', 'size_close'} <= set(phases)
    assert not state['completed']
    assert 'retype prices in Excel' in state['assistant_message']
    state = reply(state, 'Prices are weekly, 10 to 15 minutes', lambda source: capture(activities=[
        activity('retype prices in Excel', source, id='work-2', description=None,
                 frequency=fact('weekly', source), effort=fact('10 to 15 minutes', source, minimum=10., maximum=15., unit='minutes'))]), monkeypatch)
    assert 'Here is what I captured' in state['assistant_message']
    assert not state['completed']
    shown = state['blackboard']['employee_discovery_v2']['presented_summary']
    state = reply(state, 'Yes, that is correct', lambda _: pytest.fail('Confirmation should not call extractor'), monkeypatch)
    data = state['blackboard']['employee_discovery_v2']
    assert state['completed'] and data['outcome'] == 'successful'
    assert data['confirmation']['summary_sha256'] == hashlib.sha256(shown['text'].encode()).hexdigest()
    assert all(data['coverage'].values())
    assert data['invisible_work_signals'][0]['work_item_id'] == 'work-2'


def test_pause_and_resume_do_not_lose_state_or_call_provider(monkeypatch):
    state = v2.discovery_graph.invoke(initial())
    original = state['assistant_message']
    state = reply(state, 'pause', lambda _: pytest.fail('Pause cannot extract'), monkeypatch)
    assert state['blackboard']['employee_discovery_v2']['paused']
    assert not state['completed']
    state = reply(state, 'continue', lambda _: pytest.fail('Resume cannot extract'), monkeypatch)
    assert state['assistant_message'] == original
    assert not state['blackboard']['employee_discovery_v2']['paused']


def test_question_count_is_not_a_completion_condition():
    state = v2.discovery_graph.invoke(initial(question_count=99, limits={'max_questions': 1}))
    assert not state['completed'] and state['active_agent_id'] == 'anchor'


def test_invalid_evidence_and_invented_effort_are_rejected():
    state = initial(user_message='20 percent of my week', source_message_id=1)
    with pytest.raises(OpenAIUnavailable):
        v2._fact(fact('someone else said this'), state)
    with pytest.raises(OpenAIUnavailable):
        v2._fact(fact('20 percent of my week', minimum=20., maximum=20., unit='hours'), state)


def test_conflicts_are_retained_and_corrections_do_not_erase_evidence():
    old = fact('daily')
    changed = v2._merge_fact(old, fact('weekly', source=2))
    assert changed['fact_status'] == 'CONTRADICTED'
    assert changed['history'][0]['value'] == 'daily'
    fixed = v2._merge_fact(changed, fact('monthly', source=3, correction=True))
    assert fixed['fact_status'] == 'REPORTED' and len(fixed['history']) == 2


def test_readback_correction_invalidates_confirmation(monkeypatch):
    data = covered_data()
    state = v2.discovery_graph.invoke(initial(blackboard={'employee_discovery_v2': data}))
    assert state['blackboard']['employee_discovery_v2']['presented_summary']
    state = reply(state, 'Actually the invoices are weekly', lambda source: capture(activities=[
        activity(id='work-1', description=None, frequency=fact('weekly', source, correction=True))]), monkeypatch)
    updated = state['blackboard']['employee_discovery_v2']
    assert not state['completed'] and updated['revision'] == 1 and updated['confirmation'] is None
    assert 'weekly' in state['assistant_message']


def test_employee_can_withdraw_a_misattributed_activity_without_losing_history(monkeypatch):
    data = covered_data()
    state = v2.discovery_graph.invoke(initial(blackboard={'employee_discovery_v2': data},
        history=[{'role': 'user', 'content': 'Review invoices', 'message_id': 1}]))
    state = reply(state, 'Actually I do not review invoices; that is another role', lambda source: capture(
        removed_activities=[{'work_item_id': 'work-1', 'reason': fact('I do not review invoices', source)}]), monkeypatch)
    data = state['blackboard']['employee_discovery_v2']
    assert not data['work_items'] and len(data['retired_work_items']) == 1
    assert data['retired_work_items'][0]['description']['value'] == 'Review invoices'
    assert data['confirmation'] is None and not state['completed']


def test_readback_withdrawal_cannot_reassign_old_facts_to_the_new_message(monkeypatch):
    data = covered_data()
    original = copy.deepcopy(data['work_items'][0])
    report = copy.deepcopy(original)
    report.update(id='work-2', description=fact('Prepare weekly reports'))
    data['work_items'].append(report)
    state = v2.discovery_graph.invoke(initial(blackboard={'employee_discovery_v2': data}))
    text = 'I do not prepare weekly reports; another role does that activity'
    state = reply(state, text, lambda source: capture(
        activities=[activity(id='work-1', description=None,
            effort=fact(text, source, minimum=None, maximum=None, unit=None))],
        removed_activities=[{'work_item_id': 'work-2', 'reason': fact(text, source)}]), monkeypatch)
    data = state['blackboard']['employee_discovery_v2']
    assert data['work_items'] == [original]
    assert data['presented_summary'] and 'weekly reports' not in data['presented_summary']['text']


EVIDENCED = {'evidence': [{'message_id': 1, 'quote': 'I cannot estimate', 'source_hash': 'x'}]}


def test_explicit_unknown_estimate_allows_success_but_keeps_follow_up(monkeypatch):
    # Policy (approved): an employee's explicit "I cannot estimate" is an answer
    # (Doc 00 §10 "not estimable"); it completes sizing and keeps a follow-up.
    data = covered_data()
    data['work_items'][0]['effort'] = fact('I cannot estimate', status='UNKNOWN', minimum=None, maximum=None, unit=None, **EVIDENCED)
    state = v2.discovery_graph.invoke(initial(blackboard={'employee_discovery_v2': data}))
    assert state['blackboard']['employee_discovery_v2']['follow_up_requirements'][0]['reason'] == 'employee_reported_unknown'
    state = reply(state, 'Yes', lambda _: pytest.fail('No extraction'), monkeypatch)
    assert state['completed']
    assert state['blackboard']['employee_discovery_v2']['outcome'] == 'successful'


def test_unsupplied_or_unevidenced_estimates_still_block_success(monkeypatch):
    data = covered_data()
    data['work_items'][0]['effort'] = fact('I cannot estimate', status='UNKNOWN', minimum=None, maximum=None, unit=None)  # no evidence
    assert not v2.coverage(data)['sizing']
    data = covered_data()
    data['work_items'][0].pop('effort')
    data['deferred_fields'] = [{'work_item_id': 'work-1', 'field': 'effort', 'reason': 'employee_answer_not_established'}]
    state = v2.discovery_graph.invoke(initial(blackboard={'employee_discovery_v2': data}))
    state = reply(state, 'Yes', lambda _: pytest.fail('No extraction'), monkeypatch)
    assert state['completed'] and state['blackboard']['employee_discovery_v2']['outcome'] == 'needs_follow_up'


@pytest.mark.parametrize('extra', [{'memory_facts': [{'content': 'Peer said'}]}, {'context_policy': {}},
                                  {'blackboard': {'employee_discovery_v2': {**v2.initial(), 'role_profile': {'company_id': 99}}}},
                                  {'blackboard': {'employee_discovery_v2': {**v2.initial(), 'role_profile': {'company_id': 1, 'participant_id': 99, 'id': '3:role-profile-3'}}}}])
def test_context_firewall_fails_closed(extra):
    result = multi_agent_graph.execute_multi_agent_turn(initial(**extra))
    assert result['error'] == 'invalid_context_policy' and not result['retryable']


def test_arabic_readback_and_confirmation_keep_original_activity_language(monkeypatch):
    data = covered_data()
    data['work_items'][0]['description']['value'] = 'مراجعة الفواتير'
    state = v2.discovery_graph.invoke(initial(preferred_language='ar', blackboard={'employee_discovery_v2': data}))
    assert 'مراجعة الفواتير' in state['assistant_message']
    state = reply(state, 'نعم، هذا صحيح', lambda _: pytest.fail('No extraction'), monkeypatch)
    assert state['completed']


@pytest.mark.parametrize('phrase,low,high,unit', [('twenty five to thirty minutes',25.,30.,'minutes'),
    ('half an hour to an hour',.5,1.,'hours'), ('خمس إلى عشر دقائق',5.,10.,'minutes')])
def test_reported_ranges_can_use_spoken_number_words(phrase, low, high, unit):
    state = initial(user_message=phrase, source_message_id=1)
    value = v2._fact(fact(phrase, minimum=low, maximum=high, unit=unit), state)
    assert value['minimum'] == low and value['maximum'] == high


@pytest.mark.usefixtures('with_model')
def test_truncation_escalates_once_with_absolute_cap(monkeypatch):
    caps = []
    def model(state, cap, schema):
        caps.append(cap)
        return Mock(invoke=Mock(return_value=SimpleNamespace(content='{}', response_metadata={'finish_reason': 'length'})))
    monkeypatch.setattr(v2, '_recording_model', model)
    state = initial(blackboard={'employee_discovery_v2': v2.initial()})
    with pytest.raises(OpenAIUnavailable) as caught:
        v2.extract(state)
    assert caps == [6000, 12000]
    assert caught.value.code == 'structured_output_truncated' and not caught.value.retryable


@pytest.mark.usefixtures('with_model')
def test_invalid_structure_repairs_once_then_holds_saved_answer(monkeypatch):
    model = Mock(invoke=Mock(return_value=SimpleNamespace(content='{}', response_metadata={})))
    monkeypatch.setattr(v2, '_recording_model', lambda *args: model)
    with pytest.raises(OpenAIUnavailable) as caught:
        v2.extract(initial(blackboard={'employee_discovery_v2': v2.initial()}))
    assert model.invoke.call_count == 2
    assert caught.value.code == 'invalid_discovery_capture'


@pytest.mark.usefixtures('with_model')
def test_nonverbatim_evidence_gets_one_different_repair_request(monkeypatch):
    bad = capture(activities=[activity('Retype prices')]).model_dump()
    bad['activities'][0]['description']['quote'] = 'I retype prices'
    good = capture(activities=[activity('Retype prices')]).model_dump()
    model = Mock(invoke=Mock(side_effect=[SimpleNamespace(content=json.dumps(bad), response_metadata={}),
        SimpleNamespace(content=json.dumps(good), response_metadata={})]))
    monkeypatch.setattr(v2, '_recording_model', lambda *args: model)
    state = initial(blackboard={'employee_discovery_v2': v2.initial()}, user_message='Retype prices weekly', source_message_id=1)
    result = v2.extract(state)
    assert result.activities[0].description.quote == 'Retype prices'
    assert model.invoke.call_count == 2
    assert 'EXACT substring' in model.invoke.call_args.args[0][-1].content


def test_unanswered_capture_does_not_spin_dead_end_or_fabricate_completion(monkeypatch):
    # B1/B4: two vague non-answers no longer fail the turn (which stranded the
    # employee). The check is deferred as an open follow-up; it is NOT recorded
    # as covered, and the interview cannot report successful coverage.
    state = v2.discovery_graph.invoke(initial())
    for _ in range(2):
        state = reply(state, 'ok', lambda _: capture(), monkeypatch)
        assert not state['completed']
    data = state['blackboard']['employee_discovery_v2']
    assert 'anchor' not in data['checks'] and 'anchor' in data['deferred_checks']
    assert data['last_check'] == 'weekly' and not v2.coverage(data)['regular_work']
    assert any(r.get('check') == 'anchor' for r in data['follow_up_requirements'])


def test_handover_number_grounding_never_accepts_canonical_metadata_as_employee_effort():
    from app import package
    data = covered_data()
    data['canonical_work_items'] = [{'id': '777:work-1', 'company_id': 777, 'version': 999,
        'description': 'Review invoices', 'frequency': 'daily', 'effort_range_min': 20., 'effort_range_max': 30., 'effort_unit': 'minutes'}]
    evidence = package._evidence({'blackboard': {'employee_discovery_v2': data}})
    grounded = package._evidence_text(evidence)
    assert '20 to 30 minutes' in grounded
    assert '777' not in grounded and '999' not in grounded


def recruitment_state():
    data = covered_data()
    data['work_items'][0]['description'] = fact('Checking emails and responding to employee queries')
    data['work_items'][0]['frequency'] = {**fact('several times a day'), 'fact_status': 'CONTRADICTED', 'history': [fact('daily')]}
    for id, name in [('work-2', 'Reviewing attendance records'),
                     ('work-11', 'Coordinating recruitment activities with hiring managers weekly'),
                     ('work-24', 'Using WhatsApp to follow up with managers about recruitment approvals and missing employee documents')]:
        data['work_items'].append({'id': id, 'description': fact(name), 'frequency': fact('weekly'),
            'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': False})
    data.update(last_item='work-1', last_check=None, last_clarification={'item': 'work-1', 'field': 'frequency'},
        last_question='When you coordinate recruitment activities weekly, how much time do you typically spend on those tasks during the week?',
        phase='size_close', attempts={'work-1': 2})
    return initial(blackboard={'employee_discovery_v2': data}, question_count=14)


RECRUITMENT_ANSWER = ('I usually spend around 4–6 hours per week actively coordinating recruitment activities, '
    'including scheduling interviews, following up with hiring managers, and updating the recruitment tracker. '
    'This excludes time spent waiting for responses.')


def test_weekly_recruitment_answer_survives_stale_question_scope_and_old_stall_counter(monkeypatch):
    state = recruitment_state()
    original = copy.deepcopy(state['blackboard']['employee_discovery_v2'])
    state = reply(state, RECRUITMENT_ANSWER, lambda source: capture(activities=[activity(id='work-11', description=None,
        effort=fact('4–6 hours per week', source, minimum=4., maximum=6., unit='hours'))]), monkeypatch)
    data = state['blackboard']['employee_discovery_v2']
    recruitment = next(w for w in data['work_items'] if w['id'] == 'work-11')
    whatsapp = next(w for w in data['work_items'] if w['id'] == 'work-24')
    assert recruitment['effort']['minimum'] == 4 and recruitment['effort']['maximum'] == 6
    assert recruitment['effort']['basis'] == 'per_week'
    assert 'effort' not in whatsapp
    assert data['work_items'][0]['frequency']['fact_status'] == 'REPORTED'
    assert data['work_items'][0]['frequency']['history'] == original['work_items'][0]['frequency']['history']
    assert data['attempts']['work-1'] == 0 and not state['completed']
    assert data['last_sizing_batch'][0]['item'] == 'work-2' and 'attendance' in state['assistant_message']


@pytest.mark.parametrize('old,new,status', [('daily', 'several times a day', 'REPORTED'),
    ('weekly', 'twice a week', 'REPORTED'), ('daily', 'weekly', 'CONTRADICTED'),
    ('once a day', 'three times a day', 'CONTRADICTED'), ('daily', 'not daily', 'CONTRADICTED')])
def test_frequency_detail_is_not_automatically_a_contradiction(old, new, status):
    value = v2._merge_fact(fact(old), fact(new, source=2), field='frequency')
    assert value['fact_status'] == status and value['history'][0]['value'] == old


@pytest.mark.usefixtures('with_model')
@pytest.mark.parametrize('question', [
    'Do you coordinate recruitment activities with hiring managers each week?',
    'How much working time do you spend checking emails and responding to employee queries each week?'])
def test_question_writer_cannot_change_bound_activity_or_clarification_field(monkeypatch, question):
    state = recruitment_state()
    state['v2_plan'] = {'phase': 'size_close', 'item': 'work-1', 'field': 'frequency', 'clarify': True}
    model = Mock(invoke=Mock(return_value=SimpleNamespace(content=question, response_metadata={})))
    monkeypatch.setattr(v2, 'build_chat_openai', lambda **kwargs: model)
    output = v2.talk(state)
    assert 'Checking emails' in output['assistant_message'] and 'frequency' in output['assistant_message']
    assert 'recruitment' not in output['assistant_message'].lower()
    # C2: clarification wording is deterministic and shows both conflicting values,
    # so the question writer cannot turn it into a different (unanswerable) question.
    assert '“daily”' in output['assistant_message'] and '“several times a day”' in output['assistant_message']
    assert model.invoke.call_count == 0


def test_real_frequency_conflict_still_requires_clarification():
    state = recruitment_state()
    state['blackboard']['employee_discovery_v2']['work_items'][0]['frequency']['history'] = [fact('weekly')]
    prepared = v2.prepare(state)
    assert prepared['v2_plan']['clarify'] and prepared['v2_plan']['field'] == 'frequency'


def test_readback_distinguishes_weekly_total_from_each_occurrence():
    data = covered_data()
    data['work_items'][0]['effort'] = {**fact('4–6 hours per week'), 'minimum': 4., 'maximum': 6., 'unit': 'hours', 'basis': 'per_week'}
    assert '4–6 hours per week' in v2.summary(data, 'en')
    assert v2._effort_basis('Each session takes 15–30 minutes') == 'per_occurrence'


def test_normalizing_the_same_saved_weekly_estimate_is_not_a_new_conflicting_claim():
    old = {**fact('4–6 hours per week'), 'minimum': None, 'maximum': None, 'unit': None, 'basis': 'per_week'}
    new = {**fact('4–6 hours per week'), 'minimum': 4., 'maximum': 6., 'unit': 'hours', 'basis': 'per_week'}
    normalized = v2._merge_fact(old, new, field='effort')
    assert normalized['fact_status'] == 'REPORTED' and normalized['minimum'] == 4
    assert normalized['history'][0] == old
    different = {**new, 'value': '8–10 hours per week', 'minimum': 8., 'maximum': 10., 'source_message_id': 2}
    assert v2._merge_fact(new, different, field='effort')['fact_status'] == 'CONTRADICTED'


def sizing_state(item_id='work-2', answer='2 3 hrs'):
    state = recruitment_state()
    data = state['blackboard']['employee_discovery_v2']
    data.update(last_item=item_id, last_clarification=None, attempts={item_id: 2})
    target = next(w for w in data['work_items'] if w['id'] == item_id)
    data['last_question'] = f"For {target['description']['value']}, how much working time does each occurrence take?"
    state.update(source_message_id=99, user_message=answer,
        history=[{'role': 'user', 'content': answer, 'message_id': 99}])
    return state


@pytest.mark.usefixtures('with_model')
@pytest.mark.parametrize('item_id', ['work-2', 'work-11', 'work-24'])
@pytest.mark.parametrize('answer,low,high,unit,basis', [
    ('2 3 hrs', 2, 3, 'hours', None), ('2-3 hours', 2, 3, 'hours', None),
    ('15 to 30 minutes', 15, 30, 'minutes', None), ('4-6 hours per week', 4, 6, 'hours', 'per_week')])
def test_bound_effort_formats_preserve_activity_units_evidence_and_progress(monkeypatch, item_id, answer, low, high, unit, basis):
    state = sizing_state(item_id, answer)
    old = copy.deepcopy(state['blackboard']['employee_discovery_v2']['work_items'])
    monkeypatch.setattr(v2, '_recording_model', lambda *args: pytest.fail('Explicit duration needs no model extraction'))
    state = v2.record(state)
    data = state['blackboard']['employee_discovery_v2']
    item = next(w for w in data['work_items'] if w['id'] == item_id)
    assert item['effort']['minimum'] == low and item['effort']['maximum'] == high
    assert item['effort']['unit'] == unit and item['effort']['basis'] == basis
    assert item['effort']['evidence'][0]['message_id'] == 99 and item['effort']['quote'] == answer
    assert item['description'] == next(w for w in old if w['id'] == item_id)['description']
    assert [w for w in data['work_items'] if w['id'] != item_id] == [w for w in old if w['id'] != item_id]
    assert data['attempts'][item_id] == 0


@pytest.mark.usefixtures('with_model')
@pytest.mark.parametrize('answer', ['2 hours or 3 minutes', '2-3 hours attendance; 4-6 hours recruitment', '20%', '3-2 hours'])
def test_ambiguous_effort_is_not_guessed_by_numeric_parser(answer):
    assert v2._bound_effort_capture(sizing_state(answer=answer)) is None


@pytest.mark.parametrize('question,clarification', [
    ('How often do you review attendance records?', None),
    ('How much working time does recruitment coordination take?', None),
    ('Which frequency should I keep?', {'item': 'work-2', 'field': 'frequency'})])
def test_numeric_effort_never_uses_a_different_activity_or_frequency_question(question, clarification):
    state = sizing_state()
    state['blackboard']['employee_discovery_v2'].update(last_question=question, last_clarification=clarification)
    assert v2._bound_effort_capture(state) is None


@pytest.mark.usefixtures('with_model')
def test_copied_unchanged_context_does_not_poison_valid_effort_or_reattribute_history(monkeypatch):
    text = 'Reviewing attendance records takes 15 to 30 minutes.'
    state = sizing_state(answer=text)
    original = copy.deepcopy(state['blackboard']['employee_discovery_v2']['work_items'][1])
    # Real-provider failure pattern: correct effort alongside copied old fields
    # with invented message ID 0. Only the unchanged context is discarded.
    response = capture(activities=[activity(id='work-2',
        description=fact('Reviewing attendance records', 0), frequency=fact('weekly', 0),
        effort=fact(text, 99, minimum=15., maximum=30., unit='minutes'))])
    model = Mock(invoke=Mock(return_value=SimpleNamespace(content=response.model_dump_json(), response_metadata={})))
    monkeypatch.setattr(v2, '_recording_model', lambda *args: model)
    state = v2.record(state)
    item = state['blackboard']['employee_discovery_v2']['work_items'][1]
    assert model.invoke.call_count <= 1  # The bound duration is now read deterministically.
    assert item['description'] == original['description'] and item['frequency'] == original['frequency']
    assert item['effort']['maximum'] == 30 and item['effort']['evidence'][0]['message_id'] == 99


@pytest.mark.usefixtures('with_model')
def test_new_unsupported_facts_are_rejected_individually_after_one_repair(monkeypatch):
    # B1: the invented frequency (cited to message 0) is still rejected, but the
    # valid effort in the same answer is kept instead of failing the whole turn.
    state = sizing_state(answer='Reviewing attendance records takes about three hours, I think.')
    state['blackboard']['employee_discovery_v2']['last_question'] = 'Tell me more about attendance.'
    response = capture(activities=[activity(id='work-2', description=None, frequency=fact('monthly', 0),
        effort=fact(state['user_message'], 99, minimum=180., maximum=180., unit='minutes'))])
    model = Mock(invoke=Mock(return_value=SimpleNamespace(content=response.model_dump_json(), response_metadata={})))
    monkeypatch.setattr(v2, '_recording_model', lambda *args: model)
    state = v2.record(state)
    data = state['blackboard']['employee_discovery_v2']
    item = next(w for w in data['work_items'] if w['id'] == 'work-2')
    assert model.invoke.call_count == 2 and 'Some facts failed validation' in model.invoke.call_args.args[0][-1].content
    assert item['frequency']['value'] == 'weekly'  # Unchanged; 'monthly' was never accepted.
    # Converted minutes are replaced by the duration as said.
    assert (item['effort']['minimum'], item['effort']['maximum'], item['effort']['unit']) == (3, 3, 'hours')
    assert any(r['field'] == 'frequency' and r['work_item_id'] == 'work-2' for r in data['rejected_extractions'])


def test_same_effort_in_different_words_preserves_history_without_false_conflict():
    old = fact('2-3 hours', minimum=2., maximum=3., unit='hours', basis=None)
    new = fact('2 3 hrs', 2, minimum=2., maximum=3., unit='hours', basis=None)
    merged = v2._merge_fact(old, new, field='effort')
    assert merged['fact_status'] == 'REPORTED' and merged['history'] == [old]
    weekly = {**new, 'basis': 'per_week'}
    assert v2._merge_fact(old, weekly, field='effort')['fact_status'] == 'CONTRADICTED'


def test_multiple_consecutive_sizing_answers_advance_without_losing_other_activities(monkeypatch):
    monkeypatch.setattr(v2, '_recording_model', lambda *args: pytest.fail('Explicit numeric answers must not call a live model'))
    state = sizing_state()
    data = state['blackboard']['employee_discovery_v2']
    # Recruitment has already been sized; attendance and WhatsApp remain.
    next(w for w in data['work_items'] if w['id'] == 'work-11')['effort'] = fact('4-6 hours per week', minimum=4., maximum=6., unit='hours', basis='per_week')
    for source, answer, target in [(99, '2 3 hrs', 'work-2'), (100, '15 to 30 minutes', 'work-24')]:
        monkeypatch.setattr(v2, 'llm_configured', lambda: True)
        state.update(source_message_id=source, user_message=answer)
        state['history'].append({'role': 'user', 'content': answer, 'message_id': source})
        state = v2.record(state)
        data = state['blackboard']['employee_discovery_v2']
        assert next(w for w in data['work_items'] if w['id'] == target)['effort']['fact_status'] == 'REPORTED'
        state = v2.prepare(state)
        monkeypatch.setattr(v2, 'llm_configured', lambda: False)
        state = v2.talk(state)
        assert state['question_count'] == 15 + source - 99
    assert state['v2_plan']['review'] and data['presented_summary']
    assert len(data['work_items']) == 4 and not state['completed']


def overlap_data():
    data = covered_data()
    parent = data['work_items'][0]
    parent.update(description=fact('Recruitment coordination'), frequency=fact('weekly'),
        effort=fact('4–6 hours per week', minimum=4., maximum=6., unit='hours', basis='per_week'))
    for id, name in [('work-2', 'Scheduling candidate interviews'), ('work-3', 'Following up with hiring managers'),
                     ('work-4', 'Updating recruitment tracker')]:
        data['work_items'].append({'id': id, 'description': fact(name), 'frequency': fact('as needed'),
            'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': False})
    return data


def inclusions(text, source, children=('work-2', 'work-3', 'work-4'), parent='work-1'):
    return [{'work_item_ids': list(children), 'included_in_work_item_id': parent, 'reason': fact(text, source)}]


OVERLAP_ANSWER = ('Those 4–6 hours per week for recruitment coordination include scheduling candidate interviews, '
    'following up with hiring managers, and updating the recruitment tracker. I do not track separate time for them.')


def test_explicit_group_effort_moves_to_readback_then_confirmation_without_repeating_subtasks(monkeypatch):
    data = overlap_data()
    original = copy.deepcopy(data['work_items'])
    state = v2.discovery_graph.invoke(initial(blackboard={'employee_discovery_v2': data}))
    assert state['blackboard']['employee_discovery_v2']['last_item'] == 'work-2'
    for _ in range(2):
        state = reply(state, OVERLAP_ANSWER, lambda source: capture(effort_inclusions=inclusions(OVERLAP_ANSWER, source)), monkeypatch)
        current = state['blackboard']['employee_discovery_v2']
        assert current['last_item'] is None and current['coverage']['sizing']
        assert 'not counted separately' in state['assistant_message']
        assert state['assistant_message'].count('4–6 hours per week') == 1
        assert len(current['work_items']) == len(original)
        assert [w['description'] for w in current['work_items']] == [w['description'] for w in original]
        assert not state['completed']
    state = reply(state, 'Yes, correct', lambda _: pytest.fail('Confirmation must not extract'), monkeypatch)
    assert state['completed'] and state['blackboard']['employee_discovery_v2']['outcome'] == 'successful'


def test_similar_activity_names_are_still_distinct_without_reported_inclusion():
    data = overlap_data()
    state = v2.prepare(initial(blackboard={'employee_discovery_v2': data}))
    assert state['v2_plan']['item'] == 'work-2' and state['v2_plan']['missing'] == ['effort']
    assert not v2.coverage(data)['sizing']


@pytest.mark.parametrize('quote', ['I also schedule interviews for recruitment', 'Interview effort is not included in recruitment coordination',
    'Interview effort is separate from recruitment coordination'])
def test_effort_overlap_requires_affirmative_employee_evidence(quote):
    state = initial(user_message=quote, source_message_id=1, blackboard={'employee_discovery_v2': overlap_data()})
    data, rejected = state['blackboard']['employee_discovery_v2'], []
    v2.merge(data, capture(effort_inclusions=inclusions(quote, 1, children=('work-2',))), state, rejected)
    assert not any(w.get('effort_inclusion') for w in data['work_items'])
    assert rejected and rejected[0]['field'] == 'effort_inclusion'


@pytest.mark.parametrize('parent', ['work-2', 'work-999'])
def test_invalid_or_self_referencing_effort_inclusion_is_rejected(parent):
    state = initial(user_message=OVERLAP_ANSWER, source_message_id=1)
    data, rejected = overlap_data(), []
    v2.merge(data, capture(effort_inclusions=inclusions(OVERLAP_ANSWER, 1, children=('work-2',), parent=parent)), state, rejected)
    assert not any(w.get('effort_inclusion') for w in data['work_items']) and rejected


def test_cyclic_inclusions_cannot_satisfy_coverage():
    data = overlap_data()
    data['work_items'][0]['effort_inclusion'] = fact('work-2')
    data['work_items'][1]['effort_inclusion'] = fact('work-1')
    assert not v2.coverage(data)['sizing']
    with pytest.raises(OpenAIUnavailable):
        v2._validate_inclusions(data)


def test_unknown_group_effort_is_not_repeated_and_counts_children_once(monkeypatch):
    data = overlap_data()
    data['work_items'][0]['effort'] = fact('I cannot estimate', status='UNKNOWN', minimum=None, maximum=None, unit=None, **EVIDENCED)
    for item in data['work_items'][1:]:
        item['effort_inclusion'] = {**fact('work-1'), 'quote': OVERLAP_ANSWER}
    state = v2.discovery_graph.invoke(initial(blackboard={'employee_discovery_v2': data}))
    data = state['blackboard']['employee_discovery_v2']
    assert state['v2_plan']['review'] and data['coverage']['sizing']
    # One follow-up for the group; the included children are not separately unknown.
    assert [r['work_item_id'] for r in data['follow_up_requirements']] == ['work-1']
    state = reply(state, 'Yes', lambda _: pytest.fail('Confirmed unknown effort needs no repeat'), monkeypatch)
    assert state['completed'] and state['blackboard']['employee_discovery_v2']['outcome'] == 'successful'


def test_inclusion_retains_previous_independent_estimate_but_readback_does_not_add_it():
    data = overlap_data()
    child = data['work_items'][1]
    child['effort'] = fact('1–2 hours', minimum=1., maximum=2., unit='hours')
    original = copy.deepcopy(child['effort'])
    text = OVERLAP_ANSWER
    v2.merge(data, capture(effort_inclusions=inclusions(text, 1)), initial(user_message=text, source_message_id=1))
    assert child['effort'] == original
    assert '1–2 hours' not in v2.summary(data, 'en')
    assert 'not counted separately' in v2.summary(data, 'en')


def test_breakdown_question_with_hours_in_context_is_not_an_effort_question():
    data = overlap_data()
    assert not v2._question_matches_plan('Besides scheduling candidate interviews, what other recruitment tasks happen during those 4–6 hours per week?',
        {'item': 'work-2', 'missing': ['effort']}, data, 'en')


def test_package_marks_included_effort_as_non_additive():
    from app import package
    data = overlap_data()
    data['canonical_work_items'] = [
        {'id': '3:work-1', 'description': 'Recruitment coordination'},
        {'id': '3:work-2', 'description': 'Scheduling candidate interviews', 'effort_included_in_work_item_id': '3:work-1'}]
    evidence = package._evidence({'blackboard': {'employee_discovery_v2': data}})
    assert 'not additional effort' in evidence['learned'][1]['detail']
    assert '4–6' not in evidence['learned'][1]['detail']


def scope_data():
    data = overlap_data()
    data['work_items'] = data['work_items'][:2]
    data['work_items'][0]['description'] = fact('Coordinating recruitment activities with hiring managers')
    data['work_items'][1]['description'] = fact('Following up with department managers regarding pending recruitment approvals')
    return data


def test_possible_overlap_asks_scope_once_instead_of_demanding_a_separate_range(monkeypatch):
    state = v2.discovery_graph.invoke(initial(blackboard={'employee_discovery_v2': scope_data()}))
    assert state['v2_plan']['overlap_candidate'] == 'work-1'
    assert 'already included' in state['assistant_message'] and 'as a range' not in state['assistant_message']
    question = state['assistant_message']
    state.update(user_message='Yes', source_message_id=7)
    state['history'].append({'role': 'user', 'content': 'Yes', 'message_id': 7})
    monkeypatch.setattr(v2, 'llm_configured', lambda: True)
    monkeypatch.setattr(v2, '_recording_model', lambda *args: pytest.fail('Bound yes needs no extraction model'))
    state = v2.record(state)
    state = v2.prepare(state)
    assert state['v2_plan']['review']
    link = state['blackboard']['employee_discovery_v2']['work_items'][1]['effort_inclusion']
    assert link['quote'] == 'Yes' and link['scope_question'] == question
    assert state['blackboard']['employee_discovery_v2']['work_items'][1].get('effort') is None


def test_denied_overlap_is_preserved_and_not_asked_again(monkeypatch):
    state = v2.discovery_graph.invoke(initial(blackboard={'employee_discovery_v2': scope_data()}))
    state.update(user_message='No', source_message_id=7)
    state['history'].append({'role': 'user', 'content': 'No', 'message_id': 7})
    state = v2.record(state)
    state = v2.prepare(state)
    assert 'overlap_candidate' not in state['v2_plan']
    assert state['v2_plan']['missing'] == ['effort']
    state = v2.talk(state)
    assert 'as a range' in state['assistant_message']
    child = state['blackboard']['employee_discovery_v2']['work_items'][1]
    assert child['effort_scope_checked']['quote'] == 'No' and 'effort_inclusion' not in child
    state.update(user_message='2-3 hours', source_message_id=8)
    state['history'].append({'role': 'user', 'content': '2-3 hours', 'message_id': 8})
    monkeypatch.setattr(v2, 'llm_configured', lambda: True)
    state = v2.record(state)
    assert v2.prepare(state)['v2_plan']['review']


def test_parent_echo_in_reported_group_never_creates_a_self_link():
    data = overlap_data()
    v2.merge(data, capture(effort_inclusions=inclusions(OVERLAP_ANSWER, 1, children=('work-1', 'work-2'))),
        initial(user_message=OVERLAP_ANSWER, source_message_id=1))
    assert 'effort_inclusion' not in data['work_items'][0]
    assert data['work_items'][1]['effort_inclusion']['value'] == 'work-1'


def test_inclusion_delta_does_not_turn_legacy_null_range_wording_into_a_false_conflict():
    data = overlap_data()
    old = {**fact('included in 4–6 hours per week'), 'minimum': None, 'maximum': None, 'unit': 'hours', 'basis': 'per_week'}
    data['work_items'][1]['effort'] = copy.deepcopy(old)
    changed_words = fact(OVERLAP_ANSWER, minimum=None, maximum=None, unit=None)
    v2.merge(data, capture(activities=[activity(id='work-2', description=None, effort=changed_words)],
        effort_inclusions=inclusions(OVERLAP_ANSWER, 1)),
        initial(user_message=OVERLAP_ANSWER, source_message_id=1, blackboard={'employee_discovery_v2': data}))
    assert data['work_items'][1]['effort'] == old
    assert data['work_items'][1]['effort_inclusion']['fact_status'] == 'REPORTED'
