"""Focused planner tests; no live provider, database or interview submissions."""
import copy

import pytest

from app import employee_discovery_v2 as v2
from app.llm import OpenAIUnavailable
from test_employee_discovery_v2 import initial, covered_data, fact, activity, capture, overlap_data


def pending_state(count, question_count=10):
    data = covered_data()
    template = data['work_items'][0]
    data['work_items'] = [{**copy.deepcopy(template), 'id': f'work-{i}',
        'description': fact(f'Activity {i}'), 'effort': None} for i in range(1, count + 1)]
    # Absent fields, rather than an explicit UNKNOWN, are genuinely missing.
    for item in data['work_items']:
        item.pop('effort')
    return initial(blackboard={'employee_discovery_v2': data}, question_count=question_count)


def answer(state, text):
    state = copy.deepcopy(state)
    source = 100 + len(state['history'])
    state.update(user_message=text, source_message_id=source)
    state['history'].append({'role': 'user', 'content': text, 'message_id': source})
    return v2.discovery_graph.invoke(state)


@pytest.fixture
def deterministic(monkeypatch):
    monkeypatch.setattr(v2, 'llm_configured', lambda: True)
    monkeypatch.setattr(v2, '_recording_model', lambda *args: pytest.fail('Explicit sizing rows need no provider'))
    monkeypatch.setattr(v2, 'build_chat_openai', lambda **kwargs: pytest.fail('Batch labels must not be rewritten'))


def test_24_independent_estimates_fit_soft_target_and_still_require_readback_confirmation(deterministic):
    state = v2.discovery_graph.invoke(pending_state(24))
    questions = []
    while not state['blackboard']['employee_discovery_v2'].get('presented_summary'):
        questions.append(state['assistant_message'])
        batch = state['blackboard']['employee_discovery_v2']['last_sizing_batch']
        assert 1 < len(batch) <= 6
        state = answer(state, '\n'.join(f'{i}. 15 to 30 minutes' for i in range(1, len(batch) + 1)))
    assert len(questions) == 4 and len(set(questions)) == 4
    assert state['question_count'] == 15 and not state['completed']
    assert all(state['blackboard']['employee_discovery_v2']['coverage'].values())
    assert len(state['blackboard']['employee_discovery_v2']['work_items']) == 24
    state = answer(state, 'Yes, correct')
    assert state['completed'] and state['question_count'] == 15
    assert state['blackboard']['employee_discovery_v2']['outcome'] == 'successful'


def test_partial_answers_stay_missing_and_next_question_prioritizes_unasked_work(deterministic):
    state = v2.discovery_graph.invoke(pending_state(8))
    previous = state['blackboard']['employee_discovery_v2']['last_sizing_batch']
    state = answer(state, '1. 2 3 hrs')
    data = state['blackboard']['employee_discovery_v2']
    assert data['work_items'][0]['effort']['minimum'] == 2
    assert 'effort' not in data['work_items'][1] and 'effort' not in data['work_items'][2]
    assert not data['follow_up_requirements'] and not data['coverage']['sizing']
    assert not ({row['item'] for row in previous} & {row['item'] for row in data['last_sizing_batch']})


def test_confirmed_overlap_and_known_fields_are_reused_while_reported_overhead_is_prioritized():
    data = overlap_data()
    for child in data['work_items'][1:]:
        child['effort_inclusion'] = {**fact('work-1'), 'quote': 'This effort is included in recruitment coordination'}
    extras = pending_state(3)['blackboard']['employee_discovery_v2']['work_items']
    for i, item in enumerate(extras, 5):
        item['id'] = f'work-{i}'
    data['work_items'].extend(extras)
    data['invisible_work_signals'] = [{'work_item_id': 'work-7', 'probe_type': 'DUPLICATE_ENTRY', 'detail': fact('Manual entry')}]
    plan = v2.prepare(initial(blackboard={'employee_discovery_v2': data}, question_count=12))['v2_plan']
    assert [row['item'] for row in plan['batch']] == ['work-7', 'work-5', 'work-6']
    assert all(row['missing'] == ['effort'] for row in plan['batch'])
    assert data['work_items'][0]['effort']['basis'] == 'per_week'


@pytest.mark.parametrize('text', ['I cannot estimate any of these', 'I cannot estimate', 'unknown'])
def test_unknown_batch_gets_followup_and_readback_without_repeat(deterministic, text):
    state = v2.discovery_graph.invoke(pending_state(3, question_count=20))
    assert state['question_count'] == 21 and not state['completed'] # No cutoff at 15.
    state = answer(state, text)
    data = state['blackboard']['employee_discovery_v2']
    assert data['presented_summary'] and not data['last_sizing_batch']
    assert len(data['follow_up_requirements']) == 3 and data['coverage']['sizing']
    assert all(w['effort']['fact_status'] == 'UNKNOWN' and w['effort']['minimum'] is None for w in data['work_items'])
    assert all(r['evidence'] for r in data['follow_up_requirements'])
    state = answer(state, 'Yes')
    # Explicit unknowns are answers: success, with every follow-up still recorded.
    assert state['completed'] and state['blackboard']['employee_discovery_v2']['outcome'] == 'successful'
    assert len(state['blackboard']['employee_discovery_v2']['follow_up_requirements']) == 3


def test_soft_target_never_skips_inventory_or_pads_a_covered_interview():
    state = pending_state(2, question_count=20)
    del state['blackboard']['employee_discovery_v2']['checks']['weekly']
    assert v2.prepare(state)['v2_plan']['check'] == 'weekly'
    covered = initial(blackboard={'employee_discovery_v2': covered_data()}, question_count=3)
    assert v2.prepare(covered)['v2_plan']['review']


def test_unresolved_contradiction_takes_priority_over_minor_estimates_even_after_turn_15():
    state = pending_state(2, question_count=21)
    item = state['blackboard']['employee_discovery_v2']['work_items'][1]
    item['frequency'] = {**item['frequency'], 'fact_status': 'CONTRADICTED', 'history': [fact('weekly')]}
    prepared = v2.prepare(state)
    assert prepared['v2_plan'] == {'phase': 'size_close', 'item': 'work-2', 'field': 'frequency', 'clarify': True}
    assert prepared['blackboard']['employee_discovery_v2']['completion_plan']['remaining_sizing_items'] == 2


def test_reworded_activity_label_is_never_put_to_the_employee_as_a_conflict():
    # Live run: the recorder re-labelled an activity and the employee was asked to
    # choose between two labels. Labels are not employee claims to adjudicate.
    state = pending_state(2, question_count=12)
    state['blackboard']['employee_discovery_v2']['work_items'][1]['description']['fact_status'] = 'CONTRADICTED'
    assert not v2.prepare(state)['v2_plan'].get('clarify')


@pytest.mark.parametrize('wrong_item,minimum,maximum,quote', [
    ('work-2', 15., 30., '1. 15 to 30 minutes'), # Wrong row.
    ('work-2', 2., 6., '2. 4-6 hours per week')]) # Row index is not reported effort.
def test_batch_evidence_cannot_cross_activities_or_use_row_numbers_as_estimates(wrong_item, minimum, maximum, quote):
    data = pending_state(2)['blackboard']['employee_discovery_v2']
    data.update(last_sizing_batch=[{'item': 'work-1', 'missing': ['effort']}, {'item': 'work-2', 'missing': ['effort']}], last_question='Saved sizing list')
    text = '1. 15 to 30 minutes\n2. 4-6 hours per week'
    state = initial(blackboard={'employee_discovery_v2': data}, user_message=text, source_message_id=9)
    delta = activity(id=wrong_item, description=None, effort=fact(quote, 9, minimum=minimum, maximum=maximum,
        unit='minutes' if minimum == 15 else 'hours'))
    rejected = []
    v2.merge(data, capture(activities=[delta]), state, rejected)
    item = next(w for w in data['work_items'] if w['id'] == wrong_item)
    if quote.startswith('1.'):
        # Row 1's estimate cited for work-2: rejected, not attributed to the wrong row.
        assert 'effort' not in item and rejected
    else:
        # The row number is never the estimate: the range comes from the words said.
        assert (item['effort']['minimum'], item['effort']['maximum'], item['effort']['basis']) == (4., 6., 'per_week')


def test_explicit_single_unknown_is_kept_instead_of_requested_again(deterministic):
    state = pending_state(1, question_count=14)
    data = state['blackboard']['employee_discovery_v2']
    data.update(phase='size_close', last_item='work-1', last_question='For Activity 1, how much working time does each occurrence take?')
    data['work_items'][0]['effort'] = fact('time varies', minimum=None, maximum=None, unit=None)
    state = answer(state, 'I cannot estimate')
    assert state['v2_plan']['review']
    assert state['blackboard']['employee_discovery_v2']['follow_up_requirements'][0]['field'] == 'effort'
    assert state['blackboard']['employee_discovery_v2']['work_items'][0]['effort']['history'][0]['value'] == 'time varies'


def test_partial_unknown_phrase_cannot_be_copied_to_another_batch_activity():
    data = pending_state(2)['blackboard']['employee_discovery_v2']
    data.update(last_sizing_batch=[{'item': 'work-1', 'missing': ['effort']}, {'item': 'work-2', 'missing': ['effort']}], last_question='Saved sizing list')
    text = 'Activity 1: unknown. Activity 2: 4-6 hours.'
    delta = activity(id='work-2', description=None,
        effort=fact('unknown', 9, status='UNKNOWN', minimum=None, maximum=None, unit=None))
    rejected = []
    v2.merge(data, capture(activities=[delta]), initial(blackboard={'employee_discovery_v2': data}, user_message=text, source_message_id=9), rejected)
    assert 'effort' not in data['work_items'][1] and rejected


def test_unknown_only_changes_requested_fields_and_does_not_repeat_missing_frequency(deterministic):
    state = pending_state(2)
    items = state['blackboard']['employee_discovery_v2']['work_items']
    del items[0]['frequency']
    items[0]['effort'] = fact('2-3 hours', minimum=2., maximum=3., unit='hours')
    state = v2.discovery_graph.invoke(state)
    batch = state['blackboard']['employee_discovery_v2']['last_sizing_batch']
    state = answer(state, '\n'.join(f"{i}. " + ('unknown' if row['item'] == 'work-1' else '15 to 30 minutes')
        for i, row in enumerate(batch, 1)))
    data = state['blackboard']['employee_discovery_v2']
    assert state['v2_plan']['review']
    assert data['work_items'][0]['effort']['minimum'] == 2
    assert data['work_items'][0]['frequency']['fact_status'] == 'UNKNOWN'
    assert data['work_items'][1]['frequency']['value'] == 'daily'
    assert data['follow_up_requirements'][0]['field'] == 'frequency'
