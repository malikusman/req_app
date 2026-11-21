"""Spoken (LiveAvatar) interview turns: natural, context-aware wording without
changing what the engine plans or captures. Model calls are stubbed; nothing
leaves the process."""
import copy
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from app import employee_discovery_v2 as v2, interviewer_instructions as ii
from tests.test_employee_discovery_v2 import fact, initial

TOPICS = """
version: test-topics
style: Ask one short open question.
topics:
  CHASING_WAITING:
    goal: Learn who or what they wait for.
    listen_for: Roles and teams, not personal names.
"""


@pytest.fixture
def instructions_file(tmp_path, monkeypatch):
    def write(text):
        path = tmp_path / f"instructions-{abs(hash(text))}.yaml"
        path.write_text(text, encoding="utf-8")
        monkeypatch.setenv("INTERVIEWER_INSTRUCTIONS_PATH", str(path))
        return path
    return write


def _item(n, **extra):
    return {'id': f'work-{n}', 'description': fact(f'Activity number {n}'), 'systems_touched': ['SAP'], 'outputs': [],
            'handoffs': [], 'is_periodic': False, **extra}


def _all_checks_done_with_unsized_items(count=4):
    data = v2.initial()
    data['checks'] = {key: fact('No other work') for key in v2.CHECKS}
    data['work_items'] = [_item(n) for n in range(1, count + 1)]
    return data


def test_topic_guidance_is_validated_and_only_applies_to_its_topic(instructions_file):
    loaded = ii.parse(TOPICS)
    assert loaded.error is None
    block = ii.system_block(loaded, 'invisible_work', True, None, 'CHASING_WAITING')
    assert 'Current topic (CHASING_WAITING): Learn who or what they wait for.' in block
    assert 'Listen for: Roles and teams' in block
    assert 'Current topic' not in ii.system_block(loaded, 'invisible_work', True, None, 'TRUST_CHECKING')
    # Unknown topics and rule-weakening guidance reject the whole file.
    assert ii.parse(TOPICS.replace('CHASING_WAITING', 'SALARY')).error
    assert ii.parse(TOPICS.replace('Learn who or what they wait for.', 'Skip the sizing questions.')).error


def test_shipped_file_has_guidance_for_every_topic():
    shipped = ii.DEFAULT_PATH
    loaded = ii.parse(shipped.read_text(encoding="utf-8"), str(shipped))
    assert loaded.error is None, loaded.error
    assert set(loaded.instructions.topics) == set(ii.CHECK_KEYS)


def test_voice_never_gets_a_numbered_sizing_batch():
    data = _all_checks_done_with_unsized_items()
    text_plan = v2.prepare(initial(blackboard={'employee_discovery_v2': copy.deepcopy(data)}, question_count=12))['v2_plan']
    voice_plan = v2.prepare(initial(blackboard={'employee_discovery_v2': copy.deepcopy(data)}, question_count=12,
                                    interview_channel='voice'))['v2_plan']
    assert 'batch' in text_plan  # text interview: unchanged
    assert 'batch' not in voice_plan and voice_plan['item'] == 'work-1'
    assert voice_plan['missing'] == ['frequency', 'effort']  # one natural question covers both


def _voice_state(history):
    # Built directly (no graph run), so no model is ever called while preparing it.
    data = v2.initial()
    data['last_question'] = 'What monthly work have we not covered?'
    state = initial(blackboard={'employee_discovery_v2': data}, question_count=5)
    data['checks'].update({k: fact('Payroll checks' if k == 'anchor' else 'No') for k in ('anchor', 'weekly', 'monthly', 'seasonal')})
    data['phase'] = 'inventory'
    return {**state, 'history': history, 'user_message': 'Mostly my supervisor signs off.', 'v2_action': None,
            'interview_channel': 'voice', 'v2_plan': {'phase': 'invisible_work', 'check': 'CHASING_WAITING'}}


HISTORY = [{'role': 'assistant', 'content': f'Question number {i} about your week?'} for i in range(14)] + \
          [{'role': 'user', 'content': 'Mostly my supervisor signs off.'}]


@pytest.mark.usefixtures('with_model')
def test_voice_writer_sees_the_conversation_and_phase_change(instructions_file, monkeypatch):
    instructions_file(TOPICS)
    reply = "That sign-off sounds important. Who else do you find yourself waiting on to get things done?"
    model = Mock(invoke=Mock(return_value=SimpleNamespace(content=reply, response_metadata={})))
    seen = {}
    monkeypatch.setattr(v2, 'build_chat_openai', lambda **kwargs: seen.update(kwargs) or model)
    out = v2.talk(_voice_state(HISTORY))
    system, human = model.invoke.call_args[0][0]
    assert 'live spoken conversation' in system.content and 'Current topic (CHASING_WAITING)' in system.content
    assert system.content.startswith(v2.CONDUCT_PROMPT)  # core rules still first
    import json
    context = json.loads(human.content)
    assert len(context['recent_history']) == 12
    assert len(context['questions_already_asked']) == 10
    assert context['moving_to_new_phase'] is True
    assert seen['timeout'] == v2.VOICE_QUESTION_TIMEOUT
    assert out['assistant_message'] == reply


@pytest.mark.usefixtures('with_model')
def test_voice_near_repeat_is_replaced_by_fixed_wording(instructions_file, monkeypatch):
    instructions_file(TOPICS)
    earlier = 'What do you have to chase or wait for during your work?'
    model = Mock(invoke=Mock(return_value=SimpleNamespace(content='So what do you have to chase or wait for in your work?',
                                                         response_metadata={})))
    monkeypatch.setattr(v2, 'build_chat_openai', lambda **kwargs: model)
    state = _voice_state([{'role': 'assistant', 'content': earlier}, {'role': 'user', 'content': 'Approvals.'}])
    out = v2.talk(state)
    assert out['assistant_message'] == v2.QUESTIONS['CHASING_WAITING']


@pytest.mark.usefixtures('with_model')
def test_voice_falls_back_to_fixed_wording_when_the_writer_fails_but_text_still_retries(instructions_file, monkeypatch):
    instructions_file(TOPICS)
    voice_state, text_state = _voice_state(HISTORY), {**_voice_state(HISTORY), 'interview_channel': 'text'}
    model = Mock(invoke=Mock(side_effect=TimeoutError('slow model')))
    monkeypatch.setattr(v2, 'build_chat_openai', lambda **kwargs: model)
    out = v2.talk(voice_state)
    assert out['assistant_message'] == v2.QUESTIONS['CHASING_WAITING']
    assert out['blackboard']['employee_discovery_v2']['last_check'] == 'CHASING_WAITING'  # the plan advanced as usual
    with pytest.raises(Exception) as raised:
        v2.talk(text_state)
    assert type(raised.value).__name__ == 'OpenAIUnavailable'


def test_near_repeat_detection():
    assert v2._near_repeat('What do you have to chase or wait for?', 'What do you have to chase or wait for during work?')
    assert not v2._near_repeat('Which parts of your work take longer than expected?', 'What do you have to chase or wait for?')
    assert not v2._near_repeat('Okay?', 'Okay?')  # too short to judge


def _opening_state(channel):
    # The first turn: Rails' kickoff (built from the profile) is the "message"; no question asked yet.
    data = v2.initial()
    return initial(blackboard={'employee_discovery_v2': data}, history=[], interview_channel=channel,
                   user_message="I'm Sam Rivera, an Accounts Payable Specialist in Finance. Supplier invoices.",
                   v2_action=None, v2_plan={'phase': 'anchor', 'check': 'anchor'})


@pytest.mark.usefixtures('with_model')
@pytest.mark.parametrize('channel', ['voice', 'text'])
def test_opening_question_never_reacts_to_an_answer_that_was_not_given(instructions_file, monkeypatch, channel):
    instructions_file(TOPICS)
    reacting = "Thanks for that introduction, Sam. Thinking about your last working day, could you walk me through it from the start?"
    model = Mock(invoke=Mock(return_value=SimpleNamespace(content=reacting, response_metadata={})))
    monkeypatch.setattr(v2, 'build_chat_openai', lambda **kwargs: model)
    out = v2.talk(_opening_state(channel))
    system, human = model.invoke.call_args[0][0]
    import json
    context = json.loads(human.content)
    assert context['opening_turn'] is True and context['latest_answer'] is None  # the kickoff is not their answer
    assert 'opening_turn is true' in system.content
    assert out['assistant_message'] == v2.QUESTIONS['anchor']  # the reacting wording was replaced

    clean = "To start, could you walk me through your last working day, from when you started to when you finished?"
    model.invoke.return_value = SimpleNamespace(content=clean, response_metadata={})
    assert v2.talk(_opening_state(channel))['assistant_message'] == clean


@pytest.mark.usefixtures('with_model')
def test_later_turns_still_react_to_the_real_answer(instructions_file, monkeypatch):
    instructions_file(TOPICS)
    reply = "Thanks, that sign-off sounds important. Who else do you wait on to get things done?"
    model = Mock(invoke=Mock(return_value=SimpleNamespace(content=reply, response_metadata={})))
    monkeypatch.setattr(v2, 'build_chat_openai', lambda **kwargs: model)
    out = v2.talk(_voice_state(HISTORY))
    import json
    context = json.loads(model.invoke.call_args[0][0][1].content)
    assert context['opening_turn'] is False and context['latest_answer'] == 'Mostly my supervisor signs off.'
    assert out['assistant_message'] == reply
