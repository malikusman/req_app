"""Turns a finished interview into the structured package the consultant reads.

The interview already produced everything this needs: named role areas, filled
dossier slots, parked asides, and per-turn findings. So this is a synthesis step,
not a second analysis — it reads the blackboard, never the raw transcript.

Fails safe. With no model configured (or on any error) it returns a deterministic
package built from the same material, because a consultant opening an empty package
cannot tell "nothing was found" from "generation broke".
"""

import json
import re
import time
from typing import Any

from langchain_core.messages import HumanMessage, SystemMessage

from app.circuit_breaker import record_failure, record_success
from app.config import settings
from app.json_parse import LlmJsonParseError, extract_json_object
from app.openai_factory import build_chat_openai, llm_configured, truncated

MAX_ISSUES = 6
MAX_SOLUTIONS = 6
MAX_FOLLOWUPS = 5


def build_package(payload: dict[str, Any]) -> dict[str, Any]:
    """payload: {blackboard, profile, company_name, insights, language}."""
    evidence = _evidence(payload)

    if not llm_configured():
        return _deterministic(payload, evidence, reason="no_model")

    try:
        parsed = _call_model(payload, evidence)
    except Exception as exc:  # noqa: BLE001 — a broken package must not break completion
        return _deterministic(payload, evidence, reason=f"llm_failed: {type(exc).__name__}")

    normalized = _normalize(parsed, evidence)
    if not normalized:
        return _deterministic(payload, evidence, reason="unusable_llm_output")

    normalized["generated_by"] = "llm"
    return normalized


# --------------------------------------------------------------------------- #
# evidence
# --------------------------------------------------------------------------- #


def _evidence(payload: dict[str, Any]) -> dict[str, Any]:
    """Only what the interview actually captured. The model gets nothing else, so it
    has nothing else to draw on."""
    bb = payload.get("blackboard") or {}
    dossier = bb.get("dossier") or {}
    slots = dossier.get("slots") or {}

    areas = [a.get("name") for a in (bb.get("role_areas") or []) if a.get("name")]

    learned = []
    for key, entry in slots.items():
        slot, _, area = key.partition("::")
        learned.append(
            {
                "about": slot.replace("_", " "),
                "area": area or None,
                "detail": entry.get("value"),
                "how_clearly": round(float(entry.get("confidence") or 0), 2),
            }
        )

    return {
        "areas": areas,
        "learned": learned,
        "parked": [p.get("note") for p in (dossier.get("parked") or []) if p.get("note")],
        "findings": [f.get("finding") for f in (bb.get("shared_findings") or []) if f.get("finding")],
        "summary": bb.get("conversation_summary") or "",
        "insights": [i for i in (payload.get("insights") or []) if i],
        "close_reason": bb.get("close_reason"),
    }


# --------------------------------------------------------------------------- #
# model path
# --------------------------------------------------------------------------- #


def _call_model(payload: dict[str, Any], evidence: dict[str, Any]) -> dict[str, Any]:
    profile = payload.get("profile") or {}
    system = f"""You are preparing a handover for a consultant who will review it and decide
what happens next. They have not read the interview. Be concrete and short.

Employee: {profile.get('name') or 'unknown'} — {profile.get('role_title') or 'unknown role'},
{profile.get('department') or 'unknown'} at {payload.get('company_name', 'the company')}.

Everything the interview captured:
{json.dumps(evidence, ensure_ascii=False, indent=2)[:6000]}

Write in {payload.get('language', 'en')} (ISO 639-1).

Rules that matter:
- Ground every claim in the evidence above. Do NOT introduce numbers, durations,
  volumes or percentages that do not appear there. If you don't have a figure, describe
  the problem without one.
- An issue is something costing this person time, accuracy or patience — not a
  restatement of what they do.
- A solution is a concrete change. Say what would change, not "consider optimising".
- Follow-up questions are what YOU would ask this employee next to firm up the
  weakest part of the picture. One clause each, answerable in a sentence. Prefer the
  parked asides — those are threads the interview deliberately left open.
- impact is one of: low, medium, high.

Respond with JSON only:
{{
  "recommendation": "the one thing you'd tell the consultant, in 1-2 sentences",
  "recommendation_rationale": "why, from the evidence, in 1-3 sentences",
  "confidence": 0.0,
  "issues": [{{ "title": "short label", "body": "what's wrong and what it costs", "impact": "medium" }}],
  "solutions": [{{ "title": "short label", "body": "what would change", "impact": "medium", "addresses": "the issue title it answers, or null" }}],
  "followup_questions": [{{ "body": "the question to ask the employee", "rationale": "what it would settle", "from_parked": "the parked note it came from, or null" }}]
}}"""

    # Escalate the cap on truncation rather than re-asking at the same one: a
    # reasoning model that spent its budget thinking will do so again identically.
    cap = settings.openai_max_tokens
    messages = [SystemMessage(content=system), HumanMessage(content="Produce the package.")]
    truncation_retries = 0

    last_error: Exception | None = None
    for attempt in range(settings.max_openai_retries + 1):
        try:
            llm = build_chat_openai(temperature=0.3, json_mode=True, max_tokens=cap)
            response = llm.invoke(messages)
            if truncated(response):
                if truncation_retries < 1:
                    truncation_retries += 1
                    cap *= 2
                    continue
                raise RuntimeError(
                    f"package reply cut off at max_tokens={cap}"
                )
            payload_out = extract_json_object(response.content)
            record_success()
            return payload_out
        except LlmJsonParseError as exc:
            last_error = exc
            record_failure()
            if attempt < settings.max_openai_retries:
                time.sleep(2**attempt)
        except Exception as exc:  # noqa: BLE001
            last_error = exc
            record_failure()
            if attempt < settings.max_openai_retries:
                time.sleep(2**attempt)

    raise last_error or RuntimeError("package generation failed")


def _normalize(parsed: Any, evidence: dict[str, Any]) -> dict[str, Any] | None:
    """Shape and ground the model's output. Ungrounded figures drop the claim, not
    just the figure — a sentence built around an invented number is not salvageable
    by removing the number."""
    if not isinstance(parsed, dict):
        return None

    allowed = _allowed_numbers(evidence)

    recommendation = _grounded(parsed.get("recommendation"), allowed)
    if not recommendation:
        # Without a recommendation there is no package worth showing.
        return None

    issues = _items(parsed.get("issues"), allowed, MAX_ISSUES)
    solutions = _items(parsed.get("solutions"), allowed, MAX_SOLUTIONS, extra_keys=("addresses",))

    followups = []
    for item in (parsed.get("followup_questions") or [])[:MAX_FOLLOWUPS]:
        if not isinstance(item, dict):
            continue
        body = _grounded(item.get("body"), allowed)
        if not body:
            continue
        followups.append(
            {
                "body": body,
                "rationale": _grounded(item.get("rationale"), allowed) or "",
                "from_parked": (str(item.get("from_parked")).strip() or None)
                if item.get("from_parked")
                else None,
            }
        )

    try:
        confidence = max(0.0, min(1.0, float(parsed.get("confidence") or 0.5)))
    except (TypeError, ValueError):
        confidence = 0.5

    return {
        "recommendation": recommendation,
        "recommendation_rationale": _grounded(parsed.get("recommendation_rationale"), allowed) or "",
        "confidence": confidence,
        "issues": issues,
        "solutions": solutions,
        "followup_questions": followups,
    }


def _items(raw: Any, allowed: set[str], limit: int, extra_keys: tuple[str, ...] = ()) -> list[dict[str, Any]]:
    out = []
    for item in (raw or [])[:limit]:
        if not isinstance(item, dict):
            continue
        body = _grounded(item.get("body"), allowed)
        if not body:
            continue
        entry = {
            "title": (str(item.get("title") or "").strip()[:120]) or None,
            "body": body,
            "impact": item.get("impact") if item.get("impact") in {"low", "medium", "high"} else None,
        }
        for key in extra_keys:
            value = item.get(key)
            entry[key] = str(value).strip()[:120] if value else None
        out.append(entry)
    return out


# Mirrors Llm::GroundedNumbers::SIGNIFICANT_NUMBER on the Rails side: currency,
# thousands, decimals, percentages, ranges.
SIGNIFICANT_NUMBER = re.compile(
    r"AED\s?[\d,]+(?:\.\d+)?|\$\s?[\d,]+(?:\.\d+)?|\d{1,3}(?:,\d{3})+(?:\.\d+)?"
    r"|\d+\.\d+|\d+\s?%|\d+\s?(?:[-–—]|to)\s?\d+",
    re.IGNORECASE,
)

# A bare integer is ignored by SIGNIFICANT_NUMBER to avoid false positives on counts
# ("6 issues"), but a bare integer WITH A UNIT is exactly the shape a model invents
# in this domain — "14 hours a week", "3 days to approve", "200 invoices".
#
# Kept in step with Llm::GroundedNumbers on the Rails side, which grounds the report
# the same way. If one changes, change both; both have tests that lock the behaviour.
QUANTITY_UNITS = (
    r"hours?|hrs?|minutes?|mins?|days?|weeks?|months?|years?"
    r"|invoices?|orders?|tickets?|emails?|documents?|files?"
    r"|people|persons?|staff|employees?|times?|steps?"
)
QUANTITY_WITH_UNIT = re.compile(rf"\b(\d+(?:[.,]\d+)?)\s*({QUANTITY_UNITS})\b", re.IGNORECASE)

# "11-14 days" must license BOTH bounds with the unit. Without this, evidence stating
# a real range would reject prose quoting either end of it — a false positive that
# silently deletes correct sentences.
RANGE_WITH_UNIT = re.compile(
    rf"\b(\d+(?:[.,]\d+)?)\s*(?:[-–—]|to)\s*(\d+(?:[.,]\d+)?)\s*({QUANTITY_UNITS})\b",
    re.IGNORECASE,
)


def _canon(token: str) -> str:
    return token.lower().replace(" ", "").replace("–", "-").replace("—", "-").replace("to", "-")


def _quantity(number: str, unit: str) -> str:
    # Unit is part of the key, singularised so "1 day" and "3 days" compare.
    return f"{number.replace(',', '')}{unit.lower().rstrip('s')}"


def _figures(text: str) -> set[str]:
    found = {_canon(t) for t in SIGNIFICANT_NUMBER.findall(text)}
    for low, high, unit in RANGE_WITH_UNIT.findall(text):
        found.add(_quantity(low, unit))
        found.add(_quantity(high, unit))
    for number, unit in QUANTITY_WITH_UNIT.findall(text):
        found.add(_quantity(number, unit))
    return found


# Only the CONTENT the interview captured — never the metadata around it.
#
# Dumping the whole evidence object made the dossier's own confidence scores
# (0.7, 0.8, 0.9) count as grounded figures, so a model could have emitted "0.8%"
# or "saves 0.9 days" and passed the guard.
def _evidence_text(evidence: dict[str, Any]) -> str:
    parts: list[str] = [str(evidence.get("summary") or "")]
    parts.extend(str(item.get("detail") or "") for item in evidence.get("learned") or [])
    parts.extend(str(p) for p in evidence.get("parked") or [])
    parts.extend(str(f) for f in evidence.get("findings") or [])
    parts.extend(str(i) for i in evidence.get("insights") or [])
    return "\n".join(parts)


def _allowed_numbers(evidence: dict[str, Any]) -> set[str]:
    return _figures(_evidence_text(evidence))


def _grounded(text: Any, allowed: set[str]) -> str | None:
    """The text if every figure in it traces to the evidence, else None.

    Drops the whole claim, not just the figure: a sentence built around an invented
    number is not salvageable by deleting the number.
    """
    value = str(text or "").strip()
    if not value:
        return None
    return value if _figures(value) <= allowed else None


# --------------------------------------------------------------------------- #
# deterministic path
# --------------------------------------------------------------------------- #


def _deterministic(payload: dict[str, Any], evidence: dict[str, Any], reason: str) -> dict[str, Any]:
    """A real package from the same evidence, without a model.

    Issues come from what the interview recorded as friction; the recommendation
    names the area with the most friction. No solutions — inventing a remedy without
    a model would be guessing, and an empty solutions list is honest.
    """
    profile = payload.get("profile") or {}
    role = profile.get("role_title") or "this role"
    areas = evidence["areas"]

    frictions = [item for item in evidence["learned"] if item["about"] == "friction" and item["detail"]]
    issues = [
        {
            "title": f"Friction in {item['area']}" if item["area"] else "Reported friction",
            "body": item["detail"],
            "impact": "high" if item["how_clearly"] >= 0.8 else "medium",
        }
        for item in frictions[:MAX_ISSUES]
    ]

    if not issues:
        issues = [
            {"title": "Interview captured little friction", "body": f, "impact": "low"}
            for f in evidence["findings"][:MAX_ISSUES]
        ]

    if frictions:
        focus = frictions[0]["area"] or "their main workflow"
        recommendation = (
            f"Start with {focus} — it is where {role} reported the clearest friction "
            f"across {len(areas) or 1} area(s) of their work."
        )
    else:
        recommendation = (
            f"The interview with {role} did not surface clear friction. "
            "Treat this as thin evidence and ask a follow-up before drawing conclusions."
        )

    # Parked notes are model-authored phrases, so the template stays neutral rather
    # than assuming they read as a clause ("you mentioned mentioned a spreadsheet").
    followups = [
        {
            "body": f"Could you tell me a bit more about this? — {note}",
            "rationale": "The interview captured this and moved on without exploring it.",
            "from_parked": note,
        }
        for note in evidence["parked"][:MAX_FOLLOWUPS]
    ]

    return {
        "recommendation": recommendation,
        "recommendation_rationale": (
            "Built without a language model, directly from what the interview recorded."
        ),
        "confidence": 0.4,
        "issues": issues,
        "solutions": [],
        "followup_questions": followups,
        "generated_by": "deterministic",
        "fallback_reason": reason,
    }
