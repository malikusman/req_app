"""Standalone discovery-interview simulator — drives the multi-agent graph
directly so you can eyeball question flow, repetition and tone without the full
Rails stack. Talks to whatever LLM the env points at (local LM Studio/Gemma or
OpenAI), so it's the zero-friction way to test against a LOCAL model without
restarting the langgraph service.

Run inside the langgraph container (reaches LM Studio via host.docker.internal):

  docker exec \
    -e OPENAI_BASE_URL=http://host.docker.internal:1234/v1 \
    -e OPENAI_API_KEY=lm-studio \
    -e OPENAI_MODEL=google/gemma-4-12b-qat \
    -e AREA_ROUTING=1 \
    req_app-langgraph-1 python -u /app/scripts/sim_interview.py

AREA_ROUTING=1 -> phase-3 map-then-branch flow; =0 -> specialist queue.
Prints each question with its phase/area/beat (or active specialist), then the
full sequence for a repetition scan.
"""
import os
import sys

sys.path.insert(0, "/app")

from app.multi_agent_llm import run_agent_turn  # noqa: E402
from app.openai_factory import llm_configured  # noqa: E402
from app.orchestrator import finalize_turn, prepare_turn  # noqa: E402
from app.state import default_limits  # noqa: E402

AREA_ROUTING = os.environ.get("AREA_ROUTING", "1") == "1"
print("LLM configured:", llm_configured(), "| model:", os.environ.get("OPENAI_MODEL"), "| area_routing:", AREA_ROUTING)

PROFILE = {
    "name": "Layla",
    "role_title": "Accounts Payable Clerk",
    "department": "finance",
    "seniority": "individual_contributor",
    "responsibilities": "Processing supplier invoices, matching POs, and supporting month-end close",
    "primary_tools": ["SAP", "Excel", "Outlook"],
}

# Realistic answers, deliberately NOT steered toward handoffs, to test fixation.
ANSWERS = [
    "I mostly process supplier invoices — matching them to POs in SAP and chasing anything that doesn't line up.",
    "A lot of it is manual. If the PO and invoice don't match I drop it into an Excel exception tab and work through them one by one.",
    "The three-way match failures are the worst — maybe one in five invoices don't match and they pile up.",
    "SAP for posting, an Excel workbook for the exception tracker, and Outlook for chasing approvals.",
    "Honestly the copy-paste between SAP and Excel eats my day — I re-key the same numbers over and over.",
    "Month-end is the crunch; everything has to hit the right period even when the paperwork shows up late.",
    "Anything over 25k needs the CFO to sign off, and if he's travelling it can sit for a couple of days.",
    "Not really, but if something could auto-match invoices to POs that would honestly save me hours.",
    "The demurrage charges from the ports are messy — they arrive late so I end up backdating them.",
    "That's most of my day, really.",
]

KICKOFF = ("I'm Layla, an Accounts Payable Clerk in finance. I process supplier invoices, "
           "match POs and help with month-end close. I mainly use SAP, Excel and Outlook.")

state = {
    "blackboard": None,
    "profile": PROFILE,
    "question_count": 0,
    "question_target": 10,
    "limits": {**default_limits(), "orient_questions": 3, "switch_after": 3},
    "preferred_language": "en",
    "company_name": "GulfLink Logistics",
    "department": "finance",
    "playbook_block": "You are conducting workflow discovery for a finance team member.",
    "area_routing": AREA_ROUTING,
    "history": [],
    "user_message": KICKOFF,
}

history: list[dict] = []
for i in range(12):
    prepared = prepare_turn(state)
    if prepared.get("should_close"):
        print(f"\n--- CLOSE at Q{i + 1} ---")
        break
    out = run_agent_turn(prepared)
    q = out.get("assistant_message", "")
    dec = prepared.get("area_decision") or {}
    tag = (f"{dec.get('phase')}:{dec.get('current_area', '-')}/{dec.get('current_beat', '-')}"
           if dec else prepared.get("active_agent_id"))
    areas = [a.get("name") for a in prepared["blackboard"].get("role_areas", [])]
    print(f"\nQ{i + 1}  [{tag}]  areas={areas}")
    print(f"    {q}")
    final = finalize_turn(prepared, out)
    ans = ANSWERS[i] if i < len(ANSWERS) else "Yeah, pretty much."
    history = history + [{"role": "assistant", "content": q}, {"role": "user", "content": ans}]
    if final.get("completed"):
        print(f"\n--- LLM ended at Q{i + 1} ---")
        break
    state = {**final, "history": history, "user_message": ans}

print("\n\n===== QUESTION SEQUENCE (repetition scan) =====")
for i, q in enumerate([h["content"] for h in history if h["role"] == "assistant"], 1):
    print(f"{i}. {q}")
