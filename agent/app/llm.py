import json
import time
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage
from langchain_openai import ChatOpenAI

from app.circuit_breaker import record_failure, record_success
from app.config import settings


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
            "en": f"Thank you, {employee_name or 'there'}! We've completed your discovery interview. Your insights will help your team improve workflows.",
            "es": f"¡Gracias, {employee_name or 'amigo/a'}! Hemos completado tu entrevista de descubrimiento.",
        }.get(lang, f"Thank you! We've completed your discovery interview.")
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
) -> dict[str, Any]:
    if not settings.openai_api_key:
        return _mock_turn(
            preferred_language=preferred_language,
            question_count=question_count,
            question_target=question_target,
            user_message=user_message,
            employee_name=employee_name,
        )

    system = f"""You are a workflow discovery interviewer for {company_name}.
Department focus: {department or "general"}.
Employee: {employee_name or "the employee"}.

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

    llm = ChatOpenAI(
        model=settings.openai_model,
        api_key=settings.openai_api_key,
        temperature=0.4,
    )

    last_error = None
    for attempt in range(settings.max_openai_retries + 1):
        try:
            response = llm.invoke(messages)
            record_success()
            content = response.content.strip()
            if content.startswith("```"):
                content = content.split("```")[1]
                if content.startswith("json"):
                    content = content[4:]
            payload = json.loads(content)
            completed = bool(payload.get("completed")) or question_count + 1 >= question_target
            return {
                "assistant_message": payload.get("assistant_message", ""),
                "insight": payload.get("insight") or {"summary": "", "topics": []},
                "completed": completed,
                "question_count": question_count if completed else question_count + 1,
            }
        except Exception as exc:
            last_error = exc
            record_failure()
            if attempt < settings.max_openai_retries:
                time.sleep(2**attempt)

    raise OpenAIUnavailable(str(last_error))
