"""Redis-coordinated discovery execution with a killable, bounded local worker."""
import asyncio
import hashlib
import json
import logging
import multiprocessing
import os
import signal
import sys
import time
import uuid

import redis.asyncio as redis

from app.config import settings

_slots = asyncio.Semaphore(4)
_CLAIM = """
if redis.call('EXISTS', KEYS[1]) == 1 then
  if redis.call('HGET', KEYS[1], 'fingerprint') ~= ARGV[1] then return 'conflict' end
  return 'busy'
end
redis.call('HSET', KEYS[1], 'fingerprint', ARGV[1], 'token', ARGV[2])
redis.call('EXPIRE', KEYS[1], ARGV[3])
return 'claimed'
"""
_FINISH = """
if redis.call('HGET', KEYS[1], 'token') ~= ARGV[1] then return 0 end
if ARGV[3] == 'success' then
  redis.call('HSET', KEYS[1], 'result', ARGV[2])
  redis.call('EXPIRE', KEYS[1], 900)
else redis.call('DEL', KEYS[1]) end
return 1
"""


def _child(pipe, state, multi_agent, deadline_at):
    import logging
    if not logging.getLogger().handlers:
        # Spawned workers do not inherit Uvicorn's log setup; without this the
        # per-stage model timings are silently dropped.
        logging.basicConfig(level=logging.INFO, format='%(levelname)s:     [turn-worker] %(message)s')
    try:
        from app.turn_runtime import _deadline
        from app.multi_agent_graph import execute_multi_agent_turn
        from app.graph import execute_turn
        token = _deadline.set(time.monotonic() + max(0, deadline_at - time.time()))
        try:
            result = execute_multi_agent_turn(state) if multi_agent else execute_turn(state)
            pipe.send(result)
        finally:
            _deadline.reset(token)
    except BaseException as exc:
        pipe.send({'error': 'agent_execution_failed', 'retryable': True, 'error_detail': type(exc).__name__})
    finally:
        pipe.close()


def _guard_parent(parent_pid):
    # A crashed Uvicorn worker must not leave an orphaned model computation.
    if sys.platform == 'linux':
        import ctypes
        ctypes.CDLL(None).prctl(1, signal.SIGKILL)
        if os.getppid() != parent_pid:
            os.kill(os.getpid(), signal.SIGKILL)


def _warm_child(jobs, results, parent_pid):
    """A pre-started, single-use worker: same parent-death guard and one turn per
    process as the cold path, but the engine import (4-11 s) happens before the
    employee answers instead of inside their turn."""
    _guard_parent(parent_pid)
    try:
        import app.turn_runtime, app.multi_agent_graph, app.graph, app.employee_discovery_v2  # noqa: F401 (warm-up)
    except BaseException:
        pass  # _child reports the failure for the actual turn.
    try:
        state, multi_agent, deadline_at = jobs.recv()
    except (EOFError, OSError):
        return
    finally:
        jobs.close()
    _child(results, state, multi_agent, deadline_at)


_warm = None  # (process, job_sender, result_receiver), owned by this Uvicorn process


def _start_warm():
    global _warm
    context = multiprocessing.get_context('spawn')
    job_receiver, job_sender = context.Pipe(duplex=False)
    result_receiver, result_sender = context.Pipe(duplex=False)
    process = context.Process(target=_warm_child, args=(job_receiver, result_sender, os.getpid()), daemon=True)
    process.start()
    job_receiver.close()
    result_sender.close()
    _warm = (process, job_sender, result_receiver)


def _take_warm():
    """Hand out the ready worker (if healthy) and start warming its replacement."""
    global _warm
    taken, _warm = _warm, None
    try:
        _start_warm()
    except Exception:
        pass
    if taken and taken[0].is_alive():
        return taken
    if taken:
        for end in taken[1:]:
            end.close()
    return None


def _run_child(pipe, state, multi_agent, deadline_at, runner, parent_pid):
    _guard_parent(parent_pid)
    (runner or _child)(pipe, state, multi_agent, deadline_at)


def expired():
    return {'error': 'deadline_exceeded', 'retryable': True, 'error_detail': 'Discovery processing deadline expired'}


async def run_isolated(thread_id, source_id, state, multi_agent, deadline_at, identity=None, revision=0, runner=None):
    deadline_at = min(deadline_at, time.time() + 85)
    stop_at = time.monotonic() + max(0, deadline_at - time.time())
    if stop_at <= time.monotonic():
        return expired()
    fingerprint = hashlib.sha256(json.dumps([state, multi_agent], sort_keys=True, default=str).encode()).hexdigest()
    key = 'discovery:agent:' + hashlib.sha256(json.dumps([thread_id, identity or source_id or str(uuid.uuid4()), revision]).encode()).hexdigest()
    owner = str(uuid.uuid4())
    client = redis.from_url(settings.redis_url, decode_responses=True, socket_connect_timeout=1, socket_timeout=1)
    process = None
    acquired = False
    claimed = False
    parent = child = None
    result = expired()
    try:
        while time.monotonic() < stop_at:
            claim = await client.eval(_CLAIM, 1, key, fingerprint, owner, max(1, int(stop_at - time.monotonic()) + 15))
            if claim == 'conflict':
                return {'error': 'turn_identity_conflict', 'retryable': False}
            if claim == 'claimed':
                claimed = True
                break
            cached = await client.hget(key, 'result')
            if cached:
                return json.loads(cached) if time.monotonic() < stop_at else expired()
            await asyncio.sleep(min(.05, max(0, stop_at - time.monotonic())))
        if not claimed or time.monotonic() >= stop_at:
            return expired()
        try:
            await asyncio.wait_for(_slots.acquire(), timeout=max(.001, stop_at - time.monotonic()))
            acquired = True
        except asyncio.TimeoutError:
            return expired()
        if time.monotonic() >= stop_at:
            return expired()
        warm = _take_warm() if runner is None else None
        started = time.monotonic()
        if warm:
            process, job_sender, parent = warm
            job_sender.send((state, multi_agent, deadline_at))
            job_sender.close()
        else:
            context = multiprocessing.get_context('spawn')
            parent, child = context.Pipe(duplex=False)
            process = context.Process(target=_run_child, args=(child, state, multi_agent, deadline_at, runner, os.getpid()), daemon=True)
            process.start()
            child.close()
        while time.monotonic() < stop_at:
            if parent.poll():
                try:
                    candidate = parent.recv()
                except EOFError:
                    break
                if time.monotonic() < stop_at:
                    result = candidate
                break
            if not process.is_alive():
                break
            await asyncio.sleep(min(.02, max(0, stop_at - time.monotonic())))
        if time.monotonic() >= stop_at:
            result = expired()
        logging.getLogger('uvicorn.error').info('discovery turn worker=%s run=%.2fs error=%s',
            'warm' if warm else 'cold', time.monotonic() - started, result.get('error'))
        await client.eval(_FINISH, 1, key, owner, json.dumps(result), 'error' if result.get('error') else 'success')
        claimed = False
        return result
    except redis.RedisError:
        return {'error': 'agent_coordination_unavailable', 'retryable': True}
    finally:
        if process is not None:
            if process.is_alive():
                process.terminate()
            process.join(timeout=.2)
            if process.is_alive():
                process.kill()
                process.join(timeout=.2)
        if parent is not None:
            parent.close()
        if child is not None:
            child.close()
        if acquired:
            _slots.release()
        if claimed:
            try:
                await client.eval(_FINISH, 1, key, owner, '{}', 'error')
            except redis.RedisError:
                pass
        await client.aclose()
