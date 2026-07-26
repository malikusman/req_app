import uuid
from typing import Any

import httpx
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

from app.circuit_breaker import is_open
from app.config import configure_langsmith, settings
from app.graph import execute_turn
from app.multi_agent_graph import execute_multi_agent_turn
from app.router import build_agent_queue

app = FastAPI(title="Req Discovery Agent", version="1.0.0")

if configure_langsmith():
    import logging

    logging.getLogger("uvicorn.error").info(
        "LangSmith tracing enabled (project=%s)",
        settings.langsmith_project,
    )


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
    industry: str | None = None
    size_band: str | None = None
    region: str | None = None
    business_goals: Any = None
    company_profile: dict[str, Any] | None = None


class HistoryMessage(BaseModel):
    role: str
    content: str


class TurnRequest(BaseModel):
    thread_id: str | None = None
    user_message: str
    playbook: PlaybookPayload
    context: TurnContext = Field(default_factory=TurnContext)
    history: list[HistoryMessage] = Field(default_factory=list)
    # Multi-agent extensions (optional — legacy requests omit them)
    multi_agent: bool = False
    profile: dict[str, Any] | None = None
    blackboard: dict[str, Any] | None = None
    limits: dict[str, int] | None = None
    memory_facts: list[dict[str, Any]] = Field(default_factory=list)
    document_snippets: list[str] = Field(default_factory=list)
    knowledge_snippets: list[str] = Field(default_factory=list)
    media_context: dict[str, Any] | None = None
    company_profile: dict[str, Any] | None = None
    media_snippets: list[str] = Field(default_factory=list)


class TurnResponse(BaseModel):
    thread_id: str
    assistant_message: str
    insight: dict[str, Any]
    completed: bool
    question_count: int
    playbook_version: int
    # Multi-agent extensions (None on legacy turns)
    blackboard: dict[str, Any] | None = None
    active_agent_id: str | None = None
    routing_decision: dict[str, Any] | None = None


class RouteRequest(BaseModel):
    profile: dict[str, Any]
    limits: dict[str, int] | None = None
    question_target: int = 12


class RouteResponse(BaseModel):
    agents: list[dict[str, Any]]
    skipped: list[dict[str, Any]]
    total_budget: int


@app.get("/health")
def health():
    return {"status": "ok", "openai_configured": bool(settings.openai_api_key or settings.openai_base_url)}


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
        "industry": body.context.industry,
        "size_band": body.context.size_band,
        "region": body.context.region,
        "business_goals": body.context.business_goals,
        "company_profile": body.context.company_profile or {},
        "user_message": body.user_message,
        "history": [m.model_dump() for m in body.history],
    }

    if body.multi_agent:
        state.update(
            {
                "profile": body.profile or {},
                "blackboard": body.blackboard,
                "limits": body.limits or {},
                "memory_facts": body.memory_facts,
                "document_snippets": body.document_snippets,
                "knowledge_snippets": body.knowledge_snippets,
                "media_context": body.media_context,
                "media_snippets": body.media_snippets,
                "company_profile": body.company_profile or body.context.company_profile or {},
            }
        )
        result = execute_multi_agent_turn(state)
    else:
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
        blackboard=result.get("blackboard") if body.multi_agent else None,
        active_agent_id=result.get("active_agent_id") if body.multi_agent else None,
        routing_decision=result.get("routing_decision") if body.multi_agent else None,
    )


@app.post("/v1/threads/{thread_id}/route", response_model=RouteResponse)
def route_agents(thread_id: str, body: RouteRequest):
    result = build_agent_queue(body.profile, body.limits, body.question_target)
    return RouteResponse(**result)


@app.post("/v1/threads", response_model=dict)
def create_thread():
    return {"thread_id": str(uuid.uuid4())}


class DocsAnalysisRequest(BaseModel):
    run_id: int | None = None
    run_kind: str = "full"
    company_profile: dict[str, Any] = Field(default_factory=dict)
    documents: list[dict[str, Any]] = Field(default_factory=list)
    existing_knowledge: list[dict[str, Any]] = Field(default_factory=list)
    existing_questions: list[dict[str, Any]] = Field(default_factory=list)
    limits: dict[str, Any] = Field(default_factory=dict)


@app.post("/v1/docs_analysis/runs")
def run_docs_analysis(body: DocsAnalysisRequest):
    if is_open():
        raise HTTPException(status_code=503, detail={"error": "circuit_open"})
    from app.docs_analysis_graph import execute_docs_analysis

    try:
        return execute_docs_analysis(body.model_dump())
    except Exception as exc:  # noqa: BLE001
        raise HTTPException(status_code=500, detail={"error": str(exc)}) from exc


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
