"""Bound turn execution and reuse a completed result after a caller times out."""
import copy
import logging
import threading
import time
from collections import OrderedDict
from contextvars import ContextVar

_deadline = ContextVar("discovery_deadline", default=None)
_guard = threading.Lock()
_entries = {}
_results = OrderedDict()


def invoke(model, messages, stage="model"):
    started = time.monotonic()
    deadline = _deadline.get()
    remaining = deadline - time.monotonic() if deadline else 70.0
    if remaining <= 0:
        raise TimeoutError("Discovery turn processing budget exhausted")
    try:
        result = model.invoke(messages, timeout=min(70.0, remaining))
        if deadline and time.monotonic() >= deadline:
            raise TimeoutError("Discovery turn processing budget exhausted")
        return result
    finally:
        logging.getLogger("uvicorn.error").info("discovery model stage=%s duration=%.2fs prompt_chars=%s",
            stage, time.monotonic() - started, sum(len(str(m.content)) for m in messages))


def run_turn_once(thread_id, source_id, execute):
    # Requests without source identity retain the legacy behavior.
    deadline = time.monotonic() + 85.0
    key = (thread_id, source_id) if source_id is not None else object()
    with _guard:
        entry = _entries.setdefault(key, {"lock": threading.Lock(), "users": 0})
        entry["users"] += 1
    try:
        acquired = entry["lock"].acquire(timeout=max(0, deadline - time.monotonic()))
        if not acquired:
            raise TimeoutError("Discovery turn lock deadline expired")
        try:
            with _guard:
                if key in _results:
                    return copy.deepcopy(_results[key])
            token = _deadline.set(deadline)
            try:
                result = execute()
                if time.monotonic() >= deadline:
                    raise TimeoutError("Discovery turn processing budget exhausted")
            finally:
                _deadline.reset(token)
            if not result.get("error") and source_id is not None:
                with _guard:
                    _results[key] = copy.deepcopy(result)
                    while len(_results) > 256:
                        _results.popitem(last=False)
            return result
        finally:
            entry["lock"].release()
    finally:
        with _guard:
            entry["users"] -= 1
            if not entry["users"]:
                _entries.pop(key, None)
