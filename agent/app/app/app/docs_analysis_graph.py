"""LangGraph docs analysis graph — company document knowledge base pipeline."""

from __future__ import annotations

import json
from typing import Any

from langgraph.graph import END, StateGraph
from typing_extensions import TypedDict

from app.config import settings
from app.json_parse import extract_json_object
from app.openai_factory import build_chat_openai, llm_configured


class DocsAnalysisState(TypedDict, total=False):
    run_kind: str
    company_profile: dict[str, Any]
    documents: list[dict[str, Any]]
    existing_knowledge: list[dict[str, Any]]
    existing_questions: list[dict[str, Any]]
    limits: dict[str, Any]
    knowledge_entries: list[dict[str, Any]]
    questions: list[dict[str, Any]]
    document_summaries: list[dict[str, Any]]
    events: list[dict[str, Any]]
    summary: str
    critique_score: float


def _llm(model: str | None = None):
    if not llm_configured():
        return None
    return build_chat_openai(model=model, temperature=0.2, json_mode=False)


def _append_event(state: DocsAnalysisState, agent: str, message: str) -> list[dict[str, Any]]:
    events = list(state.get("events") or [])
    events.append({"agent": agent, "message": message})
    return events


def coordinator_node(state: DocsAnalysisState) -> dict[str, Any]:
    docs = state.get("documents") or []
    return {
        "events": _append_event(
            state,
            "ingest_coordinator",
            f"Routing {len(docs)} document(s) for {state.get('run_kind', 'full')} analysis",
        )
    }


def specialist_extract_node(state: DocsAnalysisState) -> dict[str, Any]:
    docs = state.get("documents") or []
    profile = state.get("company_profile") or {}
    limits = state.get("limits") or {}
    model = limits.get("model_fast") or settings.openai_model
    llm = _llm(model)
    knowledge: list[dict[str, Any]] = []
    summaries: list[dict[str, Any]] = []
    events = list(state.get("events") or [])

    if state.get("run_kind") == "profile_reground":
        events.append({"agent": "doc_specialist", "message": "Skipped doc extract (profile re-ground)"})
        return {"events": events, "knowledge_entries": list(state.get("existing_knowledge") or [])}

    for doc in docs:
        text = (doc.get("text_excerpt") or "")[:6000]
        if not text.strip():
            continue
        if llm is None:
            knowledge.append(
                {
                    "entry_type": "process" if doc.get("document_type") in ("sop", "process") else "other",
                    "title": f"{doc.get('filename')} overview",
                    "content": text[:800],
                    "confidence": 0.55,
                    "department": doc.get("department"),
                    "source_document_ids": [doc.get("id")],
                    "source_chunk_ids": (doc.get("chunk_ids") or [])[:5],
                }
            )
            summaries.append({"document_id": doc.get("id"), "summary": text[:280]})
            continue

        prompt = f"""You are a document analysis specialist for enterprise operations discovery.
Company profile: {json.dumps(profile)[:2000]}
Document filename: {doc.get('filename')} type={doc.get('document_type')} dept={doc.get('department')}
Extract structured findings as JSON:
{{"summary":"...","entries":[{{"entry_type":"process|policy|system|org|metric|risk|other","title":"...","content":"...","confidence":0.0,"department":null}}]}}
Text:
{text}
"""
        try:
            raw = llm.invoke(prompt).content
            parsed = extract_json_object(raw) or {}
            summaries.append({"document_id": doc.get("id"), "summary": parsed.get("summary") or text[:280]})
            for entry in parsed.get("entries") or []:
                knowledge.append(
                    {
                        **entry,
                        "source_document_ids": [doc.get("id")],
                        "source_chunk_ids": (doc.get("chunk_ids") or [])[:5],
                        "department": entry.get("department") or doc.get("department"),
                    }
                )
            events.append({"agent": "doc_specialist", "message": f"Extracted {doc.get('filename')}"})
        except Exception as exc:  # noqa: BLE001
            events.append({"agent": "doc_specialist", "message": f"Fallback for {doc.get('filename')}: {exc}"})
            knowledge.append(
                {
                    "entry_type": "other",
                    "title": f"{doc.get('filename')} excerpt",
                    "content": text[:800],
                    "confidence": 0.4,
                    "source_document_ids": [doc.get("id")],
                    "source_chunk_ids": (doc.get("chunk_ids") or [])[:5],
                }
            )

    return {
        "knowledge_entries": knowledge,
        "document_summaries": summaries,
        "events": events,
    }


def synthesizer_node(state: DocsAnalysisState) -> dict[str, Any]:
    existing = list(state.get("existing_knowledge") or [])
    fresh = list(state.get("knowledge_entries") or [])
    # Prefer fresh extracts; keep existing titles not obviously duplicated
    titles = {str(e.get("title", "")).lower() for e in fresh}
    merged = fresh + [e for e in existing if str(e.get("title", "")).lower() not in titles]
    events = _append_event(state, "knowledge_synthesizer", f"Merged KB to {len(merged)} entries")
    return {"knowledge_entries": merged[:80], "events": events}


def profile_grounder_node(state: DocsAnalysisState) -> dict[str, Any]:
    profile = state.get("company_profile") or {}
    kb = state.get("knowledge_entries") or []
    events = _append_event(
        state,
        "profile_grounder",
        f"Grounded {len(kb)} entries against profile for {profile.get('name') or 'company'}",
    )
    return {"events": events}


def question_generator_node(state: DocsAnalysisState) -> dict[str, Any]:
    profile = state.get("company_profile") or {}
    kb = state.get("knowledge_entries") or []
    existing_q = {str(q.get("body", "")).lower() for q in (state.get("existing_questions") or [])}
    limits = state.get("limits") or {}
    max_q = int(limits.get("max_questions") or 12)
    questions: list[dict[str, Any]] = []

    answers = profile.get("questionnaire_answers") or {}
    goals = answers.get("primary_goals") or (profile.get("company_profile") or {}).get("business_goals") or []
    if goals and "how do your current documents" not in " ".join(existing_q):
        body = f"How do your uploaded documents support these goals: {', '.join(map(str, goals[:3]))}?"
        if body.lower() not in existing_q:
            questions.append({"body": body, "rationale": "Profile goals coverage"})

    if not any(e.get("entry_type") == "system" for e in kb):
        body = "Which core business systems (ERP, CRM, accounting, HR) does your team use daily?"
        if body.lower() not in existing_q:
            questions.append({"body": body, "rationale": "Systems gap"})

    if not any(e.get("entry_type") in ("process", "policy") for e in kb):
        body = "Can you share the SOP for your most critical approval or handoff workflow?"
        if body.lower() not in existing_q:
            questions.append({"body": body, "rationale": "Process documentation gap"})

    llm = _llm((limits.get("model_reasoning") or settings.openai_model))
    if llm and kb:
        prompt = f"""Generate up to 4 clarification questions a consultant would ask this company.
Avoid duplicates of: {list(existing_q)[:10]}
KB titles: {[e.get('title') for e in kb[:15]]}
Profile answers keys: {list(answers.keys())[:20]}
JSON: {{"questions":[{{"body":"...","rationale":"..."}}]}}"""
        try:
            parsed = extract_json_object(llm.invoke(prompt).content) or {}
            for q in parsed.get("questions") or []:
                body = str(q.get("body") or "").strip()
                if body and body.lower() not in existing_q:
                    questions.append({"body": body, "rationale": q.get("rationale")})
        except Exception:  # noqa: BLE001
            pass

    # dedupe
    seen: set[str] = set()
    unique: list[dict[str, Any]] = []
    for q in questions:
        key = q["body"].lower()
        if key in seen or key in existing_q:
            continue
        seen.add(key)
        unique.append(q)
        if len(unique) >= max_q:
            break

    events = _append_event(state, "question_generator", f"Proposed {len(unique)} questions")
    return {"questions": unique, "events": events}


def critic_node(state: DocsAnalysisState) -> dict[str, Any]:
    kb = state.get("knowledge_entries") or []
    score = 0.4 + min(0.5, 0.05 * len(kb))
    events = _append_event(state, "critic", f"Coverage score {score:.2f}")
    return {"critique_score": score, "events": events}


def reporter_node(state: DocsAnalysisState) -> dict[str, Any]:
    kb = state.get("knowledge_entries") or []
    qs = state.get("questions") or []
    summary = f"Analyzed documents into {len(kb)} knowledge entries and {len(qs)} clarification questions."
    events = _append_event(state, "run_reporter", summary)
    return {"summary": summary, "events": events}


def build_docs_analysis_graph():
    graph = StateGraph(DocsAnalysisState)
    graph.add_node("coordinator", coordinator_node)
    graph.add_node("specialist", specialist_extract_node)
    graph.add_node("synthesizer", synthesizer_node)
    graph.add_node("profile_grounder", profile_grounder_node)
    graph.add_node("question_generator", question_generator_node)
    graph.add_node("critic", critic_node)
    graph.add_node("reporter", reporter_node)

    graph.set_entry_point("coordinator")
    graph.add_edge("coordinator", "specialist")
    graph.add_edge("specialist", "synthesizer")
    graph.add_edge("synthesizer", "profile_grounder")
    graph.add_edge("profile_grounder", "question_generator")
    graph.add_edge("question_generator", "critic")
    graph.add_edge("critic", "reporter")
    graph.add_edge("reporter", END)
    return graph.compile()


_DOCS_GRAPH = None


def execute_docs_analysis(payload: dict[str, Any]) -> dict[str, Any]:
    global _DOCS_GRAPH
    if _DOCS_GRAPH is None:
        _DOCS_GRAPH = build_docs_analysis_graph()

    initial: DocsAnalysisState = {
        "run_kind": payload.get("run_kind") or "full",
        "company_profile": payload.get("company_profile") or {},
        "documents": payload.get("documents") or [],
        "existing_knowledge": payload.get("existing_knowledge") or [],
        "existing_questions": payload.get("existing_questions") or [],
        "limits": payload.get("limits") or {},
        "knowledge_entries": [],
        "questions": [],
        "document_summaries": [],
        "events": [],
        "summary": "",
        "critique_score": 0.0,
    }
    result = _DOCS_GRAPH.invoke(initial)
    return {
        "knowledge_entries": result.get("knowledge_entries") or [],
        "questions": result.get("questions") or [],
        "document_summaries": result.get("document_summaries") or [],
        "summary": result.get("summary") or "",
        "events": result.get("events") or [],
        "critique_score": result.get("critique_score"),
    }
