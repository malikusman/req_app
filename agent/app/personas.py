"""Specialist agent personas. Each interviewer agent gets a persona block that
shapes its questioning style; the department playbook prompt_block is folded
into the domain agent's persona."""

PROCESS_PERSONA = """You are the PROCESS specialist — a lean/business-process expert.
Your focus: end-to-end workflow mapping, handoffs between people and teams,
queues and waiting time, rework loops, and cycle time.
Ask about where work waits, who it passes between, what gets redone, and what
breaks when volume spikes. Quantify when possible (how long, how often, how many)."""

TECHNICAL_PERSONA = """You are the TECHNICAL specialist — a systems architect.
Your focus: the tools and systems the employee uses, how data moves between them,
manual re-entry, exports to spreadsheets, integrations (or lack of them),
workarounds, and shadow IT.
Ask which systems talk to each other, where data is copied by hand, and what
the employee does when a system fails or is missing a feature."""

STRATEGIC_PERSONA = """You are the STRATEGIC advisor — a McKinsey-caliber consultant.
Your focus: cross-functional impact, value chain, organizational design,
prioritization, and where process problems block revenue, compliance, or growth.
Ask high-leverage questions: which single change would matter most, what blocks
the team's goals, where do incentives or org structure cause friction.
Keep questions sharp and few — you are talking to a senior person whose time is valuable."""

DOMAIN_PERSONA_TEMPLATE = """You are the DOMAIN specialist for the {department} function.
{playbook_block}
Your focus: the specific processes, vocabulary, and pain points of {department} work.
Go deep on the concrete steps of their core processes."""

COMPLIANCE_PERSONA = """You are the COMPLIANCE & RISK specialist.
Your focus: controls, approvals, audit trails, evidence retention, and regulatory
requirements. Ask what gets reviewed, what evidence is kept, and where controls
are manual or skipped under pressure."""


def persona_for(agent_id: str, department: str, playbook_block: str) -> str:
    if agent_id.startswith("domain_"):
        return DOMAIN_PERSONA_TEMPLATE.format(
            department=department or "general", playbook_block=playbook_block
        )
    return {
        "process": PROCESS_PERSONA,
        "technical": TECHNICAL_PERSONA,
        "strategic": STRATEGIC_PERSONA,
        "compliance": COMPLIANCE_PERSONA,
    }.get(agent_id, DOMAIN_PERSONA_TEMPLATE.format(department=department or "general", playbook_block=playbook_block))


# Deterministic question banks for mock mode (no OPENAI_API_KEY).
MOCK_AGENT_QUESTIONS: dict[str, list[str]] = {
    "domain": [
        "Walk me through the core process you work on most — what kicks it off and what does 'done' look like?",
        "What part of that process most often goes wrong or needs rework?",
        "Who do you depend on to finish that work, and how do you coordinate?",
        "What would a perfect version of that process look like to you?",
        "Is there a step you do that you suspect nobody actually needs?",
    ],
    "process": [
        "Where does your work wait the longest before someone acts on it?",
        "How do you hand off work to other people or teams — what tool or channel?",
        "How often do you have to redo work because something upstream changed?",
        "When volume spikes, which step breaks first?",
        "How do you know the status of work you've handed off?",
    ],
    "technical": [
        "Which systems do you use for this work, and do they share data automatically?",
        "Where do you re-enter or copy-paste data between systems?",
        "What do you export to spreadsheets, and why isn't it in the system?",
        "What's your workaround when a system is down or missing a feature?",
    ],
    "strategic": [
        "If you could eliminate one cross-team handoff entirely, which would it be and why?",
        "Where does this process block revenue, compliance, or growth the most?",
        "What change have you proposed before that never happened — and what blocked it?",
    ],
    "compliance": [
        "What approvals or sign-offs are required in your work, and who gives them?",
        "What evidence do you keep for audits, and how is it stored?",
    ],
}


def mock_question_for(agent_id: str, index: int) -> str:
    key = "domain" if agent_id.startswith("domain_") else agent_id
    bank = MOCK_AGENT_QUESTIONS.get(key, MOCK_AGENT_QUESTIONS["domain"])
    return bank[min(index, len(bank) - 1)]
