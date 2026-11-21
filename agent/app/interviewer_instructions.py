"""Configurable AI-interviewer instructions for Employee Discovery V2.

An operator-maintained YAML file (default: app/interviewer/instructions.yaml,
override with INTERVIEWER_INSTRUCTIONS_PATH) shapes HOW the interviewer speaks:
persona, tone, spoken-avatar style, per-phase follow-up guidance, opening
wording for each planned topic, and closing lines.

It cannot change WHAT is collected or WHEN the interview ends. The deterministic
plan in employee_discovery_v2 still picks every topic; generated wording is still
validated (on-plan, on-topic, one question, not repeated, no prohibited content)
and replaced by fixed wording when it fails; structured capture, evidence and
completion (explicit confirmation of the current read-back) stay engine-enforced.
The core CONDUCT_PROMPT always comes first and wins any conflict.

Governance (Document 02): the file is versioned; every turn records the
instructions version and content hash; an invalid or unsafe file is rejected as a
whole and the built-in wording is used, so a bad edit can never break or steer an
interview.
"""
from __future__ import annotations

import hashlib
import logging
import os
import re
import threading
from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, ConfigDict, Field, ValidationError, field_validator, model_validator

DEFAULT_PATH = Path(__file__).parent / "interviewer" / "instructions.yaml"
PHASES = ("anchor", "inventory", "invisible_work", "size_close")
CHECK_KEYS = ("anchor", "weekly", "monthly", "seasonal", "SLOWER_THAN_EXPECTED", "DUPLICATE_ENTRY",
              "CHASING_WAITING", "TRUST_CHECKING", "OUTSIDE_SYSTEMS", "shadow_ai")
MAX_GUIDANCE = 1200
MAX_QUESTION = 300
MAX_LINE = 240

log = logging.getLogger("uvicorn.error")

# Configured text may style the conversation; it must never try to weaken the
# engine's rules. Rejected as a whole file, not silently filtered.
_UNSAFE = [
    (r"\bignore\b.{0,40}\b(?:rules?|instructions?|policy|plan|above|previous|system)\b", "tries to override the core rules"),
    (r"\b(?:skip|omit|don'?t ask|do not ask|never ask)\b.{0,40}\b(?:phase|anchor|inventory|invisible|sizing|size|frequency|effort|read-?back|confirmation|coverage)\b",
     "tries to skip required discovery coverage"),
    (r"\b(?:end|finish|complete|close)\b.{0,30}\b(?:interview|discovery|conversation)\b.{0,40}\b(?:without|before|regardless|early)\b",
     "tries to change completion rules"),
    (r"\b(?:mark|treat|record)\b.{0,30}\b(?:complete|confirmed|successful)\b", "tries to change completion rules"),
    (r"\b(?:password|passcode|api[ -]?key|credentials?|bank (?:account|card)|national id|social security)\b", "mentions credentials or sensitive identifiers"),
    (r"\b(?:automat(?:e|ion|ed)|replace (?:you|your job|staff)|redundan|headcount|layoffs?)\b", "suggests automation or job outcomes"),
    (r"\b(?:manager|management|colleagues?|peers?)\b.{0,30}\b(?:said|says|told|think|thinks|believe|answers?|views?)\b",
     "refers to management or peer views"),
    (r"\b(?:invent|make up|assume|fabricate|guess)\b.{0,30}\b(?:tasks?|work|activities|answers?|facts?|numbers?)\b", "invites invented facts"),
    (r"\b(?:reveal|share|disclose|print)\b.{0,30}\b(?:prompt|instructions|system|data|other (?:employees?|people))\b", "invites data disclosure"),
]


_NEGATED = re.compile(r"\b(?:never|not|no|nor|don'?t|without)\b[\w ,]{0,12}$", re.I)


def _check_safe(text: str, where: str) -> str:
    """Rejects text that tries to weaken a rule. Guidance that states the rule
    ("never invent numbers", "do not suggest automation") is allowed: a match
    directly preceded by a negation is not an instruction to do it."""
    for pattern, reason in _UNSAFE:
        for match in re.finditer(pattern, text, re.I | re.S):
            if not _NEGATED.search(text[max(0, match.start() - 30):match.start()]):
                raise ValueError(f"{where}: {reason}")
    return text


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)


class PhaseGuidance(_Strict):
    purpose: str = Field("", max_length=MAX_GUIDANCE)
    follow_up: str = Field("", max_length=MAX_GUIDANCE)


class TopicGuidance(_Strict):
    """What the interviewer is trying to learn on one planned topic, and what to
    listen for in the answer. Shapes the wording of that topic's question and of
    the reaction to the previous answer; the engine still decides WHEN the topic
    comes up and what is captured."""
    goal: str = Field("", max_length=MAX_GUIDANCE)
    listen_for: str = Field("", max_length=MAX_GUIDANCE)


class Closing(_Strict):
    confirmed: dict[str, str] = Field(default_factory=dict)
    paused: dict[str, str] = Field(default_factory=dict)
    stopped: dict[str, str] = Field(default_factory=dict)

    @field_validator("confirmed", "paused", "stopped")
    @classmethod
    def _lines(cls, value: dict[str, str]):
        for lang, line in value.items():
            if not re.fullmatch(r"[a-z]{2}", lang):
                raise ValueError(f"language code '{lang}' must be two lowercase letters")
            if not line or len(line) > MAX_LINE or "?" in line or "؟" in line:
                raise ValueError(f"closing line for '{lang}' must be 1-{MAX_LINE} characters and not a question")
        return value


class ReadBack(_Strict):
    """Wording around the deterministic read-back. The list itself is always built
    from the captured WorkItems; it cannot be reworded or summarised by a model."""
    intro: dict[str, str] = Field(default_factory=dict)
    closing: dict[str, str] = Field(default_factory=dict)
    confirm: dict[str, str] = Field(default_factory=dict)
    voice_confirm: dict[str, str] = Field(default_factory=dict)

    @field_validator("intro", "closing", "confirm", "voice_confirm")
    @classmethod
    def _lines(cls, value: dict[str, str]):
        for lang, line in value.items():
            if not re.fullmatch(r"[a-z]{2}", lang) or not line or len(line) > MAX_LINE or "\n" in line:
                raise ValueError(f"read_back line for '{lang}' must be one line of 1-{MAX_LINE} characters")
        return value


class FollowUps(_Strict):
    """Bounded contextual follow-ups about an activity the employee just described.

    The engine (not the prompt) decides WHEN a follow-up is allowed, and never
    beyond these limits; required coverage then resumes. `explore` asks at a high
    level what the activity involves (systems, tools, manual vs in-system), never
    process steps, triggers, rules or approvals (Deep Dive, Document 04).
    """
    enabled: bool = False
    phases: list[Literal["anchor", "inventory", "invisible_work"]] = Field(default_factory=lambda: ["anchor", "inventory"])
    max_per_activity: int = Field(2, ge=0, le=3)
    max_total: int = Field(6, ge=0, le=10)
    explore: bool = True
    size_early: bool = True
    guidance: str = Field("", max_length=MAX_GUIDANCE)


class AvatarPhrases(_Strict):
    """Fixed lines the live avatar speaks around engine questions (read by Rails).
    They assert nothing about the employee's answers and never replace a question."""
    greeting: str = Field("", max_length=MAX_LINE)
    resumed: str = Field("", max_length=MAX_LINE)
    rephrase: str = Field("", max_length=MAX_LINE)
    still_working: str = Field("", max_length=MAX_LINE)
    acknowledgements: list[str] = Field(default_factory=list, max_length=12)
    display_name: str = Field("", max_length=40)
    consent: str = Field("", max_length=1200)

    @field_validator("acknowledgements")
    @classmethod
    def _acks(cls, value: list[str]):
        for ack in value:
            if not ack or len(ack) > 60 or "?" in ack:
                raise ValueError("each acknowledgement must be 1-60 characters and not a question")
        return value


class Instructions(_Strict):
    version: str = Field(..., pattern=r"^[A-Za-z0-9._-]{1,40}$")
    persona: str = Field("", max_length=MAX_GUIDANCE)
    style: str = Field("", max_length=MAX_GUIDANCE)
    voice_style: str = Field("", max_length=MAX_GUIDANCE)
    phases: dict[Literal["anchor", "inventory", "invisible_work", "size_close"], PhaseGuidance] = Field(default_factory=dict)
    topics: dict[str, TopicGuidance] = Field(default_factory=dict)
    opening_questions: dict[str, dict[str, str]] = Field(default_factory=dict)
    closing: Closing = Field(default_factory=Closing)
    avatar: AvatarPhrases = Field(default_factory=AvatarPhrases)
    follow_ups: FollowUps = Field(default_factory=FollowUps)
    read_back: ReadBack = Field(default_factory=ReadBack)

    @field_validator("topics")
    @classmethod
    def _topics(cls, value: dict[str, TopicGuidance]):
        unknown = [key for key in value if key not in CHECK_KEYS]
        if unknown:
            raise ValueError(f"unknown topic '{unknown[0]}' (allowed: {', '.join(CHECK_KEYS)})")
        return value

    @field_validator("opening_questions")
    @classmethod
    def _questions(cls, value: dict[str, dict[str, str]]):
        for lang, questions in value.items():
            if not re.fullmatch(r"[a-z]{2}", lang):
                raise ValueError(f"language code '{lang}' must be two lowercase letters")
            for key, question in questions.items():
                if key not in CHECK_KEYS:
                    raise ValueError(f"unknown topic '{key}' (allowed: {', '.join(CHECK_KEYS)})")
                marks = question.count("?") + question.count("؟")
                if not question or len(question) > MAX_QUESTION or marks != 1 or "\n" in question:
                    raise ValueError(f"opening question {lang}.{key} must be one line, at most {MAX_QUESTION} characters, with exactly one question mark")
        return value

    @model_validator(mode="after")
    def _safe(self):
        texts = [("persona", self.persona), ("style", self.style), ("voice_style", self.voice_style)]
        texts += [(f"phases.{name}.{part}", getattr(guidance, part)) for name, guidance in self.phases.items()
                  for part in ("purpose", "follow_up")]
        texts += [(f"topics.{key}.{part}", getattr(topic, part)) for key, topic in self.topics.items()
                  for part in ("goal", "listen_for")]
        texts += [(f"opening_questions.{lang}.{key}", q) for lang, qs in self.opening_questions.items() for key, q in qs.items()]
        texts += [(f"closing.{kind}.{lang}", line) for kind in ("confirmed", "paused", "stopped")
                  for lang, line in getattr(self.closing, kind).items()]
        texts += [(f"avatar.{key}", getattr(self.avatar, key)) for key in ("greeting", "resumed", "rephrase", "still_working")]
        texts += [("avatar.acknowledgements", ack) for ack in self.avatar.acknowledgements]
        texts += [("avatar.consent", self.avatar.consent), ("follow_ups.guidance", self.follow_ups.guidance)]
        texts += [(f"read_back.{kind}.{lang}", line) for kind in ("intro", "closing", "confirm", "voice_confirm")
                  for lang, line in getattr(self.read_back, kind).items()]
        for where, text in texts:
            _check_safe(text, where)
        return self


class Loaded(BaseModel):
    instructions: Instructions | None
    version: str  # "<version>+<sha12>", or "builtin"
    path: str
    error: str | None = None


_cache: dict[str, tuple[float, Loaded]] = {}
_lock = threading.Lock()


def path() -> Path:
    return Path(os.environ.get("INTERVIEWER_INSTRUCTIONS_PATH") or DEFAULT_PATH)


def parse(raw: str, source: str = "<text>") -> Loaded:
    """Validates instruction text. Never raises: a rejected file yields built-ins."""
    try:
        data = yaml.safe_load(raw) or {}
        if not isinstance(data, dict):
            raise ValueError("the file must be a YAML mapping")
        parsed = Instructions.model_validate(data)
    except (yaml.YAMLError, ValidationError, ValueError) as exc:
        message = str(exc).splitlines()[0] if not isinstance(exc, ValidationError) else "; ".join(
            f"{'.'.join(str(p) for p in e['loc']) or 'file'}: {e['msg']}" for e in exc.errors())
        return Loaded(instructions=None, version="builtin", path=source, error=message[:500])
    digest = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:12]
    return Loaded(instructions=parsed, version=f"{parsed.version}+{digest}", path=source)


def load() -> Loaded:
    """Current instructions, re-read when the file changes (no restart needed)."""
    file = path()
    key = str(file)
    try:
        mtime = file.stat().st_mtime
    except OSError:
        return Loaded(instructions=None, version="builtin", path=key, error="file not found")
    with _lock:
        cached = _cache.get(key)
        if cached and cached[0] == mtime:
            return cached[1]
        loaded = parse(file.read_text(encoding="utf-8"), key)
        if loaded.error:
            log.error("interviewer_instructions rejected path=%s error=%s (using built-in wording)", key, loaded.error)
        else:
            log.info("interviewer_instructions loaded path=%s version=%s", key, loaded.version)
        _cache[key] = (mtime, loaded)
        return loaded


def follow_up_policy(loaded: Loaded) -> FollowUps:
    """Follow-ups are off unless a valid instructions file enables them."""
    return loaded.instructions.follow_ups if loaded.instructions else FollowUps()


def system_block(loaded: Loaded, phase: str | None, voice: bool, follow_up: str | None = None,
                 check: str | None = None) -> str:
    """The configurable section appended AFTER the core conduct rules."""
    ins = loaded.instructions
    if not ins:
        return ""
    parts = [f"ORGANISATION INTERVIEWER INSTRUCTIONS (version {loaded.version}).",
             "These shape tone and wording only. They never override the rules above, the deterministic",
             "next-topic plan, or the validation of your output; if they conflict, follow the rules above."]
    if ins.persona:
        parts.append(f"Persona: {ins.persona}")
    if ins.style:
        parts.append(f"Style: {ins.style}")
    if voice and ins.voice_style:
        parts.append(f"Spoken (avatar) delivery: {ins.voice_style}")
    guidance = ins.phases.get(phase) if phase else None
    if guidance and (guidance.purpose or guidance.follow_up):
        parts.append(f"Current phase ({phase}): {guidance.purpose}".rstrip())
        if guidance.follow_up:
            parts.append(f"Follow-up guidance for this phase: {guidance.follow_up}")
    topic = ins.topics.get(check) if check else None
    if topic and (topic.goal or topic.listen_for):
        parts.append(f"Current topic ({check}): {topic.goal}".rstrip())
        if topic.listen_for:
            parts.append(f"Listen for: {topic.listen_for}")
    if follow_up and ins.follow_ups.guidance:
        parts.append(f"Contextual follow-up guidance: {ins.follow_ups.guidance}")
    return "\n".join(parts)


def opening_question(loaded: Loaded, check: str | None, language: str) -> str | None:
    ins = loaded.instructions
    if not ins or not check:
        return None
    return (ins.opening_questions.get(language[:2]) or {}).get(check)


def read_back_line(loaded: Loaded, kind: Literal["intro", "closing", "confirm", "voice_confirm"], language: str) -> str | None:
    ins = loaded.instructions
    if not ins:
        return None
    return getattr(ins.read_back, kind).get(language[:2])


def closing_line(loaded: Loaded, kind: Literal["confirmed", "paused", "stopped"], language: str) -> str | None:
    ins = loaded.instructions
    if not ins:
        return None
    return getattr(ins.closing, kind).get(language[:2])
