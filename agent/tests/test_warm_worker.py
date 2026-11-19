"""The pre-warmed turn worker keeps the isolation contract of the cold path:
one turn per process, deadline-killable, and always replaced after use."""
import asyncio
import time
import uuid

import pytest

from app import isolated_turn


@pytest.fixture
def isolated_redis(monkeypatch):
    from app.config import settings
    monkeypatch.setattr(settings, 'redis_url', settings.redis_url)


def test_warm_worker_runs_one_turn_and_is_replaced(isolated_redis):
    isolated_turn._start_warm()
    first = isolated_turn._warm[0]
    # An empty state is rejected by the engine; the worker must still answer once.
    result = asyncio.run(isolated_turn.run_isolated('warm-' + str(uuid.uuid4()), 1, {}, True, time.time() + 40))
    assert isinstance(result, dict)
    assert not first.is_alive()  # Single use: the process that served the turn is gone.
    assert isolated_turn._warm and isolated_turn._warm[0].pid != first.pid and isolated_turn._warm[0].is_alive()


def test_dead_warm_worker_falls_back_to_a_fresh_process(isolated_redis):
    isolated_turn._start_warm()
    isolated_turn._warm[0].kill()
    isolated_turn._warm[0].join(2)
    result = asyncio.run(isolated_turn.run_isolated('cold-' + str(uuid.uuid4()), 1, {}, True, time.time() + 40))
    assert isinstance(result, dict)


def test_warm_worker_is_killed_at_the_deadline(isolated_redis, monkeypatch):
    isolated_turn._start_warm()
    worker = isolated_turn._warm[0]
    # Deadline already almost over: the turn expires and the worker is terminated.
    result = asyncio.run(isolated_turn.run_isolated('deadline-' + str(uuid.uuid4()), 1, {'slow': True}, True, time.time() + .05))
    assert result['error'] == 'deadline_exceeded'
    worker.join(3)
    assert not worker.is_alive()
