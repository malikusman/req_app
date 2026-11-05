"""Evidence-backed workflow detail inside the existing dossier, not a second agent.

Unknown facts stay unknown. Planning groups meaningful gaps rather than scheduling
one question per field. Old slot dossiers remain readable by existing report jobs.
"""
from __future__ import annotations

import hashlib
import json
import re
from typing import Any
from app.dossier import clean_effort, combine_effort, effort_complete, missing_effort_half

FIELDS = ("trigger_inputs", "steps_decisions", "tools", "frequency_volume",
          "active_effort", "exceptions", "dependencies", "output_recipient")
DISCOVERY_FIELDS = ("bottlenecks",)
GLOBAL_FIELDS = ("ai_current_usage", "role_potential")
LABELS = {
    "trigger_inputs": "what starts it and the information received",
    "steps_decisions": "the actual steps and important checks or decisions",
    "tools": "the tools used in those steps",
    "frequency_volume": "how often it happens and roughly how much work arrives",
    "active_effort": "roughly how much of their own working time it takes, excluding waiting",
    "exceptions": "what happens when something goes wrong or is difficult",
    "dependencies": "who approves, supplies information or receives a handoff",
    "output_recipient": "what finished work looks like and who receives it",
    "bottlenecks": "the step that creates avoidable work, repeated entry or waiting, rather than just what can go wrong",
}


def ledger(bb: dict) -> dict:
    return bb.setdefault("dossier", {}).setdefault("workflow", {
        "version": 1, "tasks": [], "revision": 0, "confirmation": None,
    })


def enabled(bb: dict) -> bool:
    return isinstance((bb.get("dossier") or {}).get("workflow"), dict)


def _normal(text: Any) -> str:
    return " ".join(str(text or "").casefold().split())


def _same_passage(left: dict, right: dict) -> bool:
    if not left.get("source_hash") or left.get("source_hash") != right.get("source_hash"):
        return False
    a, b = _normal(left.get("quote")), _normal(right.get("quote"))
    return min(len(a), len(b)) >= 12 and (a in b or b in a)


def explicit_approval(text: Any) -> bool:
    text = _normal(text).replace("’", "'")
    # Accept natural agreement, but never swallow a correction or new work.
    # Only confirmation-only trailing clauses are allowed; a leading 'yes'
    # cannot turn 'yes, but ...' or 'yes, I also ...' into approval.
    text = re.sub(r"[,.!; ]*(?:nothing (?:major |else |more )?to add(?: right now)?)[.! ]*$", "", text).strip(" ,.!;")
    text = re.sub(r"[,.;! ]*(?:and )?i (?:don't|do not) have anything(?: major| else| more)? to add(?: right now)?[.! ]*$", "", text).strip(" ,.!;")
    if re.search(r"\b(but|except|however|also|mostly|missing|correction|wrong|incorrect|change|add|not|actually|instead|yet)\b", text):
        return False
    coverage = r"(?:i think )?you(?:'ve| have) covered [^.!;]+"
    if re.fullmatch(coverage, text):
        return True
    text = re.sub(r"[.!;]+\s*" + coverage + r"$", "", text).strip(" ,.!;")
    return bool(re.fullmatch(
        r"(?:(?:yes|yeah|yep)[,!. ]*)?(?:"
        r"(?:that|it|this)(?:'s| is| looks| sounds)? (?:correct|accurate|right|good)(?: to me)?|"
        r"(?:it|that|the summary) reflects(?: my work)?|"
        r"correct|confirmed|accurate|looks (?:right|good)|all correct|yes|yeah|yep|نعم|صحيح)", text, re.I))


def preference_supported(anchor: dict, state: dict) -> bool:
    """A pain point is not evidence of what the employee wants to do instead."""
    quote = str(anchor.get("quote") or "")
    direct_answer = anchor.get("answering_slot") == "role_potential" or ((((state.get("blackboard") or {}).get("last_beat") or {}).get("slot") == "role_potential" and any(
        s["id"] == anchor.get("message_id") and s["text"] == str(state.get("user_message") or "") for s in sources(state))))
    return direct_answer or bool(re.search(
        r"\b(would (?:like|prefer|simplify|automate|focus)|want|wish|hope|prefer|"
        r"if I had (?:more|extra) time|freed time|free up (?:my |more )?time)\b", quote, re.I))


def sources(state: dict) -> list[dict]:
    """Only employee utterances are evidence; retrieved colleague facts aren't."""
    result = []
    area, task_id = None, None
    for item in state.get("history") or []:
        if item.get("role") == "assistant":
            area, task_id = item.get("area"), item.get("task_id")
        if item.get("role") == "user" and str(item.get("content") or "").strip():
            result.append({"id": item.get("message_id"), "text": str(item["content"]),
                           "answering_area": area, "answering_task_id": task_id})
    text = str(state.get("user_message") or "").strip()
    # Rails' opening system message is a generated profile recap, not another
    # employee answer. Prefer the original profiling messages as evidence.
    source_id = state.get("source_message_id")
    profile_recap = (state.get("question_count", 0) == 0 and source_id is not None
                     and bool(result) and not any(s["id"] == source_id for s in result))
    already_recorded = any(s["id"] == source_id for s in result) if source_id is not None else any(s["text"] == text for s in result)
    if text and not profile_recap and not already_recorded:
        beat = (state.get("blackboard") or {}).get("last_beat") or {}
        result.append({"id": state.get("source_message_id"), "text": text,
                       "answering_area": beat.get("area"), "answering_task_id": beat.get("task_id")})
    return result


def _task_words(text: Any) -> set:
    generic = {"daily", "weekly", "monthly", "annual", "work", "task", "supplier"}
    return {re.sub(r"(?:ing|es|s)$", "", w) if len(w) > 4 else w
            for w in re.findall(r"\w+", str(text or "").casefold()) if w not in generic}


def belongs_to_task(anchor: dict, task: dict, state: dict) -> bool:
    """Message identity proves provenance, not that a fact belongs to this task.
    Enforce the answered workflow before accepting a model's attribution.
    """
    available = sources(state)
    source = next((s for s in available if anchor.get("message_id") is not None and s["id"] == anchor["message_id"]), None)
    if source is None:
        source = next((s for s in available if hashlib.sha256(s["text"].encode()).hexdigest() == anchor.get("source_hash")), None)
    if not source:
        return True  # Historical evidence may lie outside the raw-message window.
    area, task_id = source.get("answering_area"), source.get("answering_task_id")
    if not area and not task_id:
        return True  # Backward-compatible unscoped historical messages.
    names = [task["name"]] + task.get("previous_names", [])
    if task_id == task["id"] or any(_normal(area) == _normal(name) for name in names):
        return True
    # Employees may describe several workflows in one answer. Permit another
    # task only when they actually name it, not because the model copied the
    # currently described process into every required record.
    for name in names:
        target = _task_words(name)
        if _normal(name) in _normal(source["text"]) or (len(target) >= 2 and target <= _task_words(source["text"])):
            return True
    return False


def evidence(quote: Any, state: dict, message_id: Any = None) -> dict | None:
    quote = str(quote or "").strip()
    for source in reversed(sources(state)):
        exact = len(quote) >= 3 and _normal(quote) in _normal(source["text"])
        reference = message_id is not None and source["id"] is not None and str(message_id) == str(source["id"])
        if exact or reference:
            return {"quote": (quote if exact else source["text"])[:3000], "message_id": source["id"],
                    "match": "exact_quote" if exact else "message_reference",
                    "answering_slot": (((state.get("blackboard") or {}).get("last_beat") or {}).get("slot")
                                      if source["text"] == str(state.get("user_message") or "") else None),
                    "source_hash": hashlib.sha256(source["text"].encode()).hexdigest(),
                    "turn": state.get("question_count", 0)}
    return None


def sufficient_fact(field: str, fact: dict, anchor: dict, task: dict, state: dict) -> bool:
    """A nonempty string is not sufficient evidence of time or an actual process."""
    value = str(fact.get("value") or "")
    said = str(anchor.get("quote") or "")
    if field in ("active_effort", "frequency_volume") and fact.get("status", "known") in ("unavailable", "not_applicable"):
        # A missing estimate is a gap to ask about, not proof the employee
        # cannot estimate it. Respect an explicit inability without inventing it.
        return bool(re.search(r"\b(cannot|can't|unable|don't know|do not know|not sure|unsure|unknown|depends|varies|hard to say|no idea|not applicable|don't track|do not track|haven't measured|have not measured|haven't timed|have not timed|no estimate|no (?:fixed|set|regular|consistent|typical|reliable) (?:time|frequency|schedule|duration|estimate))\b", said, re.I))
    if field in ("exceptions", "bottlenecks") and fact.get("status", "known") in ("unavailable", "not_applicable"):
        # 'No exceptions mentioned' is the model's observation, not the
        # employee saying none occur or that they cannot describe them.
        return bool(re.search(r"\b(no|none|never|not|nothing|cannot|can't|unable|don't|do not|haven't)\b", said, re.I))
    if fact.get("status", "known") != "known":
        return True
    if field == "exceptions":
        if not re.search(r"\b(error\w*|incorrect|wrong|mismatch\w*|missing|discrepanc\w*|unmatch\w*|partial|unclear|fail\w*|reject\w*|problem\w*|delay\w*|late|if|unless|go\w* wrong)\b", said, re.I):
            return False
        if (re.search(r"\b(?:fix|correct|resolve) (?:any |the )?(?:mismatches|discrepancies)\b", said, re.I)
                and not re.search(r"\b(contact\w*|ask\w*|back to|hold\w*|paus\w*|flag\w*|escalat\w*|trac\w*|investigat\w*|recheck\w*|adjust\w*|revers\w*|resubmit\w*|retry|source record\w*)\b", said, re.I)):
            return False  # 'Fix mismatches' gives no explanation of how.
    if field == "active_effort":
        # 'Most of my time goes into invoices' ranks responsibilities; it gives
        # no estimate of working time and must not satisfy the effort question.
        duration = r"(?:\b(?:minutes?|mins?|hours?|hrs?|days?|morning|afternoon)\b|\b\d+(?:\.\d+)?\s*[hm]\b)"
        return bool(re.search(duration, value, re.I) and re.search(duration, said, re.I))
    if field == "frequency_volume":
        cadence = r"\b(hours?|days?|weeks?|months?|quarters?|years?|hourly|daily|weekly|monthly|quarterly|annually|annual|yearly|morning|afternoon|evening|night|monday|tuesday|wednesday|thursday|friday|saturday|sunday|ad hoc|as needed|on request|occasionally|irregular)\b"
        return bool(re.search(cadence, value, re.I) and re.search(cadence, said, re.I))
    if field == "trigger_inputs":
        return bool(re.search(r"\b(receiv\w*|arriv\w*|request\w*|start\w*|trigger\w*|export\w*|download\w*|pull\w*|(?:come|comes|came) in|sent|send\w*|submitted|get|given|when|after|first|deadline|monthly|weekly|daily|month end|end of (?:the |each )?month)\b", said, re.I))
    if field == "steps_decisions":
        if re.fullmatch(r"(?:I\s+)?(?:(?:just|usually|simply|normally|mainly)\s+)*(?:check|process|handle|do|review|work on)\s+(?:them|it|those|things|the work)[.! ]*", said.strip(), re.I):
            return False  # A scoped reply can still be an empty description.
        if (re.search(r"\bonce\b.{0,30}\b(done|finished|completed|processed)\b", said, re.I)
                and not re.search(r"\b(check\w*|compar\w*|verif\w*|validat\w*|match\w*)\b", said, re.I)):
            return False  # Describing what happens after processing is not processing.
        source = next((s for s in sources(state) if s["id"] is not None and s["id"] == anchor.get("message_id")), None)
        if source and hashlib.sha256(source["text"].encode()).hexdigest() != anchor.get("source_hash"):
            source = None
        if source is None:
            return not bool(re.search(r"\b(most of my time|mainly handle|spend most)\b", str(anchor.get("quote") or ""), re.I))
        if source is None or (not source.get("answering_area") and not source.get("answering_task_id")):
            text = source["text"] if source else str(anchor.get("quote") or "")
            # An unscoped list of responsibilities is not an ordered workflow.
            if re.search(r"\b(most of my time|mainly handle|mostly (?:deal|handle|work)|responsibilit\w*|spend most)\b", text, re.I):
                return bool(re.search(r"\b(first|then|after|before|once|next|finally)\b", text, re.I))
            if not re.search(r"\b(first|then|after|before|once|next|finally)\b", text, re.I):
                actions = re.findall(r"\b(receiv\w*|export\w*|compar\w*|check\w*|validat\w*|enter\w*|updat\w*|post\w*|send\w*|email\w*|approv\w*|match\w*|investigat\w*)\b", text, re.I)
                if len(set(a.casefold() for a in actions)) < 3:
                    return False  # A task title/output announcement is not its workflow.
    return True


def merge(bb: dict, capture: dict, state: dict) -> int:
    """Validate and merge all supplied task facts, retaining revisions/corrections."""
    if "workflow_updates" not in capture and not enabled(bb):
        return 0
    data = ledger(bb)
    # Upgrading a live historical interview must not silently forget workflows
    # already named before this ledger existed. Facts still need original evidence.
    if not data.get("legacy_imported"):
        for area in bb.get("role_areas") or []:
            if area.get("name") and not any(_normal(area["name"]) == _normal(t["name"]) for t in data["tasks"]):
                data["tasks"].append({"id": f"task-{len(data['tasks']) + 1}", "name": area["name"],
                                      "importance": "important", "facts": {}, "origin": "legacy_area"})
        data["legacy_imported"] = True
    before = _normal(review_text(bb))
    # Revalidate historical preferences too: old message-reference extraction
    # could attach a fabricated aspiration to a genuine, unrelated pain point.
    preference = data.get("global_facts", {}).get("role_potential")
    if preference and preference.get("status") == "known" and not preference_supported(preference.get("evidence") or {}, state):
        data.setdefault("invalidated_globals", []).append({"field": "role_potential", "fact": preference})
        del data["global_facts"]["role_potential"]
        bb.get("dossier", {}).get("slots", {}).pop("role_potential", None)
    for task in data["tasks"]:
        for field, fact in list(task.get("facts", {}).items()):
            if not belongs_to_task(fact["evidence"], task, state) or not sufficient_fact(field, fact, fact["evidence"], task, state):
                task.setdefault("invalidated_facts", []).append({"field": field, "fact": fact, "reason": "different_workflow_source"})
                del task["facts"][field]
    for update in (capture.get("workflow_updates") or [])[:12]:
        if not isinstance(update, dict):
            continue
        name = str(update.get("name") or "").strip()[:100]
        if not name:
            continue
        task = next((t for t in data["tasks"] if str(t["id"]) == str(update.get("id"))
                     or _normal(name) == _normal(t["name"])), None)
        anchor = evidence(update.get("evidence"), state, update.get("source_message_id"))
        if task is None:
            if not anchor or len(data["tasks"]) >= 12:
                continue
            if (re.search(r"\b(would|wish|want to|could|if I had)\b", anchor["quote"], re.I)
                    and not re.search(r"\b(currently|already|I also (?:do|prepare|process|handle|manage))\b", anchor["quote"], re.I)):
                continue  # Aspirations belong to role_potential, not current work.
            task = {"id": f"task-{len(data['tasks']) + 1}", "name": name,
                    "importance": "important", "facts": {}, "evidence": anchor}
            data["tasks"].append(task)
        elif update.get("rename") is True and anchor:
            task.setdefault("previous_names", []).append(task["name"])
            task["name"] = name
        if anchor and update.get("importance") in ("important", "supporting"):
            task["importance"] = update["importance"]
        facts = update.get("facts") or {}
        if not isinstance(facts, dict):
            continue
        for field in FIELDS + DISCOVERY_FIELDS:
            fact = facts.get(field)
            if not isinstance(fact, dict):
                continue
            anchor = evidence(fact.get("evidence"), state, fact.get("source_message_id"))
            value = str(fact.get("value") or "").strip().lstrip("/ ")[:1500]
            status = fact.get("status", "known")
            if field == "bottlenecks" and re.search(r"\bno\s+(?:other\s+)?(?:(?:significant|major|real)\s+)?bottlenecks?\b", str((anchor or {}).get("quote") or ""), re.I):
                status = "not_applicable"
            if not anchor or not belongs_to_task(anchor, task, state) or not value or status not in ("known", "uncertain", "unavailable", "not_applicable") or not sufficient_fact(field, fact, anchor, task, state):
                continue
            if field not in ("tools", "dependencies"):
                # A provenance ID proves the employee said something, not that
                # one process's cost/steps apply to every task in that message.
                reused = any(other["id"] != task["id"] and
                             _same_passage(other.get("facts", {}).get(field, {}).get("evidence") or {}, anchor)
                             for other in data["tasks"])
                named = any(_normal(name) in _normal(anchor["quote"]) for name in [task["name"]] + task.get("previous_names", []))
                if reused and not named:
                    continue
            old = task["facts"].get(field)
            effort = clean_effort(fact.get("effort")) if field in ("active_effort", "bottlenecks") and status == "known" else None
            unavailable_cost = False
            if field == "bottlenecks":
                source = next((s["text"] for s in sources(state) if hashlib.sha256(s["text"].encode()).hexdigest() == anchor["source_hash"]), anchor["quote"])
                # The qualifier may follow the quoted clause in the same
                # sentence. Keep a known problem with an unknown cost, instead
                # of repeatedly demanding an estimate the employee cannot give.
                unavailable_cost = any(_normal(anchor["quote"]) in _normal(sentence) and re.search(
                    r"\b(cannot|can't|unable to|do not|don't)\b.{0,35}\b(estimate|quantify)\b", sentence, re.I)
                    for sentence in re.split(r"[.!?]\s+", source))
            if effort and old and not fact.get("correction"):
                effort = combine_effort(old.get("effort"), effort)
            same_availability = bool((old or {}).get("cost_unavailable")) == unavailable_cost
            if old and same_availability and _normal(old["value"]) == _normal(value) and old["status"] == status and (not effort or effort == old.get("effort")):
                continue
            if (old and same_availability and old["status"] == status and not fact.get("correction")
                    and _normal(old["evidence"]["quote"]) == _normal(anchor["quote"])
                    and (not effort or effort == old.get("effort")) and field != "steps_decisions"):
                continue  # Re-extraction wording changes are not new information.
            new = {"value": value, "status": status, "evidence": anchor}
            if unavailable_cost:
                new["cost_unavailable"] = True
            if effort:
                new["effort"] = effort
            if old:
                new["history"] = (old.get("history", []) + [{k: v for k, v in old.items() if k != "history"}])[-12:]
                # A contradiction is unresolved unless the employee explicitly corrected it.
                if fact.get("contradiction") is True and fact.get("correction") is not True:
                    new["status"] = "conflict"
            task["facts"][field] = new
    global_updates = dict(capture.get("global_facts") or {})
    current_text = str(state.get("user_message") or "")
    answering_slot = ((state.get("blackboard") or {}).get("last_beat") or {}).get("slot")
    priority_scope = re.search(r"\b(improvement|simplif\w*|automat\w*)\b", current_text, re.I) or answering_slot == "role_potential"
    if (priority_scope and re.search(r"\b(no|do not have|don't have|have not chosen|haven't chosen|have not decided|haven't decided)\b.{0,50}\b(preference|priority)\b", current_text, re.I)
            and not re.search(r"\b(but|except)\b", current_text, re.I)):
        # An explicit refusal/unknown is useful information, even if the recorder
        # returned null. Preserve the actual words and don't ask again.
        global_updates["role_potential"] = {"value": current_text, "status": "unavailable",
                                             "evidence": current_text, "source_message_id": state.get("source_message_id")}
    for field, fact in global_updates.items():
        if field not in GLOBAL_FIELDS or not isinstance(fact, dict):
            continue
        anchor = evidence(fact.get("evidence"), state, fact.get("source_message_id"))
        value = str(fact.get("value") or "").strip()
        status = fact.get("status", "known")
        answering = ((state.get("blackboard") or {}).get("last_beat") or {}).get("slot")
        if field == "role_potential" and status == "known" and anchor and not preference_supported(anchor, state):
            continue
        if field == "role_potential" and status == "known" and anchor:
            # Keep their actual preference, rather than generated first-person
            # intentions that can introduce unsupported motivations or benefits.
            value = anchor["quote"]
        if field == "ai_current_usage" and answering != field and anchor:
            if not re.search(r"\b(AI|ChatGPT|Copilot|Gemini|Claude|artificial intelligence)\b", anchor["quote"], re.I):
                continue
        if anchor and value and status in ("known", "uncertain", "unavailable", "not_applicable"):
            old = data.setdefault("global_facts", {}).get(field)
            if fact.get("contradiction") is True and fact.get("correction") is not True:
                status = "conflict"
            if not old or _normal(old["value"]) != _normal(value) or old["status"] != status:
                new = {"value": value, "status": status, "evidence": anchor}
                if old:
                    new["history"] = (old.get("history", []) + [{k: v for k, v in old.items() if k != "history"}])[-12:]
                data["global_facts"][field] = new
    # Evidence revisions and audit history are retained, but only a changed
    # visible profile invalidates the summary the employee is confirming.
    changed = before != _normal(review_text(bb))
    if changed:
        data["revision"] += 1
        data["confirmation"] = None
    confirmation = capture.get("summary_confirmed")
    current = str(state.get("user_message") or "").strip()
    # Confirmation applies only to the summary actually shown, with no changed facts.
    approval = explicit_approval(current)
    shown = data.get("presented_summary") or {}
    previous = next((m for m in reversed(state.get("history") or []) if m.get("role") == "assistant"
                     and shown.get("sha256") and hashlib.sha256(str(m.get("content") or "").encode()).hexdigest() == shown["sha256"]), {})
    delivered = bool(previous)
    if (bb.get("last_phase") == "review" and not changed and delivered
            and review_matches(bb, shown)):
        # Historical snapshots may have advanced an audit revision while the
        # exact displayed profile stayed unchanged. Confirm that same content.
        data["review_revision"] = data["revision"]
        shown["revision"] = data["revision"]
    if (bb.get("last_phase") == "review" and not changed and approval
            and delivered and confirmation is not False and data.get("review_revision") == data["revision"]):
        data["confirmation"] = {"revision": data["revision"], "turn": state.get("question_count", 0),
                                "summary_sha256": (data.get("presented_summary") or {}).get("sha256"),
                                "summary_message_id": previous.get("message_id"),
                                "evidence": evidence(current, state)}
    return int(changed)


def gaps(task: dict) -> list[str]:
    facts = task.get("facts") or {}
    # Explicitly unavailable information is recorded, never repeatedly demanded.
    return [f for f in FIELDS if f not in facts or facts[f].get("status") in ("uncertain", "conflict")]


def requirements(bb: dict) -> list[tuple[dict, list[str]]]:
    return [(t, gaps(t)) for t in ledger(bb)["tasks"] if t.get("importance") != "supporting"]


def global_answered(bb: dict, field: str) -> bool:
    fact = ledger(bb).get("global_facts", {}).get(field)
    if fact:
        return fact.get("status") in ("known", "unavailable", "not_applicable")
    old = bb.get("dossier", {}).get("slots", {}).get(field) or {}
    return bool(old.get("value")) and float(old.get("confidence") or 0) >= .6


def discovery_beat(bb: dict, *, optional_details: bool = True) -> dict | None:
    """Restore documented friction/cost and opportunity discovery without a
    questionnaire per task. Cost at most two explicitly described bottlenecks.
    """
    tasks = [t for t in ledger(bb)["tasks"] if t.get("importance") != "supporting"]
    explored = [t for t in tasks if t.get("facts", {}).get("bottlenecks")]
    if tasks and not explored:
        return {"slot": "workflow", "fields": ["bottlenecks"], "area": None,
                "intent": "Across the workflows already described, identify the most time-consuming repetitive step or delay. Do not ask them to repeat the workflow or its exceptions."}
    for task in [t for t in explored if t["facts"]["bottlenecks"]["status"] == "known" and optional_details][:2]:
        fact = task["facts"]["bottlenecks"]
        if not effort_complete(fact) and not fact.get("cost_unavailable"):
            half = missing_effort_half(fact)
            return {"slot": "workflow", "area": task["name"], "task_id": task["id"],
                    "fields": ["bottleneck_effort"], "missing_half": half,
                    "intent": f"Quantify ONLY this bottleneck: {fact['value']}. "
                              + (f"Ask only its missing {half}; the other half is captured. " if half else "Ask how often it occurs and their extra active time, excluding waiting. ")
                              + "Do not confuse it with the full workflow's working time; accept an unavailable estimate."}
    for field in GLOBAL_FIELDS:
        if field == "role_potential" and not optional_details:
            continue  # Preserve an unknown preference; never invent one to finish.
        if not global_answered(bb, field):
            intent = ("Whether they already use AI for the work or bottleneck described; a clear no is a complete answer."
                      if field == "ai_current_usage" else
                      "Which repetitive step they would most like simplified and what useful work the freed time would allow. Capture their priorities; do not ask them to design an AI system or suggest replacing their job.")
            return {"slot": field, "area": None, "intent": intent}
    return None


def next_decision(bb: dict, limits: dict, count: int) -> dict:
    data = ledger(bb)
    important = requirements(bb)
    confirmation = data.get("confirmation") or {}
    # After a focused interview, optional empty fields must not turn a good
    # process profile into a questionnaire. Essential gaps and contradictions
    # still get a targeted follow-up, even beyond the soft question target.
    essential_fields = {"trigger_inputs", "steps_decisions", "tools", "frequency_volume", "active_effort", "output_recipient"}
    def needs_exception_path(task):
        steps = task.get("facts", {}).get("steps_decisions", {}).get("value", "")
        return bool(re.search(r"\b(check\w*|compar\w*|match\w*|validat\w*|verif\w*|approv\w*)\b", steps, re.I))
    missing = [(task, [f for f in fields if count < 8 or f in essential_fields
                       or (f == "exceptions" and needs_exception_path(task))
                       or task.get("facts", {}).get(f, {}).get("status") == "conflict"])
               for task, fields in important]
    missing = [(task, fields) for task, fields in missing if fields]
    discovery = discovery_beat(bb, optional_details=count < 8) if important and not missing else None
    if important and not missing and not discovery and confirmation.get("revision") == data["revision"]:
        essential = [{"task": t["name"], "missing": [f for f in ("trigger_inputs", "steps_decisions", "output_recipient")
                      if t["facts"].get(f, {}).get("status") not in ("known", "not_applicable")]}
                     for t, _ in important]
        essential = [t for t in essential if t["missing"]]
        data["outcome"] = "needs_follow_up" if essential else "successful"
        data["follow_up"] = essential
        return {"phase": "close", "beat": None, "should_close": True,
                "close_reason": "insufficient_information" if essential else "dossier_complete"}
    if count >= limits["max_questions"] or bb.get("stall_turns", 0) >= max(3, limits["stall_turns"]):
        reason = "ceiling" if count >= limits["max_questions"] else "stalled"
        data["outcome"] = "needs_follow_up"
        data["follow_up"] = [{"task": t["name"], "missing": f} for t, f in missing]
        return {"phase": "close", "beat": None, "should_close": True, "close_reason": reason}
    if not important:
        return {"phase": "orient", "beat": None, "should_close": False}
    if not missing and discovery:
        return {"phase": "branch", "beat": discovery, "should_close": False}
    if not missing:
        data["review_revision"] = data["revision"]
        return {"phase": "review", "beat": {"slot": "workflow_review", "intent": "Confirm or correct the summary"}, "should_close": False}
    # Finish an actual process before rotating; don't split related facts into a questionnaire.
    priority = {"steps_decisions": 100, "trigger_inputs": 90, "output_recipient": 90,
                "tools": 50, "frequency_volume": 45, "active_effort": 40,
                "exceptions": 35, "dependencies": 35}
    task, fields = max(missing, key=lambda item: max(priority[f] for f in item[1]))
    groups = (("trigger_inputs", "steps_decisions", "output_recipient"),
              ("tools", "frequency_volume", "active_effort"), ("exceptions", "dependencies"))
    selected = next([f for f in group if f in fields] for group in groups if any(f in fields for f in group))
    # Explore friction alongside exception handling, instead of scheduling a
    # second broad pass over the same process after its details are complete.
    if "exceptions" in selected and not any(t.get("facts", {}).get("bottlenecks") for t, _ in important):
        selected.append("bottlenecks")
    intent = "; ".join(LABELS[f] for f in selected)
    exception_context = None
    if "exceptions" in selected:
        steps = task.get("facts", {}).get("steps_decisions", {}).get("value", "")
        exception_context = "approval" if re.search(r"\bapprov\w*\b", steps, re.I) else "matching" if re.search(r"\b(compar\w*|match\w*)\b", steps, re.I) else None
        intent += ". Ask how a failed check is actually resolved; do not ask them to describe the normal workflow again."
    return {"phase": "branch", "should_close": False,
            "beat": {"slot": "workflow", "area": task["name"], "task_id": task["id"],
                     "fields": selected, "intent": intent, "exception_context": exception_context}}


def prompt_context(bb: dict) -> str:
    if not enabled(bb):
        return "No structured workflows yet."
    # Revision history and previously presented summaries are audit records, not
    # current facts. Feeding them back as truth reintroduced corrected details.
    return json.dumps({"global_facts": {field: {k: v for k, v in fact.items() if k != "history"}
                                       for field, fact in ledger(bb).get("global_facts", {}).items()}, "tasks": [{"id": t["id"], "name": t["name"], "importance": t.get("importance"),
                                  "facts": {field: {k: v for k, v in fact.items() if k != "history"}
                                            for field, fact in t.get("facts", {}).items()}}
                                 for t in ledger(bb)["tasks"]]}, ensure_ascii=False)


def capture_schema(bb: dict) -> dict:
    """Require an explicit known/unknown choice per field, not optional prose keys."""
    def obj(properties: dict) -> dict:
        return {"type": "object", "properties": properties, "required": list(properties), "additionalProperties": False}
    text = {"type": "string"}
    fact = obj({"value": text, "status": {"type": "string", "enum": ["known", "uncertain", "unavailable", "not_applicable"]},
                "evidence": text, "source_message_id": {"type": ["integer", "null"]},
                "correction": {"type": "boolean"}, "contradiction": {"type": "boolean"}})
    task = obj({"name": text, "rename": {"type": "boolean"},
                "importance": {"type": "string", "enum": ["important", "supporting"]},
                "evidence": text, "source_message_id": {"type": ["integer", "null"]},
                "facts": obj({field: {"anyOf": [fact, {"type": "null"}]} for field in FIELDS + DISCOVERY_FIELDS})})
    measure = obj({"as_said": {"type": ["string", "null"]}, "min": {"type": ["number", "null"]},
                   "max": {"type": ["number", "null"]}, "unit": {"type": ["string", "null"]}})
    effort = obj({"frequency": {"anyOf": [measure, {"type": "null"}]},
                  "duration": {"anyOf": [measure, {"type": "null"}]},
                  "effort_type": {"type": "string", "enum": ["active", "waiting", "mixed", "unknown"]}})
    timed_fact = {**fact, "properties": {**fact["properties"], "effort": {"anyOf": [effort, {"type": "null"}]}},
                  "required": fact["required"] + ["effort"]}
    task["properties"]["facts"]["properties"]["active_effort"] = {"anyOf": [timed_fact, {"type": "null"}]}
    task["properties"]["facts"]["properties"]["bottlenecks"] = {"anyOf": [timed_fact, {"type": "null"}]}
    tasks = ((bb.get("dossier") or {}).get("workflow") or {}).get("tasks") or []
    schema = obj({"workflow_updates": obj({t["id"]: task for t in tasks}),
                  "new_tasks": {"type": "array", "items": task},
                  "global_facts": obj({field: {"anyOf": [fact, {"type": "null"}]} for field in GLOBAL_FIELDS}),
                  "insight": obj({"summary": text, "topics": {"type": "array", "items": text}}),
                  "wants_to_stop": {"type": "boolean"}, "summary_confirmed": {"type": "boolean"},
                  "updated_summary": {"type": ["string", "null"]}})
    return {"type": "json_schema", "json_schema": {"name": "workflow_capture", "strict": True, "schema": schema}}


def review_text(bb: dict) -> str:
    lines = ["Here’s my understanding of your work:"]
    stop = set("a an the and or to of for with in on by it their they this that when as is are from them".split())
    def words(text: str) -> set:
        return {w.rstrip("s") if len(w) > 4 else w for w in re.findall(r"\w+", text.casefold()) if w not in stop}
    for task in ledger(bb)["tasks"]:
        if task.get("importance") == "supporting":
            continue
        facts = task.get("facts") or {}
        details = []
        covered = set()
        # Present the process first. Tools, recipients and approvals often already
        # appear in those steps; don't repeat them as separate checklist entries.
        for field in ("trigger_inputs", "steps_decisions", "frequency_volume", "active_effort",
                      "exceptions", "dependencies", "output_recipient", "tools", "bottlenecks"):
            fact = facts.get(field)
            if not fact:
                continue
            value = fact["value"].strip().rstrip(".;")
            tokens = words(value)
            if (field in ("exceptions", "dependencies", "output_recipient", "tools")
                    and tokens and len(tokens & covered) / len(tokens) >= .8):
                continue
            annotation = " (unavailable)" if fact["status"] == "unavailable" else " (uncertain)" if fact["status"] in ("uncertain", "conflict") else ""
            label = {"trigger_inputs": "Start", "steps_decisions": "Steps",
                     "frequency_volume": "Frequency / volume", "active_effort": "Active time",
                     "exceptions": "Exceptions", "dependencies": "Handoffs / approvals",
                     "output_recipient": "Output", "tools": "Tools"}.get(field, "Bottleneck")
            if field == "bottlenecks":
                label = "Bottleneck"
            details.append(f"{label}: {value[0].upper() + value[1:]}{annotation}.")
            if field == "bottlenecks" and fact.get("effort"):
                effort = fact["effort"]
                parts = [str((effort.get(side) or {}).get("as_said") or "") for side in ("frequency", "duration")]
                parts = [p for p in parts if p and p.casefold() not in value.casefold()]
                if parts:
                    label = "Waiting time" if effort.get("effort_type") == "waiting" else "Extra active effort"
                    details.append(label + ": " + "; ".join(parts) + ".")
            covered.update(tokens)
        lines.append(f"• {task['name']}\n" + "\n".join(details))
    for field, label in (("ai_current_usage", "Current AI use"), ("role_potential", "Improvement priority")):
        fact = ledger(bb).get("global_facts", {}).get(field)
        if fact:
            lines.append(f"{label}: {fact['value']}" if fact.get("status") == "known" else f"{label}: Unknown — {fact['value']}")
        else:
            lines.append(f"{label}: Unknown — not provided.")
    lines.append("Is this accurate, including any important periodic or behind-the-scenes work, or should I correct or add anything?")
    message = "\n\n".join(lines)
    return message


def review_message(bb: dict) -> str:
    message = review_text(bb)
    ledger(bb)["presented_summary"] = {"revision": ledger(bb)["revision"], "text": message,
                                     "sha256": hashlib.sha256(message.encode()).hexdigest()}
    return message


def review_matches(bb: dict, shown: dict) -> bool:
    return bool(shown.get("text")) and _normal(shown["text"]) == _normal(review_text(bb))


def fallback(beat: dict) -> str:
    task = beat.get("area") or "this task"
    fields = beat.get("fields") or []
    if "exceptions" in fields and beat.get("exception_context"):
        people = " and who helps resolve it" if "dependencies" in fields else ""
        friction = " and which part causes the most avoidable work or waiting" if "bottlenecks" in fields else ""
        if beat["exception_context"] == "approval":
            return f"For {task}, what happens if a required approval or detail is missing{people}{friction}?"
        return f"For {task}, how do you find and resolve a difference when the figures or records don’t match{people}{friction}?"
    if fields == ["bottlenecks"]:
        return "Across these workflows, which repetitive step or delay costs you the most avoidable time?"
    if fields == ["bottleneck_effort"]:
        if beat.get("missing_half") == "duration":
            return f"For that bottleneck in {task}, roughly how much extra working time does each occurrence take?"
        if beat.get("missing_half") == "frequency":
            return f"How often does that bottleneck in {task} occur?"
        return f"For that bottleneck in {task}, how often does it occur and roughly how much extra working time does it take?"
    if set(fields) == {"trigger_inputs", "steps_decisions", "output_recipient"}:
        return f"Could you walk me through {task}, from what starts it to the finished result and who receives it?"
    if set(fields) == {"exceptions", "dependencies"}:
        return f"When {task} doesn’t go to plan, how do you resolve it and who else is involved?"
    phrases = {
        "trigger_inputs": "what starts it and what you receive",
        "steps_decisions": "the steps you take, including important checks",
        "output_recipient": "what you produce and who receives it",
        "tools": "which tools you use",
        "frequency_volume": "roughly how often it happens and how much you handle",
        "active_effort": "roughly how much of your own working time it takes",
        "exceptions": "what you do when something goes wrong",
        "dependencies": "who else needs to provide information or approve the work",
        "bottlenecks": "which part creates the most avoidable work or waiting",
    }
    return f"For {task}, could you describe " + ", and ".join(phrases[f] for f in fields) + "?"


def project_slots(bb: dict) -> None:
    """Keep existing reports/findings compatible while retaining the richer dossier."""
    slots = bb["dossier"].setdefault("slots", {})
    tasks = [t for t in ledger(bb)["tasks"] if t.get("importance") != "supporting"]
    bb["role_areas"] = [{"name": t["name"]} for t in tasks]
    for field, fact in ledger(bb).get("global_facts", {}).items():
        slots[field] = {"value": fact["value"], "confidence": .8 if fact["status"] != "uncertain" else .4,
                        "turn": fact["evidence"]["turn"], "evidence": fact["evidence"]}
    for task in tasks:
        name = task["name"]
        if not any(a.get("name") == name for a in bb.setdefault("role_areas", [])):
            bb["role_areas"].append({"name": name})
        facts = task["facts"]
        for slot, fields in (("how_it_works", FIELDS), ("friction", ("bottlenecks",))):
            if slot == "friction" and facts.get("bottlenecks", {}).get("status") != "known":
                old = slots.pop(f"friction::{name}", None)
                if old:
                    ledger(bb).setdefault("superseded_exception_findings", {})[name] = old
                continue
            values = [facts[f]["value"] for f in fields if f in facts]
            if values:
                slots[f"{slot}::{name}"] = {"value": "; ".join(values), "confidence": .8,
                                           "turn": max(f["evidence"]["turn"] for f in facts.values())}
        bottleneck = facts.get("bottlenecks")
        if bottleneck and bottleneck.get("status") == "known":
            # Task effort is not lost time. Only the explicitly described
            # bottleneck cost reaches the existing annual-hours calculator.
            effort = bottleneck.get("effort") or {
                "frequency": None,
                "duration": None,
                "effort_type": "unknown"}
            slots[f"friction_cost::{name}"] = {"value": bottleneck["value"], "confidence": .8,
                "turn": bottleneck["evidence"]["turn"], "effort": effort}
        elif slots.get(f"friction_cost::{name}"):
            old = slots.pop(f"friction_cost::{name}")
            ledger(bb).setdefault("superseded_task_costs", {})[name] = old
