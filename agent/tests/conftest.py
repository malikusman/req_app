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
    "app.employee_discovery_v2",
    "app.package",
    "app.requirements",
    "app.multi_agent_llm",
    # Omitting this cost a real 33s model call the moment companion tests existed:
    # llm_configured() was true on a machine set up for local Gemma, so the
    # no-model test took the model path and asserted against a live reply.
    "app.companion",
    # And again, identically, the moment deep-dive tests existed — the suite hung
    # for minutes making real Gemma calls. Any new module that imports
    # llm_configured belongs on this list on the same commit that adds it.
    "app.deep_dive",
    # The recording half of a discovery turn, added when the turn was split.
    "app.interview_capture",
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


@pytest.fixture(autouse=True)
def builtin_interviewer_instructions(monkeypatch, tmp_path):
    """Engine tests assert the built-in wording; the operator's instructions file
    (app/interviewer/instructions.yaml) must not change what they check. Tests of
    the configurable instructions point INTERVIEWER_INSTRUCTIONS_PATH at their own file."""
    monkeypatch.setenv("INTERVIEWER_INSTRUCTIONS_PATH", str(tmp_path / "no-interviewer-instructions.yaml"))
