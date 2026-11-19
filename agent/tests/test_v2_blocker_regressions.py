"""Regressions for the Stage 1 audit blockers (B1-B4, C1-C2, duplicate work items).

Each case uses the synthetic answers that stranded the audit interviews. No live
provider: the model's real (recorded) failure shapes are injected as captures."""
import copy

import pytest

from app import employee_discovery_v2 as v2
from test_employee_discovery_v2 import initial, covered_data, fact, activity, capture


def state_for(data, text, source=50, **extra):
    return initial(blackboard={'employee_discovery_v2': data}, user_message=text, source_message_id=source,
                   history=[{'role': 'user', 'content': text, 'message_id': source}], **extra)


ANCHOR = ('I started at 8:30 by clearing the HR inbox, mostly leave requests and salary certificate requests, '
          'which took about an hour. Before lunch I did two phone screening interviews.')


def test_b1_b3_point_estimate_converted_by_model_is_read_as_said_not_fatal():
    # Audit interview #2: the model turned "about an hour" into 60-60 minutes; the
    # whole turn failed three times. Now the duration is read from the quote.
    data = v2.initial()
    data.update(last_check='anchor', last_question=v2.QUESTIONS['anchor'])
    state = state_for(data, ANCHOR)
    delta = activity('HR inbox', 50, frequency=None,
                     effort=fact('which took about an hour', 50, minimum=60., maximum=60., unit='minutes'))
    delta['description'] = fact('clearing the HR inbox', 50)
    rejected = []
    assert v2.merge(data, capture(activities=[delta, activity('phone screening interviews', 50)]), state, rejected)
    inbox = data['work_items'][0]
    assert (inbox['effort']['minimum'], inbox['effort']['maximum'], inbox['effort']['unit']) == (1, 1, 'hours')
    assert len(data['work_items']) == 2 and not rejected
    assert 'anchor' in data['checks']


def test_b1_copied_estimate_on_numberless_answer_is_dropped_but_answer_is_kept():
    # Audit interview #1, turn 6: the existing 1-2 h estimate was re-cited against a
    # sentence with no numbers; the answer and its probe closure were lost.
    data = covered_data()
    data['checks'].pop('SLOWER_THAN_EXPECTED')
    data['work_items'][0]['description'] = fact('Weekly recruitment report')
    data.update(last_check='SLOWER_THAN_EXPECTED', last_question=v2.QUESTIONS['SLOWER_THAN_EXPECTED'], phase='invisible_work')
    text = 'Honestly the weekly recruitment report takes longer than it should, I rebuild it by hand every Monday.'
    copied = activity(id='work-1', description=None,
                      effort=fact('the weekly recruitment report takes longer than it should', 50, minimum=1., maximum=2., unit='hours'))
    rejected = []
    v2.merge(data, capture(activities=[copied]), state_for(data, text), rejected)
    assert data['work_items'][0]['effort']['minimum'] == 20  # Original estimate untouched.
    assert rejected and rejected[0]['field'] == 'effort'
    assert 'SLOWER_THAN_EXPECTED' in data['checks']
    assert any(s['probe_type'] == 'SLOWER_THAN_EXPECTED' and s['work_item_id'] == 'work-1' for s in data['invisible_work_signals'])


def test_b1_self_referencing_inclusion_is_dropped_without_failing_the_turn():
    # Audit interview #1, turn 9 ("Effort inclusion has no child activities").
    data = covered_data()
    data['checks'].pop('TRUST_CHECKING')
    data['work_items'][0]['description'] = fact('Preparing the payroll input file')
    data.update(last_check='TRUST_CHECKING', last_question=v2.QUESTIONS['TRUST_CHECKING'], phase='invisible_work')
    text = ('Before I send the payroll input file I double-check every line against the HRIS because the leave balances '
            'are often wrong. That check is part of the monthly payroll preparation time I gave you.')
    bad = {'work_item_ids': ['work-1'], 'included_in_work_item_id': 'work-1',
           'reason': fact('That check is part of the monthly payroll preparation time I gave you', 50)}
    rejected = []
    assert v2.merge(data, capture(effort_inclusions=[bad]), state_for(data, text), rejected)
    assert 'TRUST_CHECKING' in data['checks'] and rejected[0]['field'] == 'effort_inclusion'
    assert any(s['probe_type'] == 'TRUST_CHECKING' for s in data['invisible_work_signals'])


def test_c1_single_day_recall_does_not_become_daily():
    data = v2.initial()
    data.update(last_check='anchor', last_question=v2.QUESTIONS['anchor'])
    rejected = []
    screening = activity('phone screening interviews', 50, frequency=fact('Before lunch I did two phone screening interviews', 50))
    screening['frequency']['value'] = 'daily'
    v2.merge(data, capture(activities=[screening]), state_for(data, ANCHOR), rejected)
    assert 'frequency' not in data['work_items'][0]
    assert rejected[0]['field'] == 'frequency'
    weekly = v2._fact(fact('every Monday', 51), state_for(data, 'I prepare the report every Monday', 51), 'frequency')
    assert weekly['value'] == 'every Monday'


@pytest.mark.parametrize('text', ["That's all, thanks.", 'Perfect, nothing missing.', 'Yes, all good.', 'Looks good to me',
                                  "Yes that's everything", 'Correct, nothing else to add', 'Spot on'])
def test_b4_natural_confirmations_are_explicit_approval(text):
    assert v2._approval(text)


@pytest.mark.parametrize('text', ['Yes, but add the handbook update', 'No, payroll is 3 hours', "That's not right",
                                  'Mostly right', 'ok', 'Yes, I also run inductions', 'Looks good except the report'])
def test_b4_changes_hedges_and_bare_ok_are_not_approval(text):
    assert not v2._approval(text)


def test_b4_unrecognised_readback_reply_asks_explicitly_and_never_dead_ends(monkeypatch):
    data = covered_data()
    state = v2.discovery_graph.invoke(initial(blackboard={'employee_discovery_v2': data}, question_count=12))
    summary = state['assistant_message']
    assert summary.startswith('Here is what I captured')
    history = [{'role': 'assistant', 'content': summary}]
    for i, text in enumerate(['hmm ok', 'I suppose', 'ok'], start=60):
        monkeypatch.setattr(v2, 'extract', lambda _: capture())
        state = v2.discovery_graph.invoke({**state, 'user_message': text, 'source_message_id': i,
                                           'history': history + [{'role': 'user', 'content': text, 'message_id': i}]})
        if state['completed']:
            break
        assert state['assistant_message'] == v2.CONFIRM_PROMPT['en']
    data = state['blackboard']['employee_discovery_v2']
    # "ok" only counts after the explicit yes/no prompt, and binds to the shown summary.
    assert state['completed'] and data['outcome'] == 'successful'
    assert data['confirmation']['revision'] == data['presented_summary']['revision']


def test_c2_completing_a_lost_range_is_not_a_contradiction():
    old = fact('4 to 6 hours', minimum=None, maximum=None, unit=None, basis='per_month')
    new = fact('4 to 6 hours each month', 2, minimum=4., maximum=6., unit='hours', basis='per_month')
    merged = v2._merge_fact(old, new, field='effort')
    assert merged['fact_status'] == 'REPORTED' and merged['history'][0]['minimum'] is None


def test_c2_contradiction_can_be_resolved_by_choosing_and_keeps_history():
    data = covered_data()
    data['work_items'][0]['effort'] = {**fact('3 to 4 hours', 2, minimum=3., maximum=4., unit='hours'), 'fact_status': 'CONTRADICTED',
                                       'history': [fact('20 to 30 minutes', minimum=20., maximum=30., unit='minutes')]}
    data.update(last_item='work-1', last_clarification={'item': 'work-1', 'field': 'effort'}, phase='size_close',
                last_question=v2._clarify_question(data['work_items'][0], 'effort', False))
    assert '“20–30 minutes”' in data['last_question'] and '“3–4 hours”' in data['last_question']
    state = v2.record(state_for(data, 'The first one is right', 70))
    effort = state['blackboard']['employee_discovery_v2']['work_items'][0]['effort']
    assert effort['fact_status'] == 'REPORTED' and effort['minimum'] == 20
    assert effort['resolution']['evidence'][0]['message_id'] == 70 and len(effort['history']) == 2


def test_c2_unresolved_clarification_is_deferred_not_looped(monkeypatch):
    data = covered_data()
    data['work_items'][0]['effort'] = {**fact('3 to 4 hours', 2, minimum=3., maximum=4., unit='hours'), 'fact_status': 'CONTRADICTED',
                                       'history': [fact('20 to 30 minutes', minimum=20., maximum=30., unit='minutes')]}
    data.update(last_item='work-1', last_clarification={'item': 'work-1', 'field': 'effort'}, phase='size_close', last_question='Which?')
    monkeypatch.setattr(v2, 'extract', lambda _: capture())
    for i in (80, 81):
        state = v2.discovery_graph.invoke(state_for(data, 'not sure really', i))
        data = state['blackboard']['employee_discovery_v2']
    assert state['v2_plan'].get('review')  # Moves on to read-back.
    assert data['work_items'][0]['effort']['fact_status'] == 'CONTRADICTED'  # Never silently resolved.
    assert any(r['reason'] == 'unresolved_contradiction' for r in data['follow_up_requirements'])
    assert not v2.coverage(data)['sizing']


def test_duplicate_probe_activity_becomes_a_signal_on_existing_work():
    # Audit engine run 3: "Using WhatsApp to chase hiring managers..." duplicated work-1.
    data = covered_data()
    data['work_items'][0]['description'] = fact('Chasing hiring managers on WhatsApp for interview feedback')
    data['checks'].pop('OUTSIDE_SYSTEMS')
    data.update(last_check='OUTSIDE_SYSTEMS', last_question=v2.QUESTIONS['OUTSIDE_SYSTEMS'], phase='invisible_work')
    text = 'All the chasing of hiring managers for interview feedback happens on WhatsApp.'
    dup = activity('Using WhatsApp to chase hiring managers for interview feedback', 50)
    dup['description']['quote'] = 'chasing of hiring managers for interview feedback happens on WhatsApp'
    v2.merge(data, capture(activities=[dup]), state_for(data, text))
    assert len(data['work_items']) == 1
    assert data['invisible_work_signals'][0]['work_item_id'] == 'work-1'


def test_mixed_numbered_batch_reads_durations_unknowns_and_inclusions_without_model(monkeypatch):
    # Audit engine run 3: a natural mixed batch answer failed 3/3 through the model.
    monkeypatch.setattr(v2, '_recording_model', lambda *a: pytest.fail('Exact rows need no model'))
    monkeypatch.setattr(v2, 'llm_configured', lambda: True)
    data = covered_data()
    data['work_items'] = [
        {**copy.deepcopy(data['work_items'][0]), 'id': 'work-1', 'description': fact('Overall recruitment coordination'),
         'effort': fact('10 to 12 hours a week', minimum=10., maximum=12., unit='hours', basis='per_week')},
        {'id': 'work-2', 'description': fact('Screening CVs'), 'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': None},
        {'id': 'work-3', 'description': fact('Handling grievance cases'), 'frequency': fact('a few times a year'),
         'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': None},
        {'id': 'work-4', 'description': fact('Clearing the HR inbox'), 'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': None}]
    batch = [{'item': 'work-2', 'missing': ['frequency', 'effort']}, {'item': 'work-3', 'missing': ['effort']},
             {'item': 'work-4', 'missing': ['frequency', 'effort']}]
    data.update(last_sizing_batch=batch, last_question=v2._sizing_question(data, batch, False), phase='size_close')
    text = ('1. weekly, included in my recruitment coordination time\n2. honestly no idea, it depends on the case\n'
            '3. every day, 45 to 60 minutes')
    state = v2.discovery_graph.invoke(state_for(data, text, question_count=12))
    items = {w['id']: w for w in state['blackboard']['employee_discovery_v2']['work_items']}
    assert items['work-2']['effort_inclusion']['value'] == 'work-1' and 'effort' not in items['work-2']
    assert items['work-3']['effort']['fact_status'] == 'UNKNOWN'
    assert items['work-4']['frequency']['value'] == 'every day'
    assert (items['work-4']['effort']['minimum'], items['work-4']['effort']['maximum']) == (45, 60)


def test_wrong_one_word_parent_is_rejected_and_employee_named_group_is_created_verbatim():
    # Live interview: "part of my overall recruitment time" was linked to the
    # "weekly recruitment status report" on one shared word. That link is now
    # rejected; a correction naming the group creates it from the employee's words.
    data = covered_data()
    data['work_items'] = [
        {'id': 'work-1', 'description': fact('Screening CVs'), 'frequency': fact('weekly'), 'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': None},
        {'id': 'work-2', 'description': fact('Conducting phone screening interviews'), 'frequency': fact('weekly'), 'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': None},
        {'id': 'work-3', 'description': fact('Preparing the weekly recruitment status report'), 'frequency': fact('every Monday'),
         'effort': fact('1 to 2 hours', minimum=1., maximum=2., unit='hours'), 'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': None}]
    data.update(phase='size_close')
    said = 'It is part of my overall recruitment time'
    v2.merge(data, capture(effort_inclusions=[{'work_item_ids': ['work-1'], 'included_in_work_item_id': 'work-3', 'reason': fact(said, 50)}]),
             state_for(copy.deepcopy(data), said))
    group = data['work_items'][-1]
    # Not linked to the report on one shared word: linked to the group the employee named.
    assert data['work_items'][0]['effort_inclusion']['value'] == group['id'] != 'work-3'
    assert group['description']['value'] == 'Overall recruitment' and 'effort' not in group
    text = 'They are not part of the weekly report. They are part of my overall recruitment work, which takes 10 to 12 hours a week in total.'
    # The model often quotes the negated sentence too; only the affirmative clause is cited.
    quote = 'They are not part of the weekly report. They are part of my overall recruitment work, which takes 10 to 12 hours a week in total'
    v2.merge(data, capture(effort_inclusions=[{'work_item_ids': ['work-1', 'work-2'], 'included_in_work_item_id': '',
                                               'reason': {**fact(quote, 51), 'correction': True}}]), state_for(data, text, 51))
    assert data['work_items'][-1] is group and len(data['work_items']) == 4  # Same group reused, not duplicated.
    assert (group['effort']['minimum'], group['effort']['maximum'], group['effort']['basis']) == (10, 12, 'per_week')
    assert {w['id']: (w.get('effort_inclusion') or {}).get('value') for w in data['work_items'][:2]} == {'work-1': group['id'], 'work-2': group['id']}
    assert 'effort' not in data['work_items'][0]  # The group total is never copied onto a child.
    assert 'not part of' not in data['work_items'][1]['effort_inclusion']['quote']


def test_unknown_needs_the_employee_saying_they_cannot_estimate():
    # Live interview C: an overhead remark was recorded as UNKNOWN effort.
    state = state_for(v2.initial(), 'the rota changes for sure, because I have to type every swap twice', 60)
    with pytest.raises(v2.OpenAIUnavailable):
        v2._fact(fact('the rota changes for sure', 60, status='UNKNOWN', minimum=None, maximum=None, unit=None), state, 'effort')
    ok = state_for(v2.initial(), 'no idea in hours honestly', 61)
    assert v2._fact(fact('no idea in hours honestly', 61, status='UNKNOWN', minimum=None, maximum=None, unit=None), ok, 'effort')['fact_status'] == 'UNKNOWN'


@pytest.mark.parametrize('text', ['end of month I do the overtime file', 'month end payroll', 'five or six hours a week', 'an hour or two a day'])
def test_said_period_totals_and_month_end_are_frequencies(text):
    assert v2.frequency_phrase(text)


def test_day_estimates_are_recorded_in_days(monkeypatch):
    monkeypatch.setattr(v2, 'llm_configured', lambda: True)
    monkeypatch.setattr(v2, '_recording_model', lambda *a: pytest.fail('An explicit duration needs no model'))
    data = covered_data()
    data['work_items'][0]['effort'] = None
    data['work_items'][0].pop('effort')
    data.update(last_item='work-1', last_question='For Review invoices, roughly how much of your own working time does each occurrence take, as a range?',
                phase='size_close')
    state = v2.record(state_for(data, 'About 2 to 3 days each time', 90))
    effort = state['blackboard']['employee_discovery_v2']['work_items'][0]['effort']
    assert (effort['minimum'], effort['maximum'], effort['unit'], effort['basis']) == (2, 3, 'days', 'per_occurrence')
