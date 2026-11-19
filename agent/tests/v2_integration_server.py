"""Isolated HTTP test server. Real FastAPI/LangGraph; deterministic provider stub.

Never imported by production. Start explicitly on port 8005 for the Rails request
integration spec. The normal Agent process and real provider remain untouched.
"""
import json
import os
from pathlib import Path

import uvicorn

from app import employee_discovery_v2 as v2, main
from app.multi_agent_graph import execute_multi_agent_turn


def fact(text, source):
    return {'value': text, 'fact_status': 'REPORTED', 'quote': text, 'source_message_id': source, 'correction': False}


def extraction(state):
    data = state['blackboard']['employee_discovery_v2']
    key, text, source = data.get('last_check'), state['user_message'], state['source_message_id']
    activities = []
    settings = {
        'anchor': ('Review invoices', 'daily', '20 to 30 minutes', 20., 30., False),
        'weekly': ('Prepare reports', 'weekly', '10 to 15 minutes', 10., 15., True),
        'OUTSIDE_SYSTEMS': ('Retype prices', None, None, None, None, False),
    }
    if key in settings:
        name, frequency, duration, lo, hi, periodic = settings[key]
        activities.append({'id': None, 'description': fact(name, source),
            'frequency': fact(frequency, source) if frequency else None,
            'effort': {**fact(duration, source), 'minimum': lo, 'maximum': hi, 'unit': 'minutes'} if duration else None,
            'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': periodic})
    elif data.get('last_item'):
        activities.append({'id': data['last_item'], 'description': None, 'frequency': fact('weekly', source),
            'effort': {**fact('5 to 10 minutes', source), 'minimum': 5., 'maximum': 10., 'unit': 'minutes'},
            'systems_touched': [], 'outputs': [], 'handoffs': [], 'is_periodic': None})
    return v2.Capture.model_validate({'activities': activities,
        'checks': [{'name': key, 'fact': fact(text, source)}] if key else [], 'invisible_work': [], 'shadow_ai': [], 'removed_activities': []})


async def execution(thread_id, source_id, state, multi_agent, deadline, identity=None, revision=0):
    return execute_multi_agent_turn(state)


if __name__ == '__main__':
    Path('/tmp/mjadi-v2-integration.pid').write_text(str(os.getpid()))
    v2.extract = extraction
    v2.llm_configured = lambda: False
    main.run_isolated = execution
    uvicorn.run(main.app, host='0.0.0.0', port=8005, log_level='warning')
