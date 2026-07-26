import time
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage

from app.circuit_breaker import record_failure, record_success
from app.config import settings
from app.json_parse import LlmJsonParseError, extract_json_object
from app.openai_factory import build_chat_openai, llm_configured


class OpenAIUnavailable(Exception):
    pass


MOCK_QUESTIONS = {
    "en": [
        "What are the first three tasks you typically do when you start your workday?",
        "Which tools or systems do you use most often for those tasks?",
        "Where do you spend the most time waiting on someone or something else?",
        "What repetitive work would you automate if you could?",
        "How do you hand off work to teammates or other departments?",
        "What information is hardest to find when you need it?",
        "Describe a recent situation where a process broke down.",
        "What approvals or sign-offs slow you down?",
        "Which meetings or check-ins feel most valuable vs. wasteful?",
        "If you could fix one workflow this quarter, what would it be?",
    ],
    "es": [
        "¿Cuáles son las primeras tres tareas que haces al empezar tu jornada?",
        "¿Qué herramientas o sistemas usas con más frecuencia?",
        "¿Dónde pasas más tiempo esperando a alguien o algo?",
        "¿Qué trabajo repetitivo automatizarías si pudieras?",
        "¿Cómo entregas trabajo a compañeros u otros departamentos?",
        "¿Qué información es más difícil de encontrar cuando la necesitas?",
        "Describe una situación reciente donde un proceso falló.",
        "¿Qué aprobaciones te frenan más?",
        "¿Qué reuniones te parecen más útiles vs. una pérdida de tiempo?",
        "Si pudieras arreglar un flujo de trabajo este trimestre, ¿cuál sería?",
    ],
}


def _mock_turn(
    *,
    preferred_language: str,
    question_count: int,
    question_target: int,
    user_message: str,
    employee_name: str,
) -> dict[str, Any]:
    lang = preferred_language if preferred_language in MOCK_QUESTIONS else "en"
    questions = MOCK_QUESTIONS[lang]
    next_index = min(question_count, len(questions) - 1)
    completed = question_count + 1 >= question_target

    if completed:
        assistant = {
            "en": (
                f"Thank you, {employee_name or 'there'}! We've got what we need for now — "
                "but if anything else comes to mind, just message me anytime and I'll add it."
            ),
            "es": (
                f"¡Gracias, {employee_name or 'amigo/a'}! Por ahora tenemos lo que necesitamos — "
                "si se te ocurre algo más, escríbeme cuando quieras."
            ),
        }.get(lang, (
            f"Thank you, {employee_name or 'there'}! We've got what we need for now — "
            "but if anything else comes to mind, just message me anytime and I'll add it."
        ))
    else:
        assistant = questions[next_index]

    return {
        "assistant_message": assistant,
        "insight": {
            "summary": f"Employee mentioned: {user_message[:200]}",
            "topics": ["workflow", "tools"],
        },
        "completed": completed,
        "question_count": question_count + (0 if completed else 1),
    }


def run_discovery_turn(
    *,
    playbook_block: str,
    preferred_language: str,
    company_name: str,
    employee_name: str,
    department: str,
    question_count: int,
    question_target: int,
    user_message: str,
    history: list[dict[str, str]],
    industry: str | None = None,
    size_band: str | None = None,
    region: str | None = None,
    business_goals: list[str] | str | None = None,
    website_url: str | None = None,
    known_systems: list[str] | None = None,
) -> dict[str, Any]:
    if not llm_configured():
        return _mock_turn(
            preferred_language=preferred_language,
            question_count=question_count,
            question_target=question_target,
            user_message=user_message,
            employee_name=employee_name,
        )

    profile_bits = []
    if industry:
        profile_bits.append(f"industry={industry}")
    if size_band:
        profile_bits.append(f"size={size_band}")
    if region:
        profile_bits.append(f"region={region}")
    if business_goals:
        goal_text = ", ".join(business_goals) if isinstance(business_goals, list) else str(business_goals)
        if goal_text.strip():
            profile_bits.append(f"goals={goal_text[:160]}")
    if website_url:
        profile_bits.append(f"website={website_url}")
    if known_systems:
        profile_bits.append(f"systems_in_use={', '.join(str(s) for s in known_systems[:12])[:160]}")
    profile_line = (
        f"Company profile: {'; '.join(profile_bits)}.\n" if profile_bits else ""
    )

    system = f"""You are a workflow discovery interviewer for {company_name}.
Department focus: {department or "general"}.
Employee: {employee_name or "the employee"}.
{profile_line}
{playbook_block}

Rules:
- Conduct the entire conversation in {preferred_language} (ISO 639-1). Do not switch unless the employee switches.
- Ask ONE concise question at a time, building on prior answers.
- You have asked {question_count} discovery questions so far; target is {question_target}.
- If you have reached the target, thank them and close the interview instead of asking another question.
- On the first turn (question_count is 0), open with a brief warm welcome and ask your first discovery question in the same message. Reference any role or context the employee already shared in their opening — do not ask them to re-introduce themselves.

Respond with JSON only:
{{
  "assistant_message": "your next message to the employee",
  "insight": {{ "summary": "1-2 sentence insight from the employee's last message", "topics": ["topic1"] }},
  "completed": false
}}
Set completed to true only when the interview should end (reached target or natural wrap-up)."""

    messages = [SystemMessage(content=system)]
    for item in history[-12:]:
        role = item.get("role", "user")
        content = item.get("content", "")
        if role == "assistant":
            messages.append(SystemMessage(content=f"[Assistant]: {content}"))
        else:
            messages.append(HumanMessage(content=content))
    messages.append(HumanMessage(content=user_message))

    llm = build_chat_openai(temperature=0.4, json_mode=True)

    last_error = None
    for attempt in range(settings.max_openai_retries + 1):
        try:
            response = llm.invoke(messages)
            try:
                payload = extract_json_object(response.content)
            except LlmJsonParseError as parse_exc:
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
                    payload = extract_json_object(response.content)
                except LlmJsonParseError:
                    last_error = parse_exc
                    record_failure()
                    if attempt < settings.max_openai_retries:
                        time.sleep(2**attempt)
                        continue
                    raise OpenAIUnavailable(str(parse_exc)) from parse_exc

            record_success()
            completed = bool(payload.get("completed")) or question_count + 1 >= question_target
            return {
                "assistant_message": payload.get("assistant_message", ""),
                "insight": payload.get("insight") or {"summary": "", "topics": []},
                "completed": completed,
                "question_count": question_count if completed else question_count + 1,
            }
        except OpenAIUnavailable:
            raise
        except Exception as exc:
            last_error = exc
            record_failure()
            if attempt < settings.max_openai_retries:
                time.sleep(2**attempt)

    raise OpenAIUnavailable(str(last_error))
