"""Router coverage for COMPLIANCE persona (FEAT-AGENTS)."""

from app.router import build_agent_queue


def test_routes_compliance_for_finance():
    result = build_agent_queue(
        {"department": "finance", "seniority": "individual_contributor", "primary_tools": []},
        limits={"max_active_agents": 5, "max_questions_per_agent": 5},
    )
    ids = [a["id"] for a in result["agents"]]
    assert "compliance" in ids


def test_skips_compliance_for_sales():
    result = build_agent_queue(
        {"department": "sales", "seniority": "individual_contributor", "primary_tools": []},
        limits={"max_active_agents": 5, "max_questions_per_agent": 5},
    )
    ids = [a["id"] for a in result["agents"]]
    assert "compliance" not in ids
    assert any(s["id"] == "compliance" for s in result["skipped"])
