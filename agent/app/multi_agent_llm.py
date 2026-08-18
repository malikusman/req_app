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

from app.circuit_breaker import record_failure, record_success
from app.config import settings
from app.json_parse import LlmJsonParseError, extract_json_object
from app.llm import OpenAIUnavailable
from app.openai_factory import build_chat_openai, llm_configured
from app.orchestrator import needs_summary_refresh
from app.personas import ORIENT_PERSONA, mock_question_for, persona_for

CLOSING_MESSAGES = {
    "en": (
        "Thank you, {name}! We've got what we need for the discovery interview. "
        "You can keep messaging me anytime — tips, tools, or notes from your day. "
        "If something should count for the company report, say \"add this to my interview\"."
    ),
    "es": (
        "¡Gracias, {name}! Ya tenemos lo necesario de la entrevista. "
        "Puedes escribirme cuando quieras — tips, herramientas o notas del día. "
        "Si debe contar para el reporte, di \"add this to my interview\"."
    ),
    "fr": (
        "Merci, {name} ! Nous avons ce qu'il faut pour l'entretien. "
        "Écrivez-moi quand vous voulez — conseils, outils ou notes du jour. "
        "Pour le rapport, dites \"add this to my interview\"."
    ),
    "de": (
        "Danke, {name}! Fürs Discovery-Interview haben wir alles. "
        "Schreib mir jederzeit — Tipps, Tools oder Notizen aus deinem Tag. "
        "Für den Report sag \"add this to my interview\"."
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
    sub = profile.get("sub_industry")
    revenue = profile.get("annual_revenue_band")
    depts = profile.get("org_departments")
    website = state.get("website_url") or profile.get("website_url")
    systems = (
        state.get("known_systems")
        or profile.get("known_systems")
        or [s.get("name") for s in (profile.get("client_stack") or []) if isinstance(s, dict)]
    )
    bits = []
    if industry:
        bits.append(f"industry={industry}")
    if sub:
        bits.append(f"sub_industry={sub}")
    if size:
        bits.append(f"size={size}")
    if region:
        bits.append(f"region={region}")
    if revenue:
        bits.append(f"revenue_band={revenue}")
    if goals:
        goal_text = ", ".join(goals) if isinstance(goals, list) else str(goals)
        if goal_text.strip():
            bits.append(f"goals={goal_text[:160]}")
    if depts:
        dept_text = ", ".join(depts) if isinstance(depts, list) else str(depts)
        if dept_text.strip():
            bits.append(f"departments={dept_text[:120]}")
    if website:
        bits.append(f"website={website}")
    if systems:
        sys_text = ", ".join(str(s) for s in systems[:12])
        if sys_text.strip():
            bits.append(f"systems_in_use={sys_text[:160]}")
    if not bits:
        return ""
    return (
        "Company profile context (use to tailor questions; do not recite unless useful): "
        + "; ".join(bits)
        + ".\n"
    )


def run_agent_turn(state: dict[str, Any]) -> dict[str, Any]:
    """Returns the structured llm_output consumed by orchestrator.finalize_turn."""
    if not llm_configured():
        return _mock_agent_turn(state)

    system = _build_system_prompt(state)
    messages = [SystemMessage(content=system)]
    # Wider raw window so the model can still see the interview's opening questions
    # by Q7-8 (the truncated 6-message window was a top cause of re-asking).
    for item in (state.get("history") or [])[-14:]:
        role = item.get("role", "user")
        content = item.get("content", "")
        if role == "assistant":
            messages.append(SystemMessage(content=f"[Interviewer]: {content}"))
        else:
            messages.append(HumanMessage(content=content))
    messages.append(HumanMessage(content=state["user_message"]))

    llm = build_chat_openai(temperature=0.4, json_mode=True)

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
    # Phase 3: orient/branch prompt when area routing drove this turn.
    if state.get("area_routing") and state.get("area_decision"):
        return _build_area_prompt(state, state["area_decision"])

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

    knowledge = state.get("knowledge_snippets") or []
    knowledge_block = ""
    if knowledge:
        lines = "\n".join(f"- {s[:300]}" for s in knowledge[:5])
        knowledge_block = f"\nCompany knowledge base (from document analysis):\n{lines}\n"

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
            f"Their last answer about '{state['followup_topic']}' could use ONE quick follow-up "
            "ONLY if it was genuinely vague or hinted at something interesting. If they already "
            "answered it clearly, don't linger — get curious about a different part of their work."
        )
    else:
        followup_instruction = (
            "Move on to a fresh part of their work you haven't really touched yet — "
            "don't circle back to something already covered."
        )

    # Explicit anti-repeat guard: the model never saw a list of what it already asked,
    # so by mid-interview it re-asked earlier questions. List them plainly.
    asked = [
        (item.get("content") or "").strip()
        for item in (state.get("history") or [])
        if item.get("role") == "assistant" and (item.get("content") or "").strip()
    ]
    asked_block = ""
    if asked:
        lines = "\n".join(f"- {q[:160]}" for q in asked[-8:])
        asked_block = (
            "\nQuestions you have ALREADY asked — do NOT ask any of these again, "
            f"even reworded or from a slightly different angle:\n{lines}\n"
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

You're chatting one-to-one over WhatsApp with {profile.get('name') or 'this person'} to
understand how they really work at {state.get('company_name', 'the company')}. You come across
as a warm, curious colleague who's genuinely interested in their day — not an interviewer
running a script, and never pushy.
{_company_profile_blurb(state)}

{profile_block}

Conversation so far (summary): {summary}

Findings shared so far:
{findings_block}
{facts_block}{snippets_block}{knowledge_block}{media_block}{media_snippets_block}{asked_block}
Where things stand:
- Questions asked so far: {state.get('question_count', 0)} of {state.get('question_target', 12)} max.
- Topics not yet explored: {', '.join(uncovered) or 'the basics are covered — now go a level deeper on what THEY found painful or interesting, not generic ground'}.
- {followup_instruction}

How to talk:
- Speak in {language} (ISO 639-1). Don't switch unless they do.
- React to what they just said first — a quick, human acknowledgement ("oh nice", "yeah that
  sounds fiddly") — THEN ask ONE short, easy question. It should feel like a friendly chat, not a form.
- When your curiosity moves to a new part of their work, glide in naturally
  ("gotcha — and totally different thing...").
- Every so often, when it fits the flow, get lightly curious about whether they've ever thought
  about letting software or AI take a boring slice of this off their plate, and what they'd try —
  ask it out of genuine interest, never as a pitch.
- First turn (question_count is 0): a short, warm hello + one easy question that nods to their
  role. Never mention interviewers, agents, or handoffs.
- One question at a time. Keep it human and specific; no jargon, no interrogation.
- Set completed=true ONLY if the chat should end now (they asked to stop, or everything's genuinely covered).

Respond with JSON only:
{{
  "assistant_message": "your next message to the employee",
  "insight": {{ "summary": "1-2 sentence insight from the employee's last message", "topics": ["topic"] }},
  "finding": {{ "content": "one concrete reusable fact about how work happens at this company, or null", "confidence": 0.0 }},
  "followup": {{ "needed": false, "topic": "the single topic their LAST answer was mainly about (so a follow-up, if any, deepens THAT)" }},
  "topics_covered": ["daily_workflow"],
  "updated_summary": {summary_field},
  "completed": false
}}"""


def _build_area_prompt(state: dict[str, Any], decision: dict[str, Any]) -> str:
    """Companion-voiced prompt for the map-then-branch flow: orient asks a light
    question and names the person's areas; branch asks one beat about one area."""
    bb = state["blackboard"]
    profile = bb.get("profile") or {}
    language = state.get("preferred_language", "en")
    phase = decision.get("phase")

    profile_block = (
        f"Employee: {profile.get('name') or 'unknown'} — {profile.get('role_title') or 'unknown role'}, "
        f"{(profile.get('seniority') or 'unknown').replace('_', ' ')}, {profile.get('department') or 'unknown'}.\n"
        f"Responsibilities: {profile.get('responsibilities') or 'n/a'}\n"
        f"Tools: {', '.join(profile.get('primary_tools') or []) or 'n/a'}"
    )
    summary = bb.get("conversation_summary") or "(just getting started)"

    asked = [
        (item.get("content") or "").strip()
        for item in (state.get("history") or [])
        if item.get("role") == "assistant" and (item.get("content") or "").strip()
    ]
    asked_block = ""
    if asked:
        lines = "\n".join(f"- {q[:160]}" for q in asked[-8:])
        asked_block = f"\nQuestions already asked — do NOT repeat any of these, even reworded:\n{lines}\n"

    summary_field = (
        '"refresh the running summary of the whole chat in 2-4 sentences"'
        if needs_summary_refresh(state)
        else "null"
    )
    known_areas = [a.get("name") for a in (bb.get("role_areas") or []) if a.get("name")]

    if phase == "orient":
        persona = ORIENT_PERSONA
        task = (
            "Ask ONE short, friendly question that helps you learn the main areas their work "
            "breaks into (the concrete chunks of what they actually do). React warmly to what they "
            "just said first. Don't dig deep yet — you're just getting the lay of the land.\n"
            f"Areas you've spotted so far: {', '.join(known_areas) or 'none yet'}. "
            "In role_areas, list the 2-3 main areas you can name so far (short labels), or [] if unclear."
        )
    else:  # branch
        persona = (
            "You're a warm, curious colleague chatting with someone about how their work really "
            "goes. You're genuinely interested and easy to talk to — never an interviewer, never pushy."
        )
        area = decision.get("current_area", "their work")
        beat_intent = decision.get("beat_intent", "")
        task = (
            f"Focus this question on ONE area of their work: \"{area}\".\n"
            f"Get curious specifically about {beat_intent}.\n"
            "React warmly to their last answer first, then ask ONE easy, specific question. "
            "Keep it light and human — a friend chatting, not a form. Leave role_areas as []."
        )

    return f"""{persona}

You're chatting one-to-one over WhatsApp with {profile.get('name') or 'this person'} to
understand how they really work at {state.get('company_name', 'the company')}. Warm, curious,
easy to talk to — never an interviewer running a script, never pushy.

{profile_block}

Conversation so far (summary): {summary}
{asked_block}
Your job this turn:
{task}

Rules:
- Speak in {language} (ISO 639-1); don't switch unless they do.
- ONE question only. Acknowledge what they said, then ask. No jargon, no interrogation.
- First turn (question_count is 0): a short warm hello + one easy question about their day.
- Never mention interviewers, agents, areas, or that anything is being tracked.
- Set completed=true ONLY if they ask to stop.

Respond with JSON only:
{{
  "assistant_message": "your next message to the employee",
  "insight": {{ "summary": "1-2 sentence insight from their last message", "topics": ["topic"] }},
  "finding": {{ "content": "one concrete reusable fact about how work happens here, or null", "confidence": 0.0 }},
  "role_areas": ["short area label", "..."],
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


def _mock_area_turn(state: dict[str, Any], decision: dict[str, Any]) -> dict[str, Any]:
    """Deterministic mock for the area flow (no LLM configured)."""
    um = state.get("user_message", "")
    if decision.get("phase") == "orient":
        return {
            "assistant_message": "Nice to meet you! To get a feel for your day, what are the main things you find yourself working on?",
            "insight": {"summary": f"Employee said: {um[:160]}", "topics": ["daily_workflow"]},
            "finding": None,
            "role_areas": [p.strip() for p in (state.get("blackboard", {}).get("profile", {}).get("responsibilities") or "").split(",") if p.strip()][:3],
            "topics_covered": ["daily_workflow"],
            "updated_summary": None,
            "completed": False,
        }
    area = decision.get("current_area", "your work")
    beat = decision.get("current_beat", "how")
    qbeat = {"how": f"Walk me through how {area} usually works — what do you use for it?",
             "pain": f"What's the most annoying part of {area}?",
             "ai": f"Have you ever thought about letting software or AI take a slice of {area} off your plate?"}
    return {
        "assistant_message": qbeat.get(beat, qbeat["how"]),
        "insight": {"summary": f"Employee said: {um[:160]}", "topics": [beat]},
        "finding": ({"content": f"[{area}] {um[:160]}", "confidence": 0.6} if len(um) > 20 else None),
        "role_areas": [],
        "topics_covered": ["daily_workflow"],
        "updated_summary": None,
        "completed": False,
    }


def _mock_agent_turn(state: dict[str, Any]) -> dict[str, Any]:
    """Deterministic multi-agent mock: each agent asks its canned questions in turn."""
    if state.get("area_routing") and state.get("area_decision"):
        return _mock_area_turn(state, state["area_decision"])
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
