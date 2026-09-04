"""Test defaults for the agent suite.

`Settings` is instantiated at import time, so an ambient OPENAI_API_KEY or
OPENAI_BASE_URL cannot be cleared once the module is loaded. Without this fixture
the fallback tests silently changed meaning depending on the environment: on a
machine configured for local Gemma they took the LLM path instead of the
deterministic one, made real model calls, and failed — a 33-minute run.

So no-model is the default here, and a test that wants the model path opts in with
`@pytest.mark.usefixtures("with_model")`. Tests then assert what they claim to,
whatever the machine is set up for.
"""

import pytest

# Modules that import llm_configured into their own namespace, so each needs its own
# patch target.
MODULES_USING_LLM_SWITCH = (
    "app.package",
    "app.requirements",
    "app.multi_agent_llm",
    # Omitting this cost a real 33s model call the moment companion tests existed:
    # llm_configured() was true on a machine set up for local Gemma, so the
    # no-model test took the model path and asserted against a live reply.
    "app.companion",
)


@pytest.fixture(autouse=True)
def no_model(monkeypatch):
    for module in MODULES_USING_LLM_SWITCH:
        try:
            monkeypatch.setattr(f"{module}.llm_configured", lambda: False)
        except AttributeError:
            # Module does not use the switch — nothing to neutralise.
            pass


@pytest.fixture
def with_model(monkeypatch):
    """Opt back in to the model path (with the call itself still stubbed by the test)."""
    for module in MODULES_USING_LLM_SWITCH:
        try:
            monkeypatch.setattr(f"{module}.llm_configured", lambda: True)
        except AttributeError:
            pass
