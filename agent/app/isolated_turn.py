"""Redis-coordinated discovery execution with a killable, bounded local worker."""
import asyncio
import hashlib
import json
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


def _run_child(pipe, state, multi_agent, deadline_at, runner, parent_pid):
    # A crashed Uvicorn worker must not leave an orphaned model computation.
    if sys.platform == 'linux':
        import ctypes
        ctypes.CDLL(None).prctl(1, signal.SIGKILL)
        if os.getppid() != parent_pid:
            os.kill(os.getpid(), signal.SIGKILL)
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
