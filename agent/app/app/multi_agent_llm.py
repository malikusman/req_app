"""The per-turn LLM call for the discovery interview.

One call does the whole turn: react to the employee's reply, extract an insight
and a reusable finding, report which dossier slots their answer supplied, park
anything interesting it isn't asking about, and ask the next question.

What to ask and when to stop is decided deterministically in app/orchestrator and
app/area_flow — the model only asks and reports.
"""

import json
import re
import time
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage

from app import dossier
from app.circuit_breaker import record_failure, record_success
from app.config import settings
from app.json_parse import LlmJsonParseError, extract_json_object
from app.llm import OpenAIUnavailable
from app.openai_factory import build_chat_openai, llm_configured
from app.orchestrator import needs_summary_refresh
from app.personas import ORIENT_PERSONA

# How many times a truncated reply may be retried with a doubled token cap.
MAX_TRUNCATION_RETRIES = 1

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

    # A cap that is too tight is worse than none: the reply is cut off mid-JSON,
    # which cannot parse, and re-asking at the same cap truncates identically. So the
    # cap escalates on truncation instead — one retry with real headroom recovers a
    # verbose turn rather than failing the interview over it.
    cap = settings.openai_max_tokens
    llm = build_chat_openai(temperature=0.4, json_mode=True, max_tokens=cap)

    last_error = None
    truncation_retries = 0
    for attempt in range(settings.max_openai_retries + 1):
        try:
            response = llm.invoke(messages)
            if _truncated(response):
                if truncation_retries < MAX_TRUNCATION_RETRIES:
                    truncation_retries += 1
                    cap *= 2
                    llm = build_chat_openai(temperature=0.4, json_mode=True, max_tokens=cap)
                    continue
                raise OpenAIUnavailable(
                    f"model reply was still cut off mid-JSON at max_tokens={cap}; "
                    "the prompt is asking for more output than the model will finish"
                )
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



def _truncated(response: Any) -> bool:
    """True when the provider stopped generation at the token cap."""
    meta = getattr(response, "response_metadata", None) or {}
    return meta.get("finish_reason") == "length"


def _parse_payload(content: str) -> dict[str, Any]:
    payload = extract_json_object(content)
    finding = payload.get("finding")
    if finding and not finding.get("content"):
        payload["finding"] = None
    return payload


def _context_blocks(state: dict[str, Any]) -> str:
    """Retrieval, knowledge and media context. These used to be assembled only for
    the retired specialist prompt, so the area flow silently ran without them."""
    blocks = []

    facts = state.get("memory_facts") or []
    if facts:
        lines = "\n".join(f"- {f.get('content')}" for f in facts[:3])
        blocks.append(
            "\nWhat colleagues at this company have already shared (NEVER name anyone, "
            f"paraphrase as 'some of your colleagues mentioned...'):\n{lines}\n"
        )

    snippets = state.get("document_snippets") or []
    if snippets:
        lines = "\n".join(f"- {s[:300]}" for s in snippets[:2])
        blocks.append(f"\nRelevant company document excerpts:\n{lines}\n")

    knowledge = state.get("knowledge_snippets") or []
    if knowledge:
        lines = "\n".join(f"- {s[:300]}" for s in knowledge[:5])
        blocks.append(f"\nCompany knowledge base (from document analysis):\n{lines}\n")

    media_ctx = state.get("media_context")
    if media_ctx:
        ctx_json = json.dumps(media_ctx, ensure_ascii=False)[:1500]
        confidence = media_ctx.get("confidence")
        conf_note = ""
        if confidence is not None and float(confidence) < 0.6:
            conf_note = (
                " Confidence is low — ask ONE clarifying question about what you see "
                "before assuming details.\n"
            )
        blocks.append(
            f"\n--- UNTRUSTED MEDIA CONTEXT (employee-sent {media_ctx.get('type', 'media')}) ---\n"
            f"{ctx_json}\n"
            "--- END UNTRUSTED MEDIA CONTEXT ---\n"
            "Reference screenshot or document content naturally (e.g. 'I can see in the image "
            "you sent...'). Do NOT quote raw JSON or mention internal field names.\n"
            f"{conf_note}"
        )

    media_snippets = state.get("media_snippets") or []
    if media_snippets:
        lines = "\n".join(f"- {s[:300]}" for s in media_snippets[:2])
        blocks.append(f"\nPrior media from this conversation (indexed excerpts):\n{lines}\n")

    return "".join(blocks)


def _asked_block(state: dict[str, Any]) -> str:
    """Explicit anti-repeat guard. Without a plain list of what it already asked,
    the model re-asks earlier questions by mid-interview."""
    asked = [
        (item.get("content") or "").strip()
        for item in (state.get("history") or [])
        if item.get("role") == "assistant" and (item.get("content") or "").strip()
    ]
    if not asked:
        return ""
    lines = "\n".join(f"- {q[:160]}" for q in asked[-8:])
    return (
        "\nQuestions you have ALREADY asked — do NOT ask any of these again, "
        f"even reworded or from a slightly different angle:\n{lines}\n"
    )


# Asked of every turn, whatever the beat. The brief's "keep it simple and easy to
# reply" is a hard constraint, not a tone note: a compound question gets a partial
# answer, which fills no slot and pushes the interview toward the stall exit.
QUESTION_SHAPE = """- ONE question, one clause. It must be answerable in a sentence.
- No compound questions — nothing with "and" joining two asks, no "if so, ...".
- Plain words. No jargon, no consulting vocabulary, nothing they'd have to decode.
- React to what they just said first, in a few natural words, THEN ask.
- Warm through your WORDS, not symbols — do NOT use emoji."""


def _build_system_prompt(state: dict[str, Any]) -> str:
    bb = state["blackboard"]
    profile = bb.get("profile") or {}
    language = state.get("preferred_language", "en")
    phase = state.get("phase")
    beat = state.get("beat") or {}
    limits = state.get("limits") or {}

    profile_block = (
        f"Employee: {profile.get('name') or 'unknown'} — {profile.get('role_title') or 'unknown role'}, "
        f"{(profile.get('seniority') or 'unknown').replace('_', ' ')}, "
        f"{profile.get('department') or 'unknown'}.\n"
        f"Responsibilities: {profile.get('responsibilities') or 'n/a'}\n"
        f"Tools: {', '.join(profile.get('primary_tools') or []) or 'n/a'}"
    )

    summary = bb.get("conversation_summary") or "(just getting started)"
    findings = bb.get("shared_findings") or []
    findings_block = "\n".join(f"- {f['finding']}" for f in findings[-5:]) or "(none yet)"
    known_areas = [a.get("name") for a in (bb.get("role_areas") or []) if a.get("name")]
    still_wanted = dossier.summary_for_prompt(bb, limits.get("slot_confidence", 0.6))

    summary_field = (
        '"refresh the running summary of the whole chat in 2-4 sentences"'
        if needs_summary_refresh(state)
        else "null"
    )

    if phase == "orient":
        persona = ORIENT_PERSONA
        task = (
            "Ask ONE short, friendly question that helps you learn the main areas their work "
            "breaks into — the concrete chunks of what they actually do. You're getting the lay "
            "of the land, not digging in yet.\n"
            f"Areas you've spotted so far: {', '.join(known_areas) or 'none yet'}.\n"
            "In role_areas, list the 2-3 main areas you can name so far (short labels), or [] "
            "if it's still unclear."
        )
        slot_hint = (
            "During orient just name the areas in role_areas — leave slots_filled empty "
            "unless their answer already told you how something works or where it snags."
        )
    else:
        persona = (
            "You're a warm, curious colleague chatting with someone about how their work really "
            "goes. You're genuinely interested and easy to talk to — never an interviewer, "
            "never pushy."
        )
        area = beat.get("area")
        scope = f'this ONE area of their work: "{area}"' if area else "their work generally"
        task = (
            f"Your question MUST be about {scope}.\n"
            f"Get curious specifically about {beat.get('intent', '')}.\n"
            "React warmly to their last answer first — and even if that answer drifted "
            f"elsewhere, gently steer back so THIS question is clearly about {scope}."
        )
        slot_hint = (
            f"You are asking for the '{beat.get('slot')}' slot"
            + (f" on area '{area}'" if area else "")
            + ". Report it in slots_filled when their answer supplies it."
        )

    return f"""{persona}

You're chatting one-to-one over WhatsApp with {profile.get('name') or 'this person'} to
understand how they really work at {state.get('company_name', 'the company')}. Warm, curious,
easy to talk to — never an interviewer running a script, never pushy.
{_company_profile_blurb(state)}
{profile_block}

Conversation so far (summary): {summary}

What you've learned already:
{findings_block}
{_context_blocks(state)}{_asked_block(state)}
Still to understand: {still_wanted}

Your job this turn:
{task}

How to ask:
{QUESTION_SHAPE}
- Speak in {language} (ISO 639-1). Don't switch unless they do.
- First turn (question_count is 0): a short warm hello plus one easy question that nods to
  their role. Never mention interviewers, agents, slots or handoffs.

Capturing what you learn:
- {slot_hint}
- slots_filled reports what THEIR ANSWER supplied, not what you asked. Confidence is how
  clearly they answered: 0.8+ if they were specific, 0.5 if vague, omit it entirely if they
  didn't really answer.
- If they mention something interesting that isn't what you asked about, put it in `parked`
  and move on. Do NOT chase it — breadth first. It gets picked up later.
- Set completed=true ONLY if they ask to stop. Do not end the chat because you think
  you have enough; that decision is made elsewhere.

Valid slot names: {', '.join(sorted(dossier.SLOT_INTENT.keys()))}

Respond with JSON only:
{{
  "assistant_message": "your next message to the employee",
  "insight": {{ "summary": "1-2 sentence insight from their last message", "topics": ["topic"] }},
  "finding": {{ "content": "one concrete reusable fact about how work happens here, or null", "confidence": 0.0 }},
  "slots_filled": [{{ "slot": "how_it_works", "area": "the area name or null", "value": "what they told you", "confidence": 0.0 }}],
  "parked": "an interesting aside to come back to later, or null",
  "role_areas": [],
  "updated_summary": {summary_field},
  "completed": false
}}"""


def _mock_agent_turn(state: dict[str, Any]) -> dict[str, Any]:
    """Deterministic turn for mock mode (no model configured). Fills the beat's slot
    so the dossier progresses and the flow's exit conditions can be exercised
    end-to-end without an LLM."""
    um = state.get("user_message", "")
    phase = state.get("phase")
    beat = state.get("beat") or {}

    if phase == "orient":
        return {
            "assistant_message": (
                "Nice to meet you! To get a feel for your day — what are the main things "
                "you find yourself working on?"
            ),
            "insight": {"summary": f"Employee said: {um[:160]}", "topics": ["daily_workflow"]},
            "finding": None,
            "slots_filled": [],
            "parked": None,
            "role_areas": _mock_areas_from(state),
            "updated_summary": None,
            "completed": False,
        }

    slot = beat.get("slot", "how_it_works")
    area = beat.get("area")
    question = {
        "how_it_works": f"How does {area or 'that'} usually get done day to day?",
        "friction": f"What's the most annoying part of {area or 'that'}?",
        "ai_openness": f"Ever thought about letting software take a slice of {area or 'that'} off your plate?",
        "ai_current_usage": "Do you use any AI tools in your day to day work at the moment?",
        "volume_or_frequency": f"Roughly how often does {area or 'that'} come up?",
    }.get(slot, f"Tell me a bit more about {area or 'your work'}?")

    return {
        "assistant_message": question,
        "insight": {"summary": f"Employee said: {um[:160]}", "topics": [slot]},
        "finding": ({"content": f"[{area or 'general'}] {um[:160]}", "confidence": 0.6} if len(um) > 20 else None),
        "slots_filled": [{"slot": slot, "area": area, "value": um[:200], "confidence": 0.8 if len(um) > 20 else 0.3}],
        "parked": None,
        "role_areas": [],
        "updated_summary": None,
        "completed": False,
    }


def _mock_areas_from(state: dict[str, Any]) -> list[str]:
    """Mock orientation names areas from the profile so branching has something real."""
    profile = (state.get("blackboard") or {}).get("profile") or {}
    resp = str(profile.get("responsibilities") or "")
    parts = [p.strip() for p in re.split(r"[,;/]|\band\b", resp) if p.strip()]
    return parts[:2] or (["their main work"] if not profile.get("role_title") else [str(profile["role_title"])])
