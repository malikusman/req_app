import os
import time
import redis


def success(pipe, state, multi_agent, deadline_at):
    client = redis.from_url(state['redis_url'])
    client.incr(state['counter'])
    time.sleep(state.get('sleep', .1))
    pipe.send({'assistant_message': 'Next question?', 'question_count': 1, 'completed': False})
    pipe.close()


def forever(pipe, state, multi_agent, deadline_at):
    if state.get('pid_key'):
        redis.from_url(state['redis_url']).set(state['pid_key'], os.getpid(), ex=60)
    while True:
        time.sleep(.05)
