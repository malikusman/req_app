"""The per-turn LLM call for the multi-agent system.

One call does the active agent's full job: assess the employee's reply,
extract an insight + structured finding, decide whether a follow-up is needed,
ask the next question in the agent's voice, mark covered topics, and refresh
the rolling conversation summary when due.
"""

import json
import time
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI

from app.circuit_breaker import record_failure, record_success
from app.config import settings
from app.json_parse import LlmJsonParseError, extract_json_object
from app.llm import OpenAIUnavailable
from app.orchestrator import needs_summary_refresh
from app.personas import mock_question_for, persona_for

CLOSING_MESSAGES = {
    "en": (
        "Thank you, {name}! We've got what we need for now — but if anything else comes to mind, "
        "just message me anytime and I'll add it."
    ),
    "es": (
        "¡Gracias, {name}! Por ahora tenemos lo que necesitamos — si se te ocurre algo más, "
        "escríbeme cuando quieras y lo añadiré."
    ),
    "fr": (
        "Merci, {name} ! Nous avons ce qu'il nous faut pour le moment — si autre chose vous vient "
        "à l'esprit, écrivez-moi à tout moment et je l'ajouterai."
    ),
    "de": (
        "Danke, {name}! Fürs Erste haben wir alles — fällt Ihnen später noch etwas ein, "
        "schreiben Sie mir jederzeit und ich ergänze es."
    ),
}


def closing_message(language: str, employee_name: str) -> str:
    template = CLOSING_MESSAGES.get(language, CLOSING_MESSAGES["en"])
    return template.format(name=employee_name or "there")


def _company_profile_blurb(state: dict[str, Any]) -> str:
    profile = state.get("company_profile") or {}
    industry = state.get("industry") or profile.get("industry")
    size = state.get("size_band") or profile.get("size_band")
    region = state.get("region") or profile.get("region") or profile.get("country")
    goals = state.get("business_goals") or profile.get("business_goals")
    bits = []
    if industry:
        bits.append(f"industry={industry}")
    if size:
        bits.append(f"size={size}")
    if region:
        bits.append(f"region={region}")
    if goals:
        goal_text = ", ".join(goals) if isinstance(goals, list) else str(goals)
        if goal_text.strip():
            bits.append(f"goals={goal_text[:160]}")
    if not bits:
        return ""
    return (
        "Company profile context (use to tailor questions; do not recite unless useful): "
        + "; ".join(bits)
        + ".\n"
    )


def run_agent_turn(state: dict[str, Any]) -> dict[str, Any]:
    """Returns the structured llm_output consumed by orchestrator.finalize_turn."""
    if not settings.openai_api_key:
        return _mock_agent_turn(state)

    system = _build_system_prompt(state)
    messages = [SystemMessage(content=system)]
    for item in (state.get("history") or [])[-6:]:
        role = item.get("role", "user")
        content = item.get("content", "")
        if role == "assistant":
            messages.append(SystemMessage(content=f"[Interviewer]: {content}"))
        else:
            messages.append(HumanMessage(content=content))
    messages.append(HumanMessage(content=state["user_message"]))

    llm = ChatOpenAI(
        model=settings.openai_model,
        api_key=settings.openai_api_key,
        temperature=0.4,
        model_kwargs={"response_format": {"type": "json_object"}},
    )

    last_error = None
    for attempt in range(settings.max_openai_retries + 1):
        try:
            response = llm.invoke(messages)
            try:
                payload = _parse_payload(response.content)
            except LlmJsonParseError as parse_exc:
                # One reformat retry — do not trip the breaker on the first bad JSON.
                reformat = messages + [
                    HumanMessage(
                        content=(
                            "Your previous reply was not valid JSON. "
                            "Reply again with a single JSON object only, matching the schema."
                        )
                    )
                ]
                response = llm.invoke(reformat)
                try:
                    payload = _parse_payload(response.content)
                except LlmJsonParseError:
                    last_error = parse_exc
                    record_failure()
                    if attempt < settings.max_openai_retries:
                        time.sleep(2**attempt)
                        continue
                    raise OpenAIUnavailable(str(parse_exc)) from parse_exc
            record_success()
            return payload
        except OpenAIUnavailable:
            raise
        except Exception as exc:  # noqa: BLE001 — transport / API failures
            last_error = exc
            record_failure()
            if attempt < settings.max_openai_retries:
                time.sleep(2**attempt)

    raise OpenAIUnavailable(str(last_error))


def _build_system_prompt(state: dict[str, Any]) -> str:
    bb = state["blackboard"]
    profile = bb.get("profile") or {}
    agent_id = state["active_agent_id"]
    agent_state = bb.get("agent_states", {}).get(agent_id, {})
    coverage = bb.get("coverage", {})
    limits = state.get("limits", {})
    language = state.get("preferred_language", "en")

    persona = persona_for(agent_id, state.get("department", ""), state.get("playbook_block", ""))

    profile_block = (
        f"Employee profile: {profile.get('name') or 'unknown'} — "
        f"{profile.get('role_title') or 'unknown role'}, "
        f"{(profile.get('seniority') or 'unknown seniority').replace('_', ' ')}, "
        f"department: {profile.get('department') or 'unknown'}.\n"
        f"Responsibilities: {profile.get('responsibilities') or 'n/a'}\n"
        f"Tools: {', '.join(profile.get('primary_tools') or []) or 'n/a'}"
    )

    summary = bb.get("conversation_summary") or "(interview just started)"

    findings = bb.get("shared_findings") or []
    findings_block = (
        "\n".join(f"- [{f['agent']}] {f['finding']}" for f in findings[-5:]) or "(none yet)"
    )

    facts = state.get("memory_facts") or []
    facts_block = ""
    if facts:
        lines = "\n".join(f"- {f.get('content')}" for f in facts[:3])
        facts_block = (
            "\nWhat colleagues at this company have already shared (NEVER name anyone, "
            f"paraphrase as 'some of your colleagues mentioned...'):\n{lines}\n"
        )

    snippets = state.get("document_snippets") or []
    snippets_block = ""
    if snippets:
        lines = "\n".join(f"- {s[:300]}" for s in snippets[:2])
        snippets_block = f"\nRelevant company document excerpts:\n{lines}\n"

    media_ctx = state.get("media_context")
    media_block = ""
    if media_ctx:
        ctx_json = json.dumps(media_ctx, ensure_ascii=False)[:1500]
        confidence = media_ctx.get("confidence")
        conf_note = ""
        if confidence is not None and float(confidence) < 0.6:
            conf_note = (
                " Confidence is low — ask ONE clarifying question about what you see "
                "before assuming details.\n"
            )
        media_block = (
            f"\n--- UNTRUSTED MEDIA CONTEXT (employee-sent {media_ctx.get('type', 'media')}) ---\n"
            f"{ctx_json}\n"
            f"--- END UNTRUSTED MEDIA CONTEXT ---\n"
            "Reference screenshot or document content naturally (e.g. 'I can see in the image you sent...'). "
            "Do NOT quote raw JSON or mention internal field names.\n"
            f"{conf_note}"
        )

    media_snippets = state.get("media_snippets") or []
    media_snippets_block = ""
    if media_snippets:
        lines = "\n".join(f"- {s[:300]}" for s in media_snippets[:2])
        media_snippets_block = f"\nPrior media from this conversation (indexed excerpts):\n{lines}\n"

    if state.get("followup_allowed") and state.get("followup_topic"):
        followup_instruction = (
            f"The open topic '{state['followup_topic']}' may still need ONE clarifying follow-up. "
            "Ask a follow-up ONLY if the employee's last answer was vague or opened something valuable; "
            "otherwise move to a new topic."
        )
    else:
        followup_instruction = (
            "You may NOT ask another follow-up on a previously explored topic "
            "(depth limit reached). Move to a new topic within your focus area."
        )

    remaining = agent_state.get("question_budget", 0) - agent_state.get("questions_asked", 0)
    uncovered = [
        t
        for t in coverage.get("topics_required", [])
        if t not in coverage.get("topics_covered", [])
    ]

    summary_field = (
        '"refresh the running summary of the whole interview in 2-4 sentences"'
        if needs_summary_refresh(state)
        else "null"
    )

    return f"""{persona}

You are one of several specialist interviewers collaborating on a workflow discovery
interview over WhatsApp for {state.get('company_name', 'the company')}.
{_company_profile_blurb(state)}

{profile_block}

Conversation so far (summary): {summary}

Findings shared by all interviewers so far:
{findings_block}
{facts_block}{snippets_block}{media_block}{media_snippets_block}
Interview state:
- Total questions asked: {state.get('question_count', 0)} of {state.get('question_target', 12)} max.
- Your remaining question budget: {remaining}.
- Coverage topics still missing: {', '.join(uncovered) or 'all covered'}.
- {followup_instruction}

Rules:
- Conduct the conversation in {language} (ISO 639-1). Do not switch unless the employee does.
- Ask ONE concise question, in a natural conversational voice. If you are taking over
  from another interviewer after the first turn, transition smoothly (e.g. "Thanks — I'd also like to understand...").
- On the first turn of the interview (question_count is 0), open with a brief welcome and one discovery question — reference their role or context if provided; never mention handoffs or other interviewers.
- Never reveal that multiple agents/interviewers exist.
- Set completed=true ONLY if the interview should end now (employee asked to stop,
  or everything is genuinely covered).

Respond with JSON only:
{{
  "assistant_message": "your next message to the employee",
  "insight": {{ "summary": "1-2 sentence insight from the employee's last message", "topics": ["topic"] }},
  "finding": {{ "content": "one concrete reusable fact about how work happens at this company, or null", "confidence": 0.0 }},
  "followup": {{ "needed": false, "topic": "topic of the question you are now asking" }},
  "topics_covered": ["daily_workflow"],
  "updated_summary": {summary_field},
  "completed": false
}}"""


def _parse_payload(content: str) -> dict[str, Any]:
    payload = extract_json_object(content)
    finding = payload.get("finding")
    if finding and not finding.get("content"):
        payload["finding"] = None
    return payload


def _mock_agent_turn(state: dict[str, Any]) -> dict[str, Any]:
    """Deterministic multi-agent mock: each agent asks its canned questions in turn."""
    bb = state["blackboard"]
    agent_id = state["active_agent_id"]
    agent_state = bb.get("agent_states", {}).get(agent_id, {})
    index = agent_state.get("questions_asked", 0)
    user_message = state.get("user_message", "")

    question = mock_question_for(agent_id, index)

    coverage_rotation = ["daily_workflow", "tools", "pain_points", "handoffs", "approvals"]
    topic = coverage_rotation[state.get("question_count", 0) % len(coverage_rotation)]

    output: dict[str, Any] = {
        "assistant_message": question,
        "insight": {
            "summary": f"Employee mentioned: {user_message[:200]}",
            "topics": [topic],
        },
        "finding": (
            {
                "content": f"[{agent_id}] {user_message[:160]}",
                "confidence": 0.7 if len(user_message) > 60 else 0.5,
            }
            if len(user_message) > 20
            else None
        ),
        "followup": {"needed": False, "topic": topic},
        "topics_covered": [topic],
        "updated_summary": None,
        "completed": False,
    }

    if needs_summary_refresh(state):
        existing = bb.get("conversation_summary") or ""
        output["updated_summary"] = (existing + f" Turn {state.get('question_count', 0) + 1}: {user_message[:80]}").strip()[:600]

    return output
