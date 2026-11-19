import asyncio
import json
import os
import subprocess
import sys
import time
import uuid
from pathlib import Path

import pytest
import redis

from app import isolated_turn
from app.config import settings
from isolation_workers import success, forever

URL = 'redis://redis:6379/15'

@pytest.fixture(autouse=True)
def isolated_redis(monkeypatch):
    monkeypatch.setattr(settings, 'redis_url', URL)


def test_blocking_child_is_terminated_at_deadline():
    start = time.monotonic()
    result = asyncio.run(isolated_turn.run_isolated('timeout-' + str(uuid.uuid4()), 1, {}, True, time.time() + .3, runner=forever))
    assert result['error'] == 'deadline_exceeded'
    assert time.monotonic() - start < 2


def test_queue_wait_counts_against_deadline(monkeypatch):
    monkeypatch.setattr(isolated_turn, '_slots', asyncio.Semaphore(0))
    start = time.monotonic()
    result = asyncio.run(isolated_turn.run_isolated(str(uuid.uuid4()), 1, {}, True, time.time() + .2, runner=forever))
    assert result['error'] == 'deadline_exceeded'
    assert time.monotonic() - start < 2


def worker_script(state, identity, revision=0):
    return """import asyncio,json,time
from app.config import settings
from app.isolated_turn import run_isolated
from isolation_workers import success
settings.redis_url = %r
r=asyncio.run(run_isolated('integration',1,%r,True,time.time()+20,identity=%r,revision=%r,runner=success))
print(json.dumps(r))
""" % (URL, state, identity, revision)


def child_env():
    return {**os.environ, 'PYTHONDONTWRITEBYTECODE': '1', 'PYTHONPATH': os.environ.get('PYTHONPATH','') + os.pathsep + str(Path(__file__).parent)}


def test_two_worker_processes_and_restart_share_one_redis_result():
    identity = str(uuid.uuid4())
    state = {'redis_url': URL, 'counter': 'audit:counter:' + identity, 'sleep': .2}
    code = worker_script(state, identity)
    processes = [subprocess.Popen([sys.executable, '-c', code], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=child_env()) for _ in range(2)]
    outputs = [p.communicate(timeout=30) for p in processes]
    assert all(p.returncode == 0 for p in processes), outputs
    assert all(json.loads(stdout)['question_count'] == 1 for stdout, _ in outputs)
    # A new interpreter simulates replacement of the FastAPI worker.
    cached = subprocess.check_output([sys.executable, '-c', code], env=child_env(), text=True, timeout=30)
    assert json.loads(cached)['question_count'] == 1
    assert redis.from_url(URL).get(state['counter']) == b'1'


def test_identity_cannot_reuse_result_for_a_different_snapshot():
    identity = str(uuid.uuid4())
    state = {'redis_url': URL, 'counter': 'audit:counter:' + identity}
    first = asyncio.run(isolated_turn.run_isolated('snapshot', 1, state, True, time.time()+15, identity, 0, success))
    assert not first.get('error')
    changed = {**state, 'answer': 'different'}
    result = asyncio.run(isolated_turn.run_isolated('snapshot', 1, changed, True, time.time()+15, identity, 0, success))
    assert result['error'] == 'turn_identity_conflict'
    assert not result['retryable']


def test_larger_revision_does_not_reuse_an_old_result():
    identity = str(uuid.uuid4())
    state = {'redis_url': URL, 'counter': 'audit:counter:' + identity}
    for revision in [0, 1]:
        result = asyncio.run(isolated_turn.run_isolated('revision', 1, state, True, time.time()+15, identity, revision, success))
        assert not result.get('error')
    assert redis.from_url(URL).get(state['counter']) == b'2'


@pytest.mark.skipif(sys.platform != 'linux', reason='Docker Linux parent-death guarantee')
def test_crashed_worker_does_not_leave_its_child_running():
    identity = str(uuid.uuid4())
    pid_key = 'audit:pid:' + identity
    state = {'redis_url': URL, 'pid_key': pid_key}
    code = """import asyncio,time
from app.config import settings
from app.isolated_turn import run_isolated
from isolation_workers import forever
settings.redis_url=%r
asyncio.run(run_isolated('parent-death',1,%r,True,time.time()+20,identity=%r,runner=forever))
""" % (URL, state, identity)
    worker = subprocess.Popen([sys.executable, '-c', code], env=child_env(), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    client = redis.from_url(URL)
    try:
        until = time.monotonic() + 12
        value = None
        while time.monotonic() < until:
            value = client.get(pid_key)
            if value:
                break
            time.sleep(.05)
        assert value, 'child did not start'
        pid = int(value)
        worker.kill()
        worker.wait(timeout=5)
        until = time.monotonic() + 3
        alive = True
        while time.monotonic() < until:
            path = Path(f'/proc/{pid}/stat')
            alive = path.exists() and path.read_text().split()[2] != 'Z'
            if not alive:
                break
            time.sleep(.05)
        assert not alive
    finally:
        if worker.poll() is None:
            worker.kill()
            worker.wait(timeout=5)
