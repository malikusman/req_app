"""The talking half of a discovery turn: write what the interviewer says next.

The turn used to be one call that talked AND recorded, which let the structured
record degrade silently while the prose stayed good. Recording is now its own call
(app/interview_capture), run first; by the time this runs, the reply has been folded
into the dossier and area_flow has chosen the next topic from that fresh state.

So this call has one job — say the next thing well — and it returns plain text, not
JSON. That removes JSON parse failures from the part the employee actually sees, and
keeps the spoken reply short, which is what a voice interview needs.

What to ask and when to stop is still decided deterministically in app/orchestrator
and app/area_flow. The model only writes the words.
"""

import json
import re
import time
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage

from app import dossier
from app.circuit_breaker import record_failure, record_success
from app.config import settings
from app.llm import OpenAIUnavailable
from app.openai_factory import build_chat_openai, llm_configured, truncated as _truncated
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
    # Modern Standard Arabic, per the language rule: fus'ha is the default for Arabic.
    "ar": (
        "شكراً لك يا {name}! لدينا الآن ما نحتاجه من هذه المحادثة. "
        "يمكنك مراسلتي في أي وقت — بنصيحة أو أداة أو ملاحظة من يومك. "
        "وإن كان هناك ما تريد إضافته إلى مقابلتك، فقل \"add this to my interview\"."
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


def language_rule(language: str) -> str:
    """English by default; Modern Standard Arabic for Arabic speakers; a dialect only
    when the person is writing in that dialect themselves (Decision Register F4)."""
    first = "Arabic (Modern Standard Arabic)" if language == "ar" else (language or "en")
    return (
        "- Reply in the language they are writing in. English is the default.\n"
        "- If they write in Arabic, reply in Modern Standard Arabic (fus'ha). Switch to\n"
        "  Emirati or another dialect ONLY if they are writing in that dialect themselves.\n"
        "  System names, product codes and English business terms stay as they said them.\n"
        f"- For your very first message, before they have written anything, use: {first}."
    )


def write_question(state: dict[str, Any]) -> dict[str, Any]:
    """{assistant_message, fallback_reason}. Raises OpenAIUnavailable on an outage so
    Rails can send its delay notice and retry the whole turn."""
    if not llm_configured():
        return {"assistant_message": fallback_question(state), "fallback_reason": None}

    text = _talk(_build_talk_prompt(state), state)
    if text:
        return {"assistant_message": text, "fallback_reason": None}
    # Two empty replies in a row: ask the planned question in plain words rather than
    # stall the employee on a delay notice. The reason travels with the message.
    return {"assistant_message": fallback_question(state), "fallback_reason": "empty_reply"}


def write_farewell(state: dict[str, Any]) -> str:
    """They asked to stop. A short, warm goodbye — never a question, never pressure.
    Never raises: the employee has done their part, and failing loudly now helps nobody."""
    fallback = closing_message(state.get("preferred_language", "en"), state.get("employee_name", ""))
    if not llm_configured():
        return fallback
    prompt = (
        f"{_persona_line(state)}\n\nThey have just asked to stop the conversation. Reply in one "
        "or two short sentences: thank them warmly, say what they shared is genuinely useful, and "
        "tell them they can message again any time if something comes to mind. Do NOT ask a "
        "question. Do NOT try to persuade them to continue. No emoji.\n"
        f"{language_rule(state.get('preferred_language', 'en'))}\n\nWrite only your message."
    )
    try:
        return _talk(prompt, state) or fallback
    except OpenAIUnavailable:
        return fallback


def _talk(system_prompt: str, state: dict[str, Any]) -> str:
    messages = [SystemMessage(content=system_prompt)]
    # Wide enough that the model can still see the interview's opening questions by
    # Q7-8 (a 6-message window was a top cause of re-asking).
    for item in (state.get("history") or [])[-14:]:
        content = item.get("content", "")
        if item.get("role") == "assistant":
            messages.append(SystemMessage(content=f"[Interviewer]: {content}"))
        else:
            messages.append(HumanMessage(content=content))
    if state.get("user_message"):
        messages.append(HumanMessage(content=state["user_message"]))

    cap = settings.openai_max_tokens
    llm = build_chat_openai(temperature=0.4, json_mode=False, max_tokens=cap)
    last_error: Exception | None = None
    truncation_retries = 0
    empties = 0
    for attempt in range(settings.max_openai_retries + 1):
        try:
            response = llm.invoke(messages)
        except Exception as exc:  # noqa: BLE001 — transport / API failures
            last_error = exc
            record_failure()
            if attempt < settings.max_openai_retries:
                time.sleep(2**attempt)
                continue
            raise OpenAIUnavailable(str(exc)) from exc

        if _truncated(response) and truncation_retries < MAX_TRUNCATION_RETRIES:
            # Reasoning models spend the budget thinking before they write; re-asking
            # at the same cap truncates identically, so escalate instead.
            truncation_retries += 1
            cap *= 2
            llm = build_chat_openai(temperature=0.4, json_mode=False, max_tokens=cap)
            continue

        record_success()
        text = clean_reply(response.content)
        if text:
            return text
        empties += 1
        if empties >= 2:
            return ""
    if last_error:
        raise OpenAIUnavailable(str(last_error))
    return ""


def clean_reply(content: Any) -> str:
    """Strip what a model wraps around a plain reply: quotes, a speaker label, a JSON
    object when it forgets it was asked for text."""
    text = str(content or "").strip()
    if text.startswith("{"):
        try:
            parsed = json.loads(text)
            text = str(parsed.get("assistant_message") or parsed.get("message") or "").strip()
        except (ValueError, AttributeError):
            pass
    text = re.sub(r"^\s*\[?(interviewer|assistant|you)\]?\s*:\s*", "", text, flags=re.I)
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "\"'“”":
        text = text[1:-1].strip()
    return text[:1200]


def fallback_question(state: dict[str, Any]) -> str:
    """The planned question in plain words — used with no model, or when the model
    returns nothing twice. Deliberately simple; it is a safety net, not a style."""
    if state.get("phase") == "orient" or not state.get("beat"):
        if not state.get("question_count"):
            name = (state.get("employee_name") or "").split(" ")[0]
            return (f"Hi {name}! " if name else "Hi! ") + (
                "To get a feel for your day — what are the main things you find yourself working on?"
            )
        return "What are the main things your work breaks into, day to day?"
    beat = state["beat"]
    area = beat.get("area") or "that"
    return {
        "how_it_works": f"How does {area} usually get done, day to day?",
        "friction": f"What's the most frustrating part of {area}?",
        "friction_cost": "Roughly how much of your time does that take up in a typical week?",
        "ai_current_usage": "Do you use any AI tools in your day-to-day work at the moment?",
        "role_potential": (
            "If some of the routine parts of your job took care of themselves, "
            "what would you spend that time on?"
        ),
    }.get(beat.get("slot"), f"Could you tell me a bit more about {area}?")

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


def _persona_line(state: dict[str, Any]) -> str:
    profile = (state.get("blackboard") or {}).get("profile") or {}
    return (
        f"You're chatting one-to-one with {profile.get('name') or 'someone'} to understand how "
        f"they really work at {state.get('company_name', 'the company')}. Warm, curious, easy to "
        "talk to — never an interviewer running a script, never pushy."
    )


def _build_talk_prompt(state: dict[str, Any]) -> str:
    bb = state["blackboard"]
    profile = bb.get("profile") or {}
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
    known_areas = dossier.area_names(bb)
    still_wanted = dossier.summary_for_prompt(bb, limits.get("slot_confidence", 0.6))

    if phase == "orient":
        persona = ORIENT_PERSONA
        task = (
            "Ask ONE short, friendly question that helps you learn the main areas their work "
            "breaks into — the concrete chunks of what they actually do. You're getting the lay "
            "of the land, not digging in yet.\n"
            f"Areas you've spotted so far: {', '.join(known_areas) or 'none yet'}."
        )
    else:
        persona = (
            "You're a warm, curious colleague chatting with someone about how their work really "
            "goes. Genuinely interested and easy to talk to — never an interviewer, never pushy."
        )
        area = beat.get("area")
        scope = f'this ONE area of their work: "{area}"' if area else "their work generally"
        task = (
            f"Your question MUST be about {scope}.\n"
            f"Get curious specifically about {beat.get('intent', '')}.\n"
            "React warmly to their last answer first — and even if it drifted elsewhere, gently "
            f"steer back so THIS question is clearly about {scope}."
        )

    return f"""{persona}

{_persona_line(state)}
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
- First message (question_count is {state.get('question_count', 0)}; 0 means first): a short
  warm hello plus one easy question that nods to their role.
- Never mention interviewers, agents, slots, reports, consultants or assessments.
- Never suggest their work could be automated, replaced or handled by AI or software, and
  never ask them to design a solution. You are only trying to understand the work.
- Never judge — no "that sounds inefficient". A few neutral words, then the question.

If they asked YOU something, answer it briefly and honestly first, then ask your question:
- Whether this is about their performance, or whether they are being assessed: no — it is
  about understanding the work and the tools, and there are no right or wrong answers.
- Whether it will cost jobs: be calm and honest — the purpose is to understand the work so
  it can be made easier; you can't speak for the company's decisions, and their management
  is the right place to ask. Never promise anything about jobs.
- Who sees their answers: individual answers aren't shared with colleagues, and what comes
  out of this describes how work is done, not people.
- What AI could do for them: that's something the company will look at once the work is
  properly understood, which is what this conversation is for. Suggest nothing.
- If they want a break: of course — they can pick it up again any time.

Language:
{language_rule(state.get('preferred_language', 'en'))}

Write ONLY the message you will send them — no labels, no quotation marks, no JSON."""
