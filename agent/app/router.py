"""Agent Router — builds the prioritized specialist queue from an employee Profile Card.

Deterministic rules (no LLM): fast, free, testable. Called once after profiling
completes (POST /v1/threads/{id}/route), or lazily on the first discovery turn
if routing was skipped/failed.
"""

from typing import Any

from app.state import default_limits

SENIOR_LEVELS = {"manager", "director", "executive"}
IC_LEVELS = {"individual_contributor", "team_lead", "manager"}
TECHNICAL_DEPARTMENTS = {"it", "engineering", "technology"}


def build_agent_queue(
    profile: dict[str, Any],
    limits: dict[str, int] | None = None,
    question_target: int = 12,
) -> dict[str, Any]:
    limits = {**default_limits(), **(limits or {})}
    department = (profile.get("department") or "default").lower()
    seniority = (profile.get("seniority") or "individual_contributor").lower()
    tools = profile.get("primary_tools") or []

    agents: list[dict[str, Any]] = []
    skipped: list[dict[str, Any]] = []

    agents.append(
        {
            "id": f"domain_{department}",
            "priority": 1,
            "question_budget": 4,
            "reason": f"{department.title()} department specialist",
        }
    )

    if seniority in IC_LEVELS:
        agents.append(
            {
                "id": "process",
                "priority": 2,
                "question_budget": 4,
                "reason": "Hands-on role — daily workflow and handoff focus",
            }
        )
    else:
        skipped.append({"id": "process", "reason": f"Seniority {seniority} — strategic focus instead"})

    if tools or department in TECHNICAL_DEPARTMENTS:
        agents.append(
            {
                "id": "technical",
                "priority": 3,
                "question_budget": 3,
                "reason": "Tools mentioned in profile" if tools else "Technical department",
            }
        )
    else:
        skipped.append({"id": "technical", "reason": "No tools/systems surfaced yet"})

    if seniority in SENIOR_LEVELS or department == "executive":
        agents.append(
            {
                "id": "strategic",
                "priority": 4 if seniority == "manager" else 2,
                "question_budget": 3,
                "reason": f"{seniority.replace('_', ' ').title()} — cross-functional perspective",
            }
        )
    else:
        skipped.append({"id": "strategic", "reason": f"Seniority {seniority} — not a strategic role"})

    agents.sort(key=lambda a: a["priority"])
    max_agents = limits["max_active_agents"]
    if len(agents) > max_agents:
        for dropped in agents[max_agents:]:
            skipped.append({"id": dropped["id"], "reason": "Over max_active_agents limit"})
        agents = agents[:max_agents]

    per_agent_cap = limits["max_questions_per_agent"]
    for agent in agents:
        agent["question_budget"] = min(agent["question_budget"], per_agent_cap)

    total_budget = min(sum(a["question_budget"] for a in agents), question_target)

    return {"agents": agents, "skipped": skipped, "total_budget": total_budget}
