import uuid
from typing import Any

import httpx
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from app.circuit_breaker import is_open
from app.config import settings
from app.graph import execute_turn

app = FastAPI(title="Req Discovery Agent", version="1.0.0")


class PlaybookPayload(BaseModel):
    prompt_block: str
    version: int = 1
    department: str = "default"


class TurnContext(BaseModel):
    preferred_language: str = "en"
    company_name: str = ""
    employee_name: str = ""
    department: str = "default"
    question_count: int = 0
    question_target: int = 10


class HistoryMessage(BaseModel):
    role: str
    content: str


class TurnRequest(BaseModel):
    thread_id: str | None = None
    user_message: str
    playbook: PlaybookPayload
    context: TurnContext = Field(default_factory=TurnContext)
    history: list[HistoryMessage] = Field(default_factory=list)


class TurnResponse(BaseModel):
    thread_id: str
    assistant_message: str
    insight: dict[str, Any]
    completed: bool
    question_count: int
    playbook_version: int


@app.get("/health")
def health():
    return {"status": "ok", "openai_configured": bool(settings.openai_api_key)}


@app.post("/v1/threads/{thread_id}/turn", response_model=TurnResponse)
def run_turn(thread_id: str, body: TurnRequest):
    if is_open():
        raise HTTPException(
            status_code=503,
            detail={"error": "openai_unavailable", "retryable": True},
        )

    state = {
        "playbook_block": body.playbook.prompt_block,
        "playbook_version": body.playbook.version,
        "preferred_language": body.context.preferred_language,
        "company_name": body.context.company_name,
        "employee_name": body.context.employee_name,
        "department": body.context.department,
        "question_count": body.context.question_count,
        "question_target": body.context.question_target,
        "user_message": body.user_message,
        "history": [m.model_dump() for m in body.history],
    }

    result = execute_turn(state)
    if result.get("error") == "openai_unavailable":
        raise HTTPException(
            status_code=503,
            detail={"error": "openai_unavailable", "retryable": True},
        )

    return TurnResponse(
        thread_id=thread_id,
        assistant_message=result.get("assistant_message", ""),
        insight=result.get("insight") or {},
        completed=bool(result.get("completed")),
        question_count=int(result.get("question_count", body.context.question_count)),
        playbook_version=body.playbook.version,
    )


@app.post("/v1/threads", response_model=dict)
def create_thread():
    return {"thread_id": str(uuid.uuid4())}


@app.get("/v1/playbooks/active")
def fetch_active_playbook(
    department: str = "default",
    x_internal_token: str | None = Header(default=None),
):
    token = x_internal_token or ""
    if token != settings.internal_api_token:
        raise HTTPException(status_code=401, detail="unauthorized")

    url = f"{settings.rails_internal_url}/api/v1/internal/playbooks/active"
    try:
        response = httpx.get(
            url,
            params={"department": department},
            headers={"X-Internal-Token": settings.internal_api_token},
            timeout=10.0,
        )
        response.raise_for_status()
        return response.json()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"rails_unreachable: {exc}") from exc
