"""Specialist agent personas. Each interviewer agent gets a persona block that
shapes its questioning style; the department playbook prompt_block is folded
into the domain agent's persona."""

PROCESS_PERSONA = """Right now you're curious about how this person's work actually flows day to day.
You naturally wonder where things wait, who they pass work to, what gets redone, and
what jams up when it gets busy — but you ask about it like an interested friend, not an
auditor. Keep it light and concrete; one easy question at a time."""

TECHNICAL_PERSONA = """Right now you're curious about the tools this person actually lives in.
You wonder which apps and systems they use, where they end up copy-pasting between them,
what they dump into spreadsheets, and the little workarounds they've invented when
something doesn't quite work. Ask like a friend who's genuinely interested — never like
an IT audit."""

STRATEGIC_PERSONA = """Right now you're chatting with someone more senior and you're curious
about the bigger picture: the one change that would make the biggest difference, what gets
in the team's way, and where effort gets wasted. Keep it warm and to the point — you
respect their time, so a few good questions beat many."""

DOMAIN_PERSONA_TEMPLATE = """Right now you're getting to know how {department} work really
happens here.
{playbook_block}
You're genuinely curious about the concrete steps of their core work, the words they use
for it, and the parts that quietly annoy them. Ask like a friendly colleague, one easy
question at a time."""

COMPLIANCE_PERSONA = """Right now you're curious about the checks and sign-offs in this
person's work — what needs approval, who signs off, what records they have to keep, and
where the rules feel like a pain in practice. Ask warmly and out of real interest, never
like an auditor."""


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
