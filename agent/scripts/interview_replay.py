"""Interview replay harness — does the discovery interview learn the right things?

Eight simulated employees, each played by a model working from a hidden fact
sheet, are interviewed by the real graph (record -> prepare -> talk), in-process,
against whatever model the environment points at. Every run is scored on what
the interview actually captured, not on how it sounded.

Run it before and after any prompt, model or flow change. The numbers that matter:

  close      how it ended. dossier_complete is the intended exit; a lot of
             "stalled" means replies aren't registering, "ceiling" means the
             dossier asks for more than an interview can get.
  slots      required slots filled / required. The dossier is the record.
  costed     frictions whose time cost was captured WITH a usable unit on both
             how often and how long — the raw material for hours per year.
  capture    recording calls that degraded (fallback) — should be zero.
  repeats    questions that restate an earlier one.
  compound   messages asking more than one question.
  banned     messages using vocabulary the interviewer must never use with staff.

Usage, inside the langgraph container (only /app/app is mounted, so copy it in):

  docker compose cp agent/scripts langgraph:/app/
  docker compose exec -T -w /app langgraph python -u scripts/interview_replay.py \
      [--only procurement,arabic] [--json /tmp/replay.json] [--workers 4]
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Any

sys.path.insert(0, "/app")

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage  # noqa: E402

from app import dossier  # noqa: E402
from app.config import settings  # noqa: E402
from app.multi_agent_graph import execute_multi_agent_turn  # noqa: E402
from app.openai_factory import build_chat_openai, llm_configured  # noqa: E402
from app.state import resolve_limits  # noqa: E402

BANNED = re.compile(
    r"\b(automat\w*|efficien\w*|inefficien\w*|wast\w*|consultant\w*|"
    r"assess\w*|score\w*|slot\w*|dossier)\b",
    re.I,
)
ARABIC = re.compile(r"[؀-ۿ]")

PERSONAS: list[dict[str, Any]] = [
    {
        "key": "procurement",
        # (how often, unit, minutes per occurrence at the low end) — what the facts say.
        "true_effort": [(1, "per_day", 40), (15, "per_week", 10)],
        "about": "cooperative, two clear areas, clear times",
        "profile": {"name": "Shiv", "role_title": "Procurement Officer", "department": "procurement",
                    "seniority": "individual_contributor",
                    "responsibilities": "supplier price updates, purchase orders and supplier follow-up",
                    "primary_tools": ["NAV", "Excel", "WhatsApp"]},
        "style": "Friendly and cooperative. Two to four sentences per answer.",
        "facts": """
- Supplier price updates: every morning you open the price sheets 5 or 6 suppliers email,
  and re-key each item and variant into NAV by hand, checking the item codes. It takes
  forty minutes to an hour. Each supplier's sheet has a different layout, so codes get
  mismatched and wrong variant prices reach customers about twice a month.
- Purchase orders: you raise about 15 POs a week in NAV, then chase suppliers for order
  confirmation on WhatsApp and email. Chasing is 10 to 15 minutes per PO, and you often
  wait two or three days for a reply.
- AI: you sometimes use ChatGPT to tidy up supplier emails. Nothing official.
- With more time you'd find new suppliers and negotiate better terms on the top lines.""",
        "expect": {"areas_min": 2, "costed_min": 2},
    },
    {
        "key": "terse",
        # (how often, unit, minutes per occurrence at the low end) — what the facts say.
        "true_effort": [(30, "per_day", 3), (1, "per_day", 60)],
        "about": "very short answers",
        "profile": {"name": "Layla", "role_title": "Accounts Payable Clerk", "department": "finance",
                    "seniority": "individual_contributor",
                    "responsibilities": "invoice entry and invoice matching",
                    "primary_tools": ["SAP", "Excel"]},
        "style": "Very terse. Three to ten words per answer. Never volunteer anything extra.",
        "facts": """
- Invoice entry: about 30 supplier invoices a day into SAP, 3 to 5 minutes each.
- Matching: about 1 in 5 invoices don't match the PO; you log those in an Excel tracker
  and chase buyers by email. Chasing takes maybe an hour a day in total.
- AI: none.
- With more time: do the vendor reconciliations properly.""",
        "expect": {"areas_min": 1, "costed_min": 1, "close_ok": {"dossier_complete", "stalled"}},
    },
    {
        "key": "rambling",
        # (how often, unit, minutes per occurrence at the low end) — what the facts say.
        "true_effort": [(20, "per_day", 15), (10, "per_day", 5)],
        "about": "long digressive answers, blames a colleague",
        "profile": {"name": "Omar", "role_title": "Sales Coordinator", "department": "sales",
                    "seniority": "individual_contributor",
                    "responsibilities": "quotations and order entry",
                    "primary_tools": ["ERP", "Excel", "Word", "WhatsApp"]},
        "style": ("Long, rambling answers of five to eight sentences that drift onto other topics. "
                  "At least once complain that Ahmed in the warehouse never updates the stock."),
        "facts": """
- Quotations: enquiries arrive on WhatsApp. You check stock in the ERP, the price in an
  Excel price list, and build the quote in a Word template. About 20 a day, 15 to 20
  minutes each. Stock in the ERP is often wrong so you phone the warehouse.
- Order entry: confirmed orders are typed into the ERP, about 10 a day, 5 minutes each.
- AI: you use ChatGPT to polish quote wording.
- With more time you'd follow up customers who stopped ordering.""",
        "expect": {"areas_min": 2, "costed_min": 1},
    },
    {
        "key": "arabic",
        # (how often, unit, minutes per occurrence at the low end) — what the facts say.
        "true_effort": [(50, "per_week", 10), (4, "per_month", 120)],
        "about": "answers in Arabic",
        "language": "ar",
        "profile": {"name": "Fatima", "role_title": "HR Executive", "department": "hr",
                    "seniority": "individual_contributor",
                    "responsibilities": "recruitment screening and onboarding",
                    "primary_tools": ["Bayzat", "Excel", "Outlook"]},
        "style": ("Always answer in Arabic — mostly Modern Standard Arabic with an occasional Gulf "
                  "expression. Keep system names like Bayzat and Excel in English. Two to three sentences."),
        "facts": """
- CV screening: about 50 CVs a week arrive by email; you read each one and shortlist in
  Excel, around 10 minutes per CV.
- Onboarding: each new hire needs contracts, visa paperwork and Bayzat setup — about two
  hours per hire, roughly 4 hires a month.
- AI: none.
- With more time: employee engagement and proper training plans.""",
        "expect": {"areas_min": 2, "costed_min": 1, "arabic": True},
    },
    {
        "key": "worried",
        # (how often, unit, minutes per occurrence at the low end) — what the facts say.
        "true_effort": [(1, "per_month", 960), (1, "per_week", 180)],
        "about": "asks whether this will cost jobs",
        "profile": {"name": "Ravi", "role_title": "Accounts Assistant", "department": "finance",
                    "seniority": "individual_contributor",
                    "responsibilities": "bank reconciliation and supplier payments",
                    "primary_tools": ["Tally", "Excel", "online banking"]},
        "style": "Polite but a little anxious. Two to three sentences.",
        "worry_on": 3,
        "facts": """
- Bank reconciliation: monthly, matching bank statement lines to Tally by hand in Excel;
  takes about two days each month.
- Supplier payments: weekly payment run, preparing the list and uploading to online
  banking, about three hours each week.
- AI: none.
- With more time: chase overdue customer payments earlier.""",
        "expect": {"areas_min": 2, "costed_min": 1},
    },
    {
        "key": "stopper",
        "true_effort": [(80, "per_day", 2), (3, "per_week", 10)],
        "about": "asks to stop after four answers",
        "profile": {"name": "Maria", "role_title": "Customer Service Agent", "department": "support",
                    "seniority": "individual_contributor",
                    "responsibilities": "customer enquiries and complaints",
                    "primary_tools": ["WhatsApp Business", "Outlook", "ERP"]},
        "style": "Busy and brief. One to two sentences.",
        "stop_after": 4,
        "facts": """
- Enquiries: about 80 WhatsApp and email messages a day, most asking where an order is;
  you look each one up in the ERP, 2 to 3 minutes each.
- Complaints: about 3 a week, logged in a spreadsheet, 10 minutes each.""",
        "expect": {"close_ok": {"employee_ended"}},
    },
    {
        "key": "vague",
        # "most of a day" for a monthly count is the only figure the facts contain.
        "true_effort": [(1, "per_month", 480)],
        "about": "cannot put numbers on anything",
        "profile": {"name": "Khalid", "role_title": "Warehouse Supervisor", "department": "operations",
                    "seniority": "team_lead",
                    "responsibilities": "stock counts and goods receiving",
                    "primary_tools": ["paper checklists", "ERP"]},
        "style": ("Vague about numbers — say 'it depends', 'varies a lot', 'hard to say' when asked how "
                  "long or how often. Two sentences."),
        "facts": """
- Stock counts: monthly full count on paper sheets, then typed into the ERP. Takes 'most
  of a day, depends on the month'.
- Receiving: shipments arrive at irregular times; you check goods against the paper
  delivery note and sign it. 'Varies a lot with the season.'
- AI: none.
- With more time: reorganise the warehouse layout.""",
        "expect": {"areas_min": 2, "costed_min": 0, "close_ok": {"dossier_complete", "stalled"}},
    },
    {
        "key": "three_areas",
        # (how often, unit, minutes per occurrence at the low end) — what the facts say.
        "true_effort": [(1, "per_day", 60), (1, "per_week", 180), (15, "per_day", 2)],
        "about": "manager with three distinct areas",
        "profile": {"name": "Noura", "role_title": "Operations Manager", "department": "operations",
                    "seniority": "manager",
                    "responsibilities": "delivery scheduling, the weekly KPI report and purchase approvals",
                    "primary_tools": ["ERP", "Excel", "Outlook"]},
        "style": "Clear and organised. Three sentences per answer.",
        "facts": """
- Delivery scheduling: every afternoon, about an hour, planning the next day's routes in
  Excel from ERP orders.
- Weekly KPI report: rebuilt by hand in Excel every Monday from three ERP exports, about
  three hours, because nobody trusts the ERP's own report.
- Purchase approvals: about 15 requests a day by email, 2 to 3 minutes each, but they
  wait whenever you're in meetings.
- AI: Copilot in Outlook to summarise long email threads.
- With more time: process improvement projects with the team.""",
        "expect": {"areas_min": 3, "costed_min": 2},
    },
]

EMPLOYEE_SYSTEM = """You are role-playing an employee being interviewed about their work by a
friendly assistant. Stay completely in character.

You are {name}, {role_title}. {style}

What is true about your work (your private notes — reveal things only when asked, the way a
real person would, in your own words):
{facts}

Rules:
- Answer ONLY the interviewer's latest message. Do not ask them questions back unless your
  character would.
- Never invent numbers, frequencies or a daily schedule that are not in your notes. If asked
  something your notes don't cover, say you're not sure or give a vague answer.
- Write only your reply — no labels, no quotation marks."""


def kickoff(profile: dict[str, Any]) -> str:
    # Mirrors Discovery::KickoffMessage#profile_summary.
    parts = [f"I'm {profile['name']}, a {profile['role_title']} in {profile['department']}."]
    if profile.get("responsibilities"):
        parts.append(profile["responsibilities"])
    if profile.get("primary_tools"):
        parts.append(f"I mainly use {', '.join(profile['primary_tools'])}.")
    return " ".join(parts)


def employee_reply(persona: dict[str, Any], transcript: list[dict[str, str]], answer_no: int) -> str:
    if persona.get("stop_after") and answer_no > persona["stop_after"]:
        return "Sorry, I'm really busy today — can we stop here please?"
    # Low temperature on purpose: a simulated employee who improvises figures makes the
    # "misread" check blame the interview for numbers the employee invented.
    llm = build_chat_openai(temperature=0.3, json_mode=False, max_tokens=400)
    messages = [SystemMessage(content=EMPLOYEE_SYSTEM.format(
        name=persona["profile"]["name"], role_title=persona["profile"]["role_title"],
        style=persona["style"], facts=persona["facts"].strip()))]
    for item in transcript:
        # From the employee's side the interviewer is the other party, and the
        # employee's own earlier lines (including the kickoff) are theirs.
        cls = HumanMessage if item["role"] == "assistant" else AIMessage
        messages.append(cls(content=item["content"]))
    reply = str(llm.invoke(messages).content).strip()
    if persona.get("worry_on") == answer_no:
        reply = "Before I answer — is this so they can replace us with AI? " + reply
    return reply


def run_persona(persona: dict[str, Any]) -> dict[str, Any]:
    profile = persona["profile"]
    limits = resolve_limits(None)
    state: dict[str, Any] = {
        "blackboard": {"profile": profile}, "profile": profile, "limits": limits,
        "question_count": 0, "preferred_language": persona.get("language", "en"),
        "employee_name": profile["name"], "company_name": "Gulf Trading LLC",
        "company_profile": {"industry": "wholesale distribution", "region": "UAE"},
        "department": profile["department"],
    }
    history: list[dict[str, str]] = []
    user_message = kickoff(profile)
    turns, latencies, answer_no = [], [], 0
    out: dict[str, Any] = {}

    for _ in range(limits["max_questions"] + 3):
        history.append({"role": "user", "content": user_message})
        state.update({"user_message": user_message, "history": history[-14:]})
        started = time.monotonic()
        out = execute_multi_agent_turn(dict(state))
        latencies.append(time.monotonic() - started)
        if out.get("error"):
            turns.append({"error": out.get("error_detail")})
            break
        routing = out.get("routing_decision") or {}
        before = set(((state.get("blackboard") or {}).get("dossier") or {}).get("slots") or {})
        after = set(((out.get("blackboard") or {}).get("dossier") or {}).get("slots") or {})
        message = out.get("assistant_message") or ""
        turns.append({"reply": user_message, "question": message, "slot": routing.get("slot"),
                      "area": routing.get("area"), "capture": routing.get("capture"),
                      "newly_recorded": sorted(after - before),
                      "captured": out.get("capture"),
                      "reply_fallback": routing.get("reply"), "seconds": round(latencies[-1], 1)})
        history.append({"role": "assistant", "content": message})
        if out.get("completed"):
            break
        state.update({"blackboard": out["blackboard"], "question_count": out["question_count"]})
        answer_no += 1
        user_message = employee_reply(persona, history, answer_no)

    return score(persona, out, turns, latencies)


def score(persona: dict[str, Any], out: dict[str, Any], turns: list[dict[str, Any]],
          latencies: list[float]) -> dict[str, Any]:
    bb = out.get("blackboard") or {}
    limits = resolve_limits(None)
    threshold = limits["slot_confidence"]
    required = dossier.required_keys(bb, threshold)
    missing = dossier.missing_required(bb, threshold) if bb else required
    slots = (bb.get("dossier") or {}).get("slots") or {}

    cost_entries = {k: v for k, v in slots.items() if k.startswith("friction_cost")}
    costed = [
        k for k, v in cost_entries.items()
        if (v.get("effort") or {}).get("frequency", {}) and (v.get("effort") or {}).get("duration", {})
        and (v["effort"]["frequency"] or {}).get("unit") and (v["effort"]["duration"] or {}).get("unit")
    ]
    misread = misread_efforts(persona, cost_entries)
    questions = [t.get("question", "") for t in turns if t.get("question")]
    # The last message on a closed interview is the farewell, not a question.
    asked = questions[:-1] if out.get("completed") else questions
    repeats = sum(
        1 for i, q in enumerate(asked)
        if any(difflib.SequenceMatcher(None, q.lower(), p.lower()).ratio() > 0.8 for p in asked[:i])
    )
    compound = sum(1 for q in asked if q.count("?") > 1)
    banned = [q for q in asked if BANNED.search(q)]
    capture_fallbacks = sum(1 for t in turns if str(t.get("capture") or "").startswith("fallback"))
    reply_fallbacks = sum(1 for t in turns if t.get("reply_fallback"))
    errors = [t["error"] for t in turns if t.get("error")]
    arabic_share = (sum(1 for q in questions if ARABIC.search(q)) / len(questions)) if questions else 0

    expect = persona.get("expect", {})
    close = bb.get("close_reason") or ("error" if errors else "incomplete")
    checks = {
        "close": close in expect.get("close_ok", {"dossier_complete"}),
        "areas": len(dossier.area_names(bb)) >= expect.get("areas_min", 1),
        "costed": len(costed) >= expect.get("costed_min", 0),
        "no_capture_fallback": capture_fallbacks == 0,
        "no_repeats": repeats == 0,
        "no_compound": compound == 0,
        "no_banned_words": not banned,
        "no_errors": not errors,
        # A number that does not match the facts is worse than no number: it would
        # become an hours figure in a client's report.
        "no_misread_numbers": not misread,
    }
    if expect.get("arabic"):
        checks["replies_in_arabic"] = arabic_share >= 0.8
    if "employee_ended" in expect.get("close_ok", set()):
        checks["farewell_asks_nothing"] = bool(questions) and "?" not in questions[-1]
    else:
        checks["role_potential_captured"] = dossier.is_filled(bb.get("dossier") or {}, "role_potential", threshold)

    return {
        "persona": persona["key"], "about": persona["about"], "close": close,
        "questions": out.get("question_count"), "areas": dossier.area_names(bb),
        "slots": f"{len(required) - len(missing)}/{len(required)}", "missing": missing,
        "costed": len(costed),
        "cost_slots": {k: {"value": v.get("value"), "effort": v.get("effort")} for k, v in cost_entries.items()},
        "role_potential": (slots.get("role_potential") or {}).get("value"),
        "misread": misread,
        "capture_fallbacks": capture_fallbacks, "reply_fallbacks": reply_fallbacks,
        "repeats": repeats, "compound": compound, "banned": banned, "errors": errors,
        "arabic_share": round(arabic_share, 2),
        "turn_seconds": {"mean": round(statistics.mean(latencies), 1) if latencies else None,
                         "max": round(max(latencies), 1) if latencies else None},
        "checks": checks, "passed": all(checks.values()), "turns": turns,
    }


MINUTES = {"minutes": 1, "hours": 60, "days": 8 * 60}
# Occurrences per year, on a 5-day, 52-week working year — "each afternoon" and
# "5 a week" are the same rate and must compare equal.
PER_YEAR = {"per_day": 260, "per_week": 52, "per_month": 12, "per_quarter": 4, "per_year": 1}


def _yearly(value: float, unit: str | None) -> float | None:
    return value * PER_YEAR[unit] if unit in PER_YEAR else None


def misread_efforts(persona: dict[str, Any], cost_entries: dict[str, Any]) -> list[str]:
    """Recorded numbers that match nothing in the fact sheet. Words-only entries are
    fine (the harness cannot check words); a number is either right or a misreading."""
    truth = persona.get("true_effort") or []
    problems = []
    for key, entry in cost_entries.items():
        effort = entry.get("effort") or {}
        if effort.get("effort_type") == "waiting":
            continue  # a wait is excluded from hours, so its numbers are not effort
        freq, dur = effort.get("frequency") or {}, effort.get("duration") or {}
        low_y = _yearly(freq["min"], freq.get("unit")) if freq.get("min") is not None else None
        high_y = _yearly(freq.get("max") or freq["min"], freq.get("unit")) if freq.get("min") is not None else None
        f_ok = freq.get("min") is None or freq.get("unit") == "per_event" or any(
            low_y is not None and low_y * 0.9 <= _yearly(f, unit) <= high_y * 1.1
            for f, unit, _ in truth
        )
        d_ok = dur.get("min") is None or dur.get("unit") not in MINUTES or any(
            abs(dur["min"] * MINUTES[dur["unit"]] - m) <= max(1, m * 0.1) or
            (dur["min"] * MINUTES[dur["unit"]] <= m <= (dur.get("max") or dur["min"]) * MINUTES[dur["unit"]])
            for _, _, m in truth
        )
        if not truth and (freq.get("min") is not None or dur.get("min") is not None):
            problems.append(f"{key}: numbers recorded where the facts have none")
        elif not (f_ok and d_ok):
            problems.append(f"{key}: freq {freq.get('min')} {freq.get('unit')}, dur {dur.get('min')} {dur.get('unit')}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="")
    parser.add_argument("--json", default="")
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()

    if not llm_configured():
        print("No model configured — this harness needs one.")
        return 2
    chosen = [p for p in PERSONAS if not args.only or p["key"] in args.only.split(",")]
    print(f"model={settings.openai_model} base={settings.openai_base_url or 'openai'} personas={len(chosen)}\n")

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        results = list(pool.map(run_persona, chosen))

    header = f"{'persona':<13}{'close':<18}{'q':>3}  {'slots':<6}{'costed':>7}{'capt.fb':>8}{'rep':>5}{'cmpd':>5}{'bann':>5}{'s/turn':>8}  result"
    print(header)
    print("-" * len(header))
    for r in results:
        failed = [k for k, ok in r["checks"].items() if not ok]
        print(f"{r['persona']:<13}{r['close']:<18}{r['questions'] or 0:>3}  {r['slots']:<6}{r['costed']:>7}"
              f"{r['capture_fallbacks']:>8}{r['repeats']:>5}{r['compound']:>5}{len(r['banned']):>5}"
              f"{r['turn_seconds']['mean'] or 0:>8}  {'PASS' if r['passed'] else 'FAIL: ' + ', '.join(failed)}")
    passed = sum(1 for r in results if r["passed"])
    print(f"\n{passed}/{len(results)} personas passed")

    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(results, fh, ensure_ascii=False, indent=2)
        print(f"details: {args.json}")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
