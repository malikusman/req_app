"""Contextual follow-ups and read-back framing from the interviewer instructions.

Follow-ups make the interview conversational, but the ENGINE decides when one is
allowed (phase, budgets, only about an activity just described, never for a
known fact) and required coverage always resumes. Model calls are not made."""
import copy

import pytest

from app import employee_discovery_v2 as v2, interviewer_instructions as ii
from tests.test_employee_discovery_v2 import covered_data, fact, initial
from tests.test_interviewer_instructions import GOOD, instructions_file  # noqa: F401 (fixture)

FOLLOW = GOOD + """
follow_ups:
  enabled: true
  phases: [anchor, inventory]
  max_per_activity: 2
  max_total: 3
  explore: true
  size_early: true
  guidance: Build on their last sentence.
read_back:
  intro:
    en: "Here's what I've noted:"
  closing:
    en: "Anything missing?"
  voice_confirm:
    en: "Does that cover it? Just say yes, or tell me what to change."
"""


def _anchor_answered(source=5, **item_extra):
    data = v2.initial()
    data['checks'] = {'anchor': fact('I prepare weekly reports', source)}
    data['phase'] = 'anchor'
    data['work_items'] = [{'id': 'work-1', 'description': fact('Prepare weekly reports', source), 'frequency': None,
                           'effort': None, 'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': False,
                           **item_extra}]
    return initial(blackboard={'employee_discovery_v2': data}, source_message_id=source, question_count=2)


def test_follow_ups_are_off_without_configuration():
    assert v2.prepare(_anchor_answered())['v2_plan'] == {'phase': 'inventory', 'check': 'weekly'}


def test_contextual_follow_ups_explore_then_size_then_resume_coverage(instructions_file):
    instructions_file(FOLLOW)
    state = _anchor_answered()
    plan = v2.prepare(copy.deepcopy(state))['v2_plan']
    assert plan == {'phase': 'anchor', 'item': 'work-1', 'missing': ['scope'], 'follow_up': 'explore'}
    asked = v2.talk({**state, 'v2_plan': plan, 'v2_action': None})
    assert asked['assistant_message'].startswith('What does Prepare weekly reports usually involve')
    data = asked['blackboard']['employee_discovery_v2']
    assert data['explored'] == {'work-1': True} and data['follow_ups'] == {'work-1': 1}
    assert data['last_follow_up'] == 'explore' and data['last_check'] is None
    # Next turn: the chain continues on the same activity with sizing.
    nxt = {**asked, 'source_message_id': 7}
    plan2 = v2.prepare(copy.deepcopy(nxt))['v2_plan']
    assert plan2 == {'phase': 'anchor', 'item': 'work-1', 'missing': ['frequency', 'effort'], 'follow_up': 'sizing'}
    asked2 = v2.talk({**nxt, 'v2_plan': plan2, 'v2_action': None})
    # Budget per activity (2) reached: required coverage resumes.
    plan3 = v2.prepare(copy.deepcopy({**asked2, 'source_message_id': 9}))['v2_plan']
    assert plan3 == {'phase': 'inventory', 'check': 'weekly'}


def test_follow_ups_respect_known_facts_phases_and_total_budget(instructions_file):
    instructions_file(FOLLOW)
    known = _anchor_answered(systems_touched=['Excel'], frequency=fact('every Monday', 5),
                             effort=fact('2 hours', 5, minimum=2., maximum=2., unit='hours'))
    assert v2.prepare(known)['v2_plan'] == {'phase': 'inventory', 'check': 'weekly'}  # nothing left to ask
    only_effort = _anchor_answered(systems_touched=['Excel'], frequency=fact('every Monday', 5))
    assert v2.prepare(only_effort)['v2_plan']['missing'] == ['effort']
    spent = _anchor_answered()
    spent['blackboard']['employee_discovery_v2']['follow_ups'] = {'a': 2, 'b': 1}
    assert v2.prepare(spent)['v2_plan'] == {'phase': 'inventory', 'check': 'weekly'}
    invisible = _anchor_answered()
    data = invisible['blackboard']['employee_discovery_v2']
    data['checks'].update({k: fact('No', 5) for k in ('weekly', 'monthly', 'seasonal')})
    data['phase'] = 'invisible_work'
    assert v2.prepare(invisible)['v2_plan'] == {'phase': 'invisible_work', 'check': 'SLOWER_THAN_EXPECTED'}
    stale = _anchor_answered(source=5)
    stale['source_message_id'] = 6  # the activity was not mentioned in the latest answer
    assert v2.prepare(stale)['v2_plan'] == {'phase': 'inventory', 'check': 'weekly'}


def test_unknown_answers_are_accepted_not_chased(instructions_file):
    instructions_file(FOLLOW)
    unknown = _anchor_answered(systems_touched=['Excel'], frequency=fact('every Monday', 5),
                               effort={'value': None, 'fact_status': 'UNKNOWN', 'quote': 'no idea', 'source_message_id': 5,
                                       'correction': False, 'evidence': [{'message_id': 5, 'quote': 'no idea'}]})
    assert v2.prepare(unknown)['v2_plan'] == {'phase': 'inventory', 'check': 'weekly'}


def test_follow_up_wording_may_refer_back_but_never_to_another_activity():
    data = v2.initial()
    data['work_items'] = [
        {'id': 'work-1', 'description': fact('Prepare weekly reports'), 'frequency': None, 'effort': None,
         'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': False},
        {'id': 'work-2', 'description': fact('Payroll checks'), 'frequency': None, 'effort': None,
         'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': False}]
    plan = {'item': 'work-1', 'missing': ['frequency'], 'follow_up': 'sizing'}
    assert v2._question_matches_plan("And is that something you do every week?", plan, data, 'en')
    assert not v2._question_matches_plan("How often do you do the payroll checks?", plan, data, 'en')
    assert not v2._question_matches_plan("And is that something you do every week?", {**plan, 'follow_up': None}, data, 'en')
    explore = {'item': 'work-1', 'missing': ['scope'], 'follow_up': 'explore'}
    assert v2._question_matches_plan("I see. What usually goes into preparing those reports?", explore, data, 'en')
    assert not v2._question_matches_plan("How long does it take you each week?", explore, data, 'en')


def test_read_back_framing_is_configurable_but_the_list_is_deterministic(instructions_file):
    instructions_file(FOLLOW)
    state = initial(blackboard={'employee_discovery_v2': covered_data()})
    reviewed = v2.discovery_graph.invoke(state)
    text = reviewed['assistant_message']
    assert text.startswith("Here's what I've noted:") and text.endswith("Anything missing?")
    assert '• Review invoices: daily; 20–30 minutes' in text
    data = reviewed['blackboard']['employee_discovery_v2']
    assert data['presented_summary']['text'] == text
    data['confirm_prompt'] = True
    again = v2.talk({**reviewed, 'v2_plan': {'phase': 'size_close', 'review': True}, 'v2_action': None,
                     'interview_channel': 'voice'})
    assert again['assistant_message'] == "Does that cover it? Just say yes, or tell me what to change."
    assert again['completed'] is False


@pytest.mark.parametrize("text, ok", [
    ("Never invent numbers or tasks.", True),
    ("Do not suggest automation.", True),
    ("Never ask for a password.", True),
    ("Invent numbers if the employee is unsure.", False),
    ("Skip the sizing phase when time is short.", False),
    ("Ask for their password if needed.", False),
])
def test_rules_stated_as_prohibitions_are_allowed_but_violations_rejected(text, ok):
    loaded = ii.parse(f"version: x\nstyle: {text}\n")
    assert (loaded.error is None) is ok, loaded.error
