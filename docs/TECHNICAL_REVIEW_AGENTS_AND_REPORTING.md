# Worktruth — Agents & Reporting: Technical Review Pack

*A complete walkthrough of the AI agents and the report pipeline: what each agent is,
when it is called, what it receives, what it returns, what happens when it fails, and
how a consultant's judgement gets into the client's hands.*

**Written for external technical review.** Verified against the code on branch
`report-redesign`, 10 September 2026. Every claim below points at a file so it can be
checked rather than taken on trust. The last two sections are deliberately the most
candid — the known gaps are where outside input is worth the most.

---

## Contents

- [0. Orientation](#0-orientation)
- [1. The agent service](#1-the-agent-service)
- [2. The discovery interview, in depth](#2-the-discovery-interview-in-depth)
- [3. Discovery end to end — the call sequence](#3-discovery-end-to-end--the-call-sequence)
- [4. The intelligence layer](#4-the-intelligence-layer)
- [5. The consultant](#5-the-consultant)
- [6. Report generation](#6-report-generation)
- [7. Data model reference](#7-data-model-reference)
- [8. Observed behaviour — a real end-to-end run](#8-observed-behaviour--a-real-end-to-end-run)
- [9. Known gaps and open questions](#9-known-gaps-and-open-questions)

---

## 0. Orientation

### What the product does

An SME's employees are interviewed one-to-one by an AI agent over WhatsApp or a web
chat. The agent learns how each person actually works and where their work snags.
Company documents (SOPs, policies, invoices) are ingested alongside. A deterministic
intelligence layer turns that evidence into signals, cross-team patterns and
recommendations. An independent expert consultant reviews, corrects and endorses the
analysis. Only then does a report ship to the client.

The product is the report. Everything else exists to make it defensible.

### Services

| Service | Stack | Responsibility |
|---|---|---|
| `rails` | Rails 7.1, Postgres + pgvector | All state, all business rules, all gates, orchestration |
| `langgraph` | Python 3.11, FastAPI, LangGraph, LangChain | **All model calls.** Stateless per request |
| `sidekiq` | Sidekiq + Redis | Async jobs (packages, aggregation, drafting, retries) |
| `frontend` | React + Vite + TypeScript | Four portals: company, consultant, platform, employee |
| `gotenberg` | Chromium | HTML → PDF |
| `minio` | S3-compatible | Report artifacts, document originals |
| `redis` | Redis | Sidekiq queues **and** the shared circuit breaker |

### The one architectural rule that explains most decisions

> **Rails owns state and context assembly. The agent owns model calls.**

The agent service holds no conversation state. `thread_id` is a handle, nothing more.
Every turn, Rails sends the entire conversation state ("the blackboard") in the request
body and persists whatever comes back into `conversations.state_snapshot`.

This has consequences worth understanding before reading further:

- The agent can be restarted, scaled or redeployed mid-interview with no loss.
- Anything the agent needs must be *assembled by Rails* and passed in. There is no
  "the agent will look it up".
- Conversely, control-flow decisions that do **not** need a model are made in Python
  but deterministically (see [§2](#2-the-discovery-interview-in-depth)) — the model
  writes prose, it does not decide when the interview ends.

One deliberate exception, for a reason worth flagging: `Companion::IntentClassifier`
and `Companion::PostDiscoveryRouter` stayed in Rails even though they involve a model
call, because they sit on the inbound hot path and moving them would add a network
hop to every single message an employee sends.

### Conversation lifecycle

```
onboarding  →  profiling  →  discovery  →  completed
                                       ↘  abandoned
```

- **onboarding** — consent (WhatsApp only; web arrives pre-verified via a magic link)
- **profiling** — up to 6 fixed questions, **no LLM**, deterministic script: role title,
  department, seniority, responsibilities, team size (managers only), primary tools
- **discovery** — the AI interview (LLM, one call per turn)
- **completed** — interview finished; further messages route to the companion

---

## 1. The agent service

`agent/app/main.py` — FastAPI, six endpoints, six distinct agents behind them.

### 1.1 Design principles

Four principles are applied consistently, and they are the reason the system degrades
rather than breaks:

**1. Deterministic control, generative content.** What to ask, when to stop, what
counts as learned — all decided in plain Python from state. The model writes the
question and reports what it heard. This is inverted from a typical "agentic" design
and it is the single most important choice in the interview engine.

**2. Every model path has an honest non-model fallback.** No key, no model, model down,
model returns garbage — every agent still returns something real, and says so. A
consultant opening an empty package cannot tell "nothing was found" from "generation
broke", so we never let that ambiguity exist.

**3. Numbers are grounded or dropped.** A model may not introduce a figure that is not
traceable to captured evidence. Enforced by regex, not by asking politely — and the
whole *claim* is dropped, not just the figure, because a sentence built around an
invented number is not salvageable by deleting the number.

**4. Failures are distinguishable.** Every fallback carries a `fallback_reason`. A bare
string reply gave Rails no way to tell a real answer from a canned one, which is
precisely how a broken call once stayed hidden for an entire test run.

### 1.2 Shared infrastructure

These four modules are small and are worth reading first, because every agent depends
on them.

#### `openai_factory.py` — one switch for local and cloud

```python
build_chat_openai(model=, temperature=, json_mode=, max_tokens=)
```

- `OPENAI_BASE_URL` empty → OpenAI. Set → any OpenAI-compatible server (we develop
  against LM Studio running Gemma locally).
- **JSON mode is host-gated.** `response_format: json_object` is only sent to
  `*.openai.com`, because local servers reject it outright. Everywhere else we rely on
  tolerant parsing instead.
- **`reasoning_effort` is only sent when configured**, because a non-reasoning model
  rejects the parameter.

#### Truncation detection — subtler than it looks

```python
def truncated(response) -> bool:
    return (response.response_metadata or {}).get("finish_reason") == "length"
```

Reasoning models spend their token budget *thinking before emitting anything*. A cap
that looks generous can be entirely consumed with nothing written. The reply then
cannot be parsed — and **re-asking at the same cap truncates identically**.

So every call site detects this explicitly and **escalates the cap** rather than
retrying. This is not a micro-optimisation; without it a verbose turn fails the whole
interview. Measured on Gemma 12B: `reasoning_effort: "low"` consumed 5,997 of 6,000
tokens and returned empty content; `"minimal"` on the identical turn completed cleanly
at 2,796 tokens. Those measurements are recorded in the config comments so nobody
re-derives them.

#### `circuit_breaker.py` — shared with Rails via Redis

Both `OpenaiCircuitBreaker` (Rails) and this module read/write the same Redis keys:
`openai:circuit_open` (a `SETEX`, 300s) and `openai:error_window` (a sorted set).

- The **agent** owns windowed failure counting: ≥4 failures in 300s *and* ≥50% failure
  rate trips it.
- **Rails** reads the flag and may trip it on a retryable outage.
- **Fails open** on any Redis error — a monitoring dependency must never take down the
  thing it monitors.

One subtlety with real operational consequences: `trip!` is a `SETEX`, so tripping an
already-open breaker *refreshes its TTL*. Under continuous traffic that turns a 300s
cool-off into a permanent block. Rails therefore only ever trips a **closed** breaker.

#### `json_parse.py` — tolerant extraction

Strips ``` fences (including partial ones), falls back to first-`{`-to-last-`}`
extraction, and raises a distinct `LlmJsonParseError`. That distinctness matters: a
parse failure gets **one reformat retry** before it is treated like a transport
outage, so bad JSON does not trip the breaker on first offence.

### 1.3 The six agents

| # | Agent | Endpoint | Called from | Timeout | Raises on failure? |
|---|---|---|---|---|---|
| 1 | Discovery interviewer | `POST /v1/threads/{id}/turn` | `Discovery::ProcessTurnService` | `LANGGRAPH_READ_TIMEOUT` (45s default) | Yes — 503, Rails degrades |
| 2 | Discovery package builder | `POST /v1/discovery/package` | `Discovery::BuildPackageService` (job) | default | **No** — deterministic fallback |
| 3 | Requirement drafter | `POST /v1/consultant/requirements/draft` | `ConsultantRequirements::DraftQuestionsService` (job) | `LANGGRAPH_DRAFT_READ_TIMEOUT` (180s) | **No** — templated fallback |
| 4 | Requirement evaluator | `POST /v1/consultant/requirements/evaluate` | `ConsultantRequirements::RecordAnswerService` | 180s | **No** — fails to *not satisfied* |
| 5 | Companion | `POST /v1/companion/turn` | `Companion::ProcessTurnService` | `LANGGRAPH_COMPANION_READ_TIMEOUT` (120s) | **No** — canned fallback |
| 6 | Document analysis | `POST /v1/docs_analysis/runs` | `Documents::AnalysisRunService` (job) | `LANGGRAPH_DOCS_READ_TIMEOUT` (180s) | Yes — 500 |

Note the pattern in the "raises" column. **Only the interview and document analysis
raise.** Everything downstream of a completed interview is deliberately un-raisable,
because by then the employee has already done their part and there is nothing to gain
by failing loudly at them.

The two fallback *directions* in agents 3 and 4 are opposite, on purpose:

- **Drafting** falls back to a real question. A consultant who stated a need and got
  nothing would have to state it again.
- **Judging** falls back to **not satisfied**. Wrongly closing a requirement loses the
  consultant's question silently; wrongly leaving it open costs at most one more
  question, and the caps bound that.

---

### Agent 1 — Discovery interviewer

The core of the product. Covered in full in [§2](#2-the-discovery-interview-in-depth).

`agent/app/multi_agent_graph.py` compiles a three-node LangGraph:

```
        ┌──────────────────────────────────────────┐
        │  prepare   (deterministic — no LLM)      │
        │  what to ask next, or whether to stop    │
        └──────────────┬───────────────────────────┘
                       │  should_close?
              ┌────────┴────────┐
              ▼ no              ▼ yes
   ┌──────────────────┐   ┌──────────────┐
   │  interview       │   │  close       │
   │  ONE LLM call    │   │  fixed       │
   │  + finalize      │   │  farewell    │
   │  (deterministic) │   │  no LLM      │
   └────────┬─────────┘   └──────┬───────┘
            ▼                    ▼
                     END
```

**One LLM call does the whole turn.** In a single response the model must: react to the
reply, ask the next question, extract an insight, extract a reusable finding, report
which dossier slots the answer supplied, park anything interesting it isn't asking
about, name role areas, and optionally refresh the rolling summary. That is a lot to
ask of one call — see [§9](#9-known-gaps-and-open-questions), where it is the source of
the most significant open issue.

---

### Agent 2 — Discovery package builder

`agent/app/package.py` · run from a job, never inline (it makes a model call, and the
employee's closing message must not wait on it).

**Input** — only what the interview captured. The model gets nothing else, so it has
nothing else to draw on: role areas, filled dossier slots, parked asides, shared
findings, the rolling summary, and up to 20 per-turn insight summaries. **It never
reads the raw transcript.** This is a synthesis step, not a second analysis.

**Output**

```json
{
  "recommendation": "the one thing you'd tell the consultant",
  "recommendation_rationale": "why, from the evidence",
  "confidence": 0.0,
  "issues":    [{ "title", "body", "impact": "low|medium|high" }],
  "solutions": [{ "title", "body", "impact", "addresses": "issue title" }],
  "followup_questions": [{ "body", "rationale", "from_parked" }]
}
```

**Grounding.** `_normalize()` runs every string through `_grounded()`. The allowed-number
set is built from the *content* the interview captured — deliberately **not** the
metadata around it, because dumping the whole evidence object made the dossier's own
confidence scores (0.7, 0.8, 0.9) count as grounded figures, which would have licensed
a model to emit "saves 0.9 days" and pass the guard.

The number regexes are kept in step with `Llm::GroundedNumbers` on the Rails side, and
both have tests locking the behaviour. They recognise currency, thousands, decimals,
percentages, ranges, and — importantly — **bare integers with a unit** ("14 hours a
week", "200 invoices"), which is exactly the shape a model invents in this domain.

**Fallback** builds a genuine package from the same evidence with no model: issues come
from recorded friction, the recommendation names the area with the most friction, and
`solutions` is left **empty** — inventing a remedy without a model would be guessing,
and an empty list is honest.

---

### Agent 3 — Requirement drafter

`agent/app/requirements.py::draft_questions`

A consultant states a need **in their own words**; this turns it into questions an
employee can answer. The consultant never writes question text — that separation is the
entire reason `ConsultantRequirement` exists as its own object (one need can take
several questions, and something has to hold "is this settled yet?" across them).

Prompt rules worth noting: the employee is not the consultant, so the agent must never
mention consultants, reviews, reports or requirements — it asks as the assistant they
have been chatting with. One clause per question. Fewer is better.

**Fallback** is careful about grammar in a way that sounds trivial and isn't. A
consultant writes in the first person: *"I need to know who signs off on a PI."*
Splicing that verbatim produced *"Could you tell me a bit more about i need to know who
signs off…?"* — broken and nonsensical to the recipient. `_NEED_PREFIXES` strips the
first-person framing so what remains is the *subject* of the need.

---

### Agent 4 — Requirement evaluator

`agent/app/requirements.py::evaluate_requirement`

Given the stated need and the Q/A transcript so far, decides `{satisfied, missing_aspects}`.
"Be strict but not pedantic. Satisfied means someone reading these answers would have
what the consultant asked for — not that every detail is perfect."

Note `satisfied` is `bool(parsed["satisfied"]) and not missing` — a model that says
"satisfied, but X is missing" is treated as **not** satisfied. Fails to not-satisfied.

---

### Agent 5 — Companion

`agent/app/companion.py`

After the interview completes, ordinary chat: tips, tool questions, things the employee
wants to mention. **It must never re-interview them** — whether to reopen discovery at
all is decided in Rails.

The prompt branches on intent, for a reason found by evaluation: the promote nudge
("say *add this to my interview*") earns its place when someone volunteers something,
but on a **direct question** it crowds out the answer. An observed reply to *"how do I
chase overdue approvals faster?"* spent itself entirely on the nudge and never
answered. So on `intent == "ask"` the instruction is *answer first*, nudge second.

One failure-handling detail worth copying elsewhere: a generic `Exception` here is
logged but **not** counted as a model failure, because a `TypeError` in our own code is
our bug, not an outage — and feeding it to the shared circuit breaker took the whole
discovery path down with it. That is exactly how a missing `max_tokens` parameter once
stayed hidden while the companion silently never used the model at all.

---

### Agent 6 — Document analysis

`agent/app/docs_analysis_graph.py` — the only multi-node LangGraph pipeline:

```
coordinator → specialist → synthesizer → profile_grounder
            → question_generator → critic → reporter → END
```

Extracts structured knowledge entries per document (`process | policy | system | org |
metric | risk | other`), grounds the company profile against them, generates
clarification questions for the company admin, self-critiques, and reports.

**Note for reviewers:** in the current end-to-end scenario this pipeline is *not*
exercised — the scenario runner creates documents directly (upload, chunk, mark ready)
rather than going through `Multimodal::ParseDocumentService`. So documents contribute to
reports via chunk-level keyword matching and metric extraction, not via this richer
analysis. See [§9](#9-known-gaps-and-open-questions).

---

## 2. The discovery interview, in depth

### 2.1 The dossier — what the interview is trying to learn

`agent/app/dossier.py`

The interview used to end on arithmetic (`question_count >= target`). Coverage was
tracked but nothing read it, so every interview ran to the counter regardless of how
much had been learned. It now ends on a **filled dossier** — a set of named slots.

| Slot | Scope | Required? | What the interviewer is curious about |
|---|---|---|---|
| `how_it_works` | per role area | **required** | how this part of their work actually gets done day to day, and which tools they use |
| `friction` | per role area | **required** | what's slow, manual, annoying or error-prone — where it snags |
| `ai_current_usage` | global | **required** | whether they already use AI tools, and for what |
| `ai_openness` | per role area | opportunistic | whether they'd hand a boring slice to software — asked lightly, never as a pitch |
| `volume_or_frequency` | global | opportunistic | roughly how often or how much — *"take it if they offer it, never chase it"* |

Intents are phrased **as intent, not as a script** — the model writes the question.

Required keys therefore *grow during the interview*: `required_keys()` is
`["ai_current_usage"] + ["how_it_works::{area}", "friction::{area}"]` for each area
discovered. With 2 areas that is 5 required slots.

A slot is **filled** when the model reported it with `confidence >= slot_confidence`
(default 0.6). Higher-confidence answers overwrite lower ones; lower never overwrite
higher.

`parked` holds interesting asides the interview deliberately did **not** chase — capped
at 12. This is what makes "breadth before depth" real rather than aspirational, and the
parked items become the raw material for the package's follow-up questions.

### 2.2 Two phases

`agent/app/area_flow.py`

**Phase A — orient.** A warm colleague spends up to `orient_questions` (default 3) turns
surfacing the person's 2–3 main role areas and writes them to the blackboard. Orientation
ends early if areas are named by turn 2. If orientation names nothing, areas are seeded
by splitting the `responsibilities` string the profiling step already captured — so
branching always has something to branch on.

**Phase B — branch.** Rotate short threads across those areas, asking for whichever
slot is still missing, force-switching so no single area dominates.

`next_beat()` priority:

1. Required slots for the **current** area
2. `ai_current_usage`, once one area is fully understood
3. Opportunistic slots

The force-switch is worth reading closely. When `area_streak >= switch_after` (default
3) **or** the current area is done, candidates are the *other* areas, sorted
least-covered first. The current area is **excluded from the candidates** — otherwise it
sorts first again and the switch never happens, which is how a single lens came to
dominate an earlier version.

### 2.3 The four exits, in precedence order

`area_flow.prepare()`:

| # | `close_reason` | Condition | Interpretation |
|---|---|---|---|
| 1 | `ceiling` | `question_count >= max_questions` | **A backstop, not a target.** Firing often means the dossier asks for more than an interview can get |
| 2 | `dossier_complete` | past floor **and** every required slot filled | The intended exit |
| 3 | `stalled` | past floor **and** `stall_turns >= 2` | What stops an uncapped interview circling |
| 4 | `employee_ended` | model set `completed=true` | They asked to stop |

Exits 2 and 3 are both gated on `min_questions` (default 4), because without a floor a
terse employee trips the stall detector at turn 3 and the package gets built on almost
nothing.

`close_reason` is persisted. **It is the single best health metric for the interview
engine** — a high rate of `ceiling` means the dossier is mis-specified; a high rate of
`stalled` means slots aren't being filled (which is exactly what we observed and
root-caused in [§8](#8-observed-behaviour--a-real-end-to-end-run)).

Exits 2 and 3 fire in `prepare` on the **next** turn, not in `finalize` — completing in
finalize would orphan the question just asked. Only `employee_ended` ends mid-turn,
because the model's message doubles as the farewell.

### 2.4 prepare / finalize

`agent/app/orchestrator.py`

**`prepare_turn`** — resolve limits, ensure the blackboard is in shape, ask `area_flow`
for a decision, build the `routing_decision` (the human-readable "why this question"),
and stamp `active_agent_id` for provenance.

**`finalize_turn`** — fold the model's structured output back in:

- `area_flow.finalize()` — increment counters, merge role areas, **stash `last_beat`**
- `dossier.merge_slots()` — returns how many *required* slots this turn newly filled
- `dossier.park()` — capture the aside
- `stall_turns = 0 if progress else stall_turns + 1`
- append `finding`, refresh `conversation_summary` every 3 turns

### 2.5 `last_beat` — a subtle bug worth understanding

This one is worth a reviewer's attention because it was invisible and it broke the
central mechanism of the redesign.

`beat` is the topic of the question being asked **this** turn. But the employee message
the model is looking at *right now* was answering whatever was asked **last** turn.
Grading the incoming reply against the *upcoming* topic meant `slots_filled` almost
never matched anything real — so `dossier_complete` could never fire, and every
interview ended on `stalled` or `ceiling`.

The fix is one line in `finalize` (`bb["last_beat"] = beat`) plus using it in the
prompt:

```python
prev_beat = bb.get("last_beat")
if prev_beat and prev_beat.get("slot"):
    slot_hint = (
        f"Their answer you're looking at now was replying to the "
        f"'{prev_beat['slot']}' slot on area '{prev_beat.get('area')}'. "
        "Report it in slots_filled if their answer actually supplied it — "
        "omit it if they didn't really address it."
    )
```

### 2.6 The per-turn prompt

`agent/app/multi_agent_llm.py::_build_system_prompt` assembles:

persona (phase-specific) · company profile blurb · employee profile · rolling summary ·
findings so far · **retrieval context** · **anti-repeat guard** · what's still wanted ·
the turn's task · question-shape rules · the slot hint · valid slot names · the JSON
schema.

Two blocks earn their place:

**The anti-repeat guard** (`_asked_block`) lists the last 8 questions verbatim with
*"do NOT ask any of these again, even reworded or from a slightly different angle"*.
Without a plain list, the model re-asks earlier questions by mid-interview. The raw
history window is also 14 messages (not 6) so the model can still see the opening
questions by Q7–8.

**Question shape** is a hard constraint, not a tone note:

```
- ONE question, one clause. Answerable in a sentence.
- No compound questions — nothing with "and" joining two asks.
- Plain words. No jargon, nothing they'd have to decode.
- React to what they just said first, THEN ask.
- Warm through your WORDS, not symbols — do NOT use emoji.
```

The reason is mechanical: **a compound question gets a partial answer, which fills no
slot and pushes the interview toward the stall exit.**

Media context is fenced as `--- UNTRUSTED MEDIA CONTEXT ---` (it is employee-supplied),
and when confidence < 0.6 the model is told to ask one clarifying question rather than
assume.

### 2.7 Limits resolution

`Discovery::ContextBuilder::LIMIT_DEFAULTS` — **company setting → ENV → code default**:

| Agent key | Default | Purpose |
|---|---|---|
| `max_questions` | 8 | Ceiling (backstop) |
| `min_questions` | 4 | Floor before dossier/stall exits can fire |
| `stall_turns` | 2 | Consecutive no-progress turns before closing |
| `slot_confidence` | 0.6 | Threshold for "filled" |
| `orient_questions` | 3 | Orientation budget |
| `switch_after` | 3 | Force-switch off an area |

A detail that reads like an accident but is load-bearing: these keys are **deliberately
absent** from `Company::DEFAULT_SETTINGS`. `merged_settings` folds the defaults in, so a
key listed there would always look operator-set and ENV could never win. Their absence
is what makes the precedence work.

### 2.8 A LangGraph gotcha, documented in the code

`agent/app/state.py`:

> LangGraph only propagates keys declared in the state TypedDict between nodes. A
> decision left off this list is **silently dropped**, which is subtle and expensive to
> debug — `phase` missing made the interview never merge role areas.

---

## 3. Discovery end to end — the call sequence

### 3.1 The inbound ladder

`Inbound::TrackRouter` — one shared precedence for **both** channels. This used to live
only in the WhatsApp processor, which meant a consultant's question answered on the web
thread was swallowed by the discovery handler.

```
1. an open consultant question is awaiting an answer  → consultant_followup
2. ...unless the message is plainly about something else → companion
3. conversation not yet completed                     → discovery / profiling / onboarding
4. completed                                          → companion
```

Rung 2 matters more than it looks: without it an unanswered consultant question blocks
the companion indefinitely, so an employee asking *"any tools for this?"* gets recorded
as answering the consultant and pollutes the reply thread.

**Rung 1's fail-safe is worth studying**, because the naïve version had a silent data-loss
bug. `Companion::IntentClassifier` **never raises** — it swallows model failures and
returns `{intent: "casual", confidence: 0.5, source: "default"}`. Since `casual` is a
non-answer intent, a *failed* classification was indistinguishable from real chit-chat,
and silently diverted a genuine reply into the companion: the request stayed
`awaiting_reply` forever, the requirement stayed open, the consultant was never
notified, the employee believed they had answered, and a follow-up budget slot was burnt
for nothing. Observed intermittently (2 of 3 runs) against a local model.

The fix requires a **confident source**, not merely a non-answer intent:

```ruby
CONFIDENT_SOURCES = %w[phrase llm awaiting_affirm].freeze
# a defaulted or fail-safe "casual" means the classifier didn't know,
# not that this isn't the answer
```

Fail-safe in **both** directions — a raised error and an unconfident verdict alike treat
the message as the answer, *because losing a consultant's reply is worse than mis-filing
a companion aside.*

### 3.2 One discovery turn, end to end

```
WhatsApp webhook                          Web chat
Whatsapp::InboundProcessor                Web::TurnRouter
        └──────────────┬───────────────────────┘
                       ▼
              Inbound::TrackRouter          ← the ladder above
                       ▼
              Whatsapp::DiscoveryHandler
                       ▼
        Discovery::ProcessTurnService       ← the orchestrator
          1. ensure_thread!                 POST /v1/threads
          2. load active playbook (per department)
          3. OpenaiCircuitBreaker.open? → degrade, do NOT call
          4. Discovery::ContextBuilder      ← assembles everything
          5. Langgraph::Client#run_turn!    POST /v1/threads/{id}/turn
          6. persist_turn!
          7. breaker reset
                       ▼
              Discovery::DeliverReply
              persists outbound message with
              agent_id + routing_decision (provenance)
                       ▼
        if completed → Discovery::FinalizeConversationService
```

**What `persist_turn!` writes** — this is the audit trail a reviewer can inspect:

| Where | What |
|---|---|
| `conversation_insights` row | per-turn `summary` + `topics` |
| `state_snapshot["blackboard"]` | the whole dossier, areas, parked, findings, summary |
| `state_snapshot["last_insight"]` | the turn's insight |
| `state_snapshot["last_routing_decision"]` | why this question |
| `messages.agent_id` | which phase produced the message (`orient`/`branch`/`close`) |
| `messages.routing_decision` | the full decision object, per message |

### 3.3 What ContextBuilder assembles

`Discovery::ContextBuilder` — profile, blackboard, limits, memory facts, document
snippets, knowledge snippets, media context, media snippets, company profile.

**Memory retrieval is flag-gated and off by default**, for a measured reason: pgvector
nearest-neighbour retrieval (cross-employee facts + document chunks, cosine distance
≤ 0.35) adds a lot of prompt. Measured on Gemma 12B: **~145s per turn without it, ~570s
with it.** Twelve turns at 570s is a two-hour run. On a cloud model the trade-off is
different and it is worth turning on.

Cross-employee facts are injected with an explicit instruction: *"NEVER name anyone,
paraphrase as 'some of your colleagues mentioned…'"*.

### 3.4 On completion

`Discovery::FinalizeConversationService` fires **three** jobs:

```ruby
AggregateIntelligenceJob.perform_later(@company.id)      # re-derive company intelligence
MemoryPromotionJob.perform_later(@conversation.id)       # promote durable facts
BuildDiscoveryPackageJob.perform_later(@conversation.id) # the consultant handover
```

All async. The package makes a model call and the employee's final message must not wait
on it.

### 3.5 The failure path

When the agent is unavailable, `handle_unavailable!`:

1. Trips the breaker (only if **closed** — see [§1.2](#12-shared-infrastructure))
2. Sends a localised *"we're experiencing a brief delay"* notice
3. Enqueues `RetryDiscoveryTurnJob` at +30s

Those delay notices are tagged `raw_payload["kind"] == "delay_notice"` and **excluded
from history** on subsequent turns. Without that exclusion the anti-repeat guard told the
model not to repeat a non-question, and each further failure added another one —
compounding into a spiral a single transient hiccup could never recover from.

---

## 4. The intelligence layer

`Intelligence::AggregateCompanyIntelligence` — the **only** thing that writes findings.

```
SignalExtractor           → SignalUpsertService         → company_signals
PatternDetector           → PatternUpsertService        → patterns
RecommendationSynthesizer → RecommendationUpsertService → recommendations
CompanyStackInferrer                                    → company_systems
Catalog::CompanyFitService                              → company_catalog_matches
AgenticIdeaWriter (LLM) ‖ AgenticIdeaSynthesizer        → agentic_ideas
```

Then it refreshes `intelligence_snapshot`, `intelligence_updated_at` and readiness.
`intelligence_updated_at > report.generated_at` is what makes the portal show **"report
stale"**.

**Triggered from five places:** interview completion, document parse, media index,
document purge, analysis runs.

**Almost entirely deterministic.** Only `AgenticIdeaWriter` uses a model, and it falls
back to a rule-based synthesizer.

### 4.1 Signals

Six keyword rules (`manual_process`, `approval_bottleneck`, `tool_dependency`,
`data_silo`, `time_sink`, `communication`) matched against document chunks, completed
interview messages, and media insights.

**Evidence counting is deliberately conservative.** `evidence_count = distinct documents
+ distinct interview messages + media attachments`. Derived text (memory facts,
knowledge entries, insight summaries) only *corroborates* at 0.3 weight — counting it as
primary evidence produced an inflated "163 evidence items".

```
strength = 1 - exp(-weighted / 6)      # saturating, floor 0.2
```

A saturating absolute-evidence curve, because the earlier hits/corpus **ratio** jammed
every signal to ~0.35–0.45 regardless of how strong it was.

Message evidence is ranked by how well the *matched sentence* speaks to the signal, with
negation detection (a negation token within 40 characters *before* the match) and
self-intro filtering — so a pull quote supports the finding rather than refuting it.
*"There are no manual steps"* must not become evidence of manual process.

**Department attribution** is derived per signal from the evidence that produced it:
`document.department` for matched documents, the interviewee's department for each kept
excerpt, the exhibit owner's for matched media. Corroborating derived text and
topic-only inference attribute **nothing**, because neither is traceable to one team.

### 4.2 Patterns

Three ways a pattern can form:

1. Combo `approval_bottleneck + manual_process` (fixed confidence 0.82)
2. Combo `data_silo + time_sink` (fixed confidence 0.78)
3. **Any single signal spanning ≥ 2 departments** (confidence = the signal's own strength)

Thresholds are a **company setting** (`merged_settings["pattern_thresholds"]`), not a
constant, because how readily a pattern should form is a product-judgement call about
false positives on small samples:

| Key | Default | Applies to |
|---|---|---|
| `min_strength` | 0.35 | combo participation |
| `anchor_strength` | 0.65 | at least one strong signal in a combo |
| `cross_department_min_strength` | **0.2** | rule 3 only |
| `max_cross_department` | 3 | cap on rule-3 patterns |

The asymmetry in rule 3's floor is deliberate: a combo asserts a *fixed high* confidence,
which is unearned on thin evidence, whereas a cross-department pattern reports its own
signal's strength — so a thin one surfaces as *low confidence* and the report states the
uncertainty rather than hiding it. And two teams independently describing the same
friction is itself corroboration.

The cap exists because once attribution works properly, *most* signals in a
multi-department company span two teams — an uncapped rule emitted seven near-identical
"⟨signal⟩ across departments" patterns on one company, saying less than the signal list
already did.

**Reconciliation.** Both signals and patterns support `reconcile_stale`. A full-company
run has seen all the evidence, so it prunes what is no longer detected and **replaces**
the derived department set; a department-scoped run sees only a slice and merges.
Pattern confidence takes the **fresh** value (not a historical maximum) with material
moves recorded in `patterns.confidence_history`, so a pattern that has weakened can
still be seen to have been stronger.

---

## 5. The consultant

The consultant is not a reviewer bolted on at the end. They are a first-class actor with
four distinct intervention points, and the report's credibility rests on them.

```
interview completes
      ▼
┌─────────────────────────────┐
│ 1. DISCOVERY PACKAGE        │  per employee, before any report exists
│    amend · reject · add     │
│    state a need → agent     │
│    drafts → employee        │
│    answers → agent judges   │
└─────────────┬───────────────┘
              ▼
      report generated (gated, internal_only)
              ▼
┌─────────────────────────────┐
│ 2. REPORT REVIEW            │  hide / rewrite / add sections
│    comments · findings      │  section-by-section dispositions
│    opportunity sizing       │  ← the number the owner most wants
└─────────────┬───────────────┘
              ▼
      3. SUBMIT (4 completeness rules enforced)
              ▼
      platform approval → shipped to client
              ▼
┌─────────────────────────────┐
│ 4. REFRESH                  │  new evidence → mint next version
└─────────────────────────────┘
```

### 5.1 Discovery package review

The consultant sees, per interviewed employee: the agent's recommendation and rationale,
issues, solutions, and the follow-up questions the agent *intends* to ask next.

They can:

- **Amend the substance.** Rewriting `recommendation` is allowed; the agent's original
  survives in `agent_payload`, so the two remain separable.
- **Reject an agent issue.** A rejection is **kept, not deleted** — it is a signal about
  agent quality.
- **Add their own** issues and solutions, tracked with `origin: "consultant"` vs
  `origin: "agent"`.

Both survive regeneration. If an employee adds an addendum, `BuildPackageService` mints
v+1 and `carry_forward_consultant_edits!` copies consultant-authored items forward and
re-applies rejections by matching body text — otherwise a consultant's amendments would
vanish the moment an employee added one more thought.

### 5.2 The requirement loop

The mechanism the product is really built around:

```
consultant STATES a need, in their own words
        "I need to know who signs off on a PI once a price
         mismatch is found, and whether they can hold payment."
                    ▼
        ConsultantRequirements::CreateService
        → DraftRequirementQuestionsJob (async — LLM)
                    ▼
        agent DRAFTS the actual question text
        (consultant never writes it)
                    ▼
        SendQuestionService → employee's real channel
        (WhatsApp template if outside the 24h window)
                    ▼
        employee answers through the normal inbound path
        → Inbound::TrackRouter rung 1 attributes it
                    ▼
        RecordAnswerService → agent EVALUATES
                    ▼
        satisfied?  ── yes → requirement satisfied
              │
              no → partially_satisfied + missing_aspects
                   → draft again, IF budget remains
                    ▼
        employee gets an acknowledgement either way
```

**Status machine:** `open → questions_drafted → partially_satisfied → satisfied`
(or `withdrawn`).

**Two budgets, protecting different things:**

| Cap | Default | Protects |
|---|---|---|
| `max_per_requirement` | 3 | stops one unsatisfiable need generating questions forever |
| `max_per_package` | 6 | protects the **employee** — three requirements at three each is nine questions to one person, more than the entire interview is allowed |

**The employee always gets acknowledged**, worded by outcome — because an employee who
answered a consultant's question used to get *nothing* back, while a casual "thanks!"
got a warm companion reply. The one message that took real effort was the one that
looked ignored.

| Outcome | Acknowledgement |
|---|---|
| satisfied | "Thanks — that answers it. Nothing further needed for now." |
| more coming | "Thanks — that helps. There may be one more quick question on this." |
| no requirement behind it | "Thanks — I've passed that on." |

### 5.3 Report review — four override mechanisms

All of it is an **overlay**. The stored `report_snapshot` is never mutated, so the
machine analysis and the expert's edits stay separable and auditable.

| Mechanism | Table | Effect in the PDF |
|---|---|---|
| Override `hide` | `report_section_overrides` | section disappears |
| Override `edit` | `report_section_overrides` | **replaces** the AI section body |
| Override `add` | `report_section_overrides` | new section after `anchor_section` |
| Section state | `report_review_section_states` | approved → appendix disposition |
| Comment | `report_review_comments` | unresolved → appendix note |
| Overall note | `report_reviews.overall_note` | appendix |
| Structured finding | `report_review_findings` | appendix, when `publishable` |
| Catalog endorsement | `catalog_endorsements` | tools catalog section |
| Opportunity sizing | `report_reviews.opportunity_*` | **page 1 of the brief** |

14 sections are overridable (`ReportSectionOverride::BUILT_IN_SECTIONS`); 7 are formally
reviewable (`ReportSections::KEYS`). *(That asymmetry is listed in
[§9](#9-known-gaps-and-open-questions).)*

An `edit` on `executive_summary` is special-cased: it propagates into the base snapshot
field too, because that also feeds the cover subtitle and contents teaser. Without it
the cover would quote the AI while page three quoted the expert.

Nine finding types: `executive_conclusion`, `evidence_sufficiency`, `correction`,
`risk`, `recommendation_disposition`, `catalog_assessment`, `unresolved_followup`,
`addendum`, `endorsement` — each with a severity (`info|material|critical`) and a
disposition.

### 5.4 The section template library

"Add a section" always worked — what it lacked was **structure**. A consultant got an
empty textarea and no indication that a real deliverable wants Assumptions, Risks, Quick
Wins. `ReportSectionTemplates` holds nine sections that a strategy deliverable carries
and that an evidence-driven generator **structurally cannot produce**, because they need
judgement rather than data:

| Key | Title | Why a generator can't write it |
|---|---|---|
| `expert_conclusion` | The expert view | Their own answer, in their words |
| `assumptions_limitations` | Assumptions and limitations | What we could not see. Only a human knows |
| `risks` | Risks and mitigations | What could go wrong doing this. Requires having done it |
| `quick_wins` | First 90 days | What builds momentum and buy-in |
| `benchmarks` | How this compares | Requires outside knowledge |
| `options_considered` | Options considered | The roads not taken, and why |
| `implementation` | Implementation plan | Owners, sequencing, resourcing |
| `governance` | Governance | Who decides what, at what cadence |
| `next_steps` | Next steps | The explicit ask |

Each carries a `purpose` (rendered on the page, so the section explains itself) and a
`scaffold` — a skeleton posing the questions the section must answer, so the consultant
fills in judgement rather than staring at a cursor. Served at
`GET /api/v1/consultant/section_templates`.

Consultant sections render with an accent rail, a credentialed byline, a signature
block, and light-markup typography (`##` headings, `-` bullets, `**bold**`) — escaped
first, so consultant input can never inject HTML. They previously rendered as
`white-space: pre-wrap` plain text on a blank page, which meant the part of the
deliverable we sell looked *worse* than the machine's pages.

### 5.5 Submit — four enforced completeness rules

`ReportReviews::SubmitService` refuses to submit unless:

1. All 7 reviewable sections are `approved` or `needs_info`
2. `overall_note` is present
3. Every `needs_info` section has an explanatory comment
4. A publishable `executive_conclusion` finding exists

Status becomes `needs_info` if any section is, else `approved`. When every active
consultant has submitted, the report moves to `reviews_complete` and the platform is
notified.

### 5.6 Refresh and reshare

Evidence does not stop arriving when a report is reviewed.
`Reports::ConsultantRefreshService` lets the consultant mint the next version
themselves, rather than waiting on the company to click Generate.

Deliberately a **new version**, not a re-render: the delta section then states what
changed since the version the client already has, the approved version stays on the
record, and `carry_forward_overrides!` copies their published edits onto the new one so
re-review starts from their work. It refuses when nothing has changed, rather than
burning a version number.

---

## 6. Report generation

### 6.1 Two different artifacts, both called "report"

| | **Discovery Package** | **Company Report** |
|---|---|---|
| Model | `DiscoveryPackage` | `Report` |
| Scope | **one employee, one interview** | **the whole company** |
| Audience | the consultant, internally | the client |
| Format | database rows, in the consultant portal | **PDF** via Gotenberg |
| Trigger | interview finishes (automatic) | company user clicks Generate (gated) |
| Approval gate | none — internal | consultant review **and** platform approval |

**The package never feeds the PDF directly.** There is no
`discovery_packages → report_snapshot` code path. What flows through is the *evidence* —
interview messages, plus answers the consultant's follow-ups produced — which the
intelligence layer re-mines into signals and patterns, which the snapshot builder reads.

### 6.2 The pipeline

```
POST /api/v1/company/reports
  ├─ READINESS GATE: report_readiness_score < 100 → 422
  │  (unless allow_early_report)
  └─ Report row: version = max+1, status queued, visibility internal_only
        ▼
GenerateReportJob → Reports::GenerateReportService
  ①  DeltaCalculator      diff vs the PREVIOUS report's snapshot
  ②  SnapshotBuilder      ~25 deterministic keys  ← the bulk of the logic
        └─ NarrativeWriter    the ONE LLM call, grounded, fails safe to nil
        └─ roadmap ||= deterministic_roadmap (Now/Next/Later from priority)
  ③  for each variant (full, exec_brief):
        HtmlBuilder → ERB → PdfGenerator (Gotenberg) → MinIO
        + the reader HTML stored beside the PDF
  ④  persist snapshot, status ready
  ⑤  carry_forward_overrides!(previous)   deduped
  ⑥  THE GATE, three ways:
        skip_platform_review? → shared_with_company + notify client
        active consultants?   → ReportReviews::BootstrapService
        neither               → internal_only, notify platform
```

Any exception → `status: "failed"`, `error_message` recorded, re-raised.

> **A ready report is never automatically shipped to the client.** That is the
> load-bearing line in the whole service.

### 6.3 The snapshot contract

`report_snapshot` (jsonb) is the persisted contract. Everything downstream — PDF, API,
next version's delta — reads from it.

| Key | Source | LLM? |
|---|---|---|
| `company`, `readiness`, `participation` | company + profile + computed | no |
| `situation` | leads with a real metric when one exists | no |
| `signals` | `company_signals` — label, strength, departments, evidence_count | no |
| `patterns`, `implications` | `patterns` + template sentence | no |
| `key_metrics` | `Reports::MetricExtractor` — regex over evidence | **no, deliberately** |
| `recommendations` | published + computed `impact_score` / `feasibility_score` | no |
| `evidence_base` | four counts: interviews, documents, media, departments | no |
| `web_research` | public research on the company's own site | upstream |
| `client_stack` | `company_systems`, grounded-filtered | no |
| `tools_catalog` | catalog matches + consultant endorsements | no |
| `agentic_ideas` | published ideas | upstream |
| `narrative` | **`NarrativeWriter`** — governing thought, supporting points, stakes | **yes** |
| `executive_summary` | deterministic prose, overwritten by the narrative when grounded | maybe |
| `expert` | **injected at render time**, never stored (see below) | no |

**Note the ratio.** Almost the entire report is deterministic and evidence-derived. The
LLM writes prose *over* it and can only ever replace prose — never a number, never a
signal, never a recommendation.

`MetricExtractor` deserves a mention: it is pure regex over document chunks and
interview answers, recognising KPI table rows (`Label | target | actual` — the
highest-value shape, since it already carries the "so what"), durations, currency,
percentages and ratios. Zero LLM calls, so no latency and no hallucination risk. Every
metric carries the source *category* it came from — never the filename, which is
working-paper detail and often reveals more than intended.

### 6.4 The hallucination guardrail

`Reports::NarrativeWriter` has three defences:

1. **The model never sees raw scores.** `band()` converts strength/confidence to
   `"high" | "medium" | "low"` before the context is built, so the model cannot parrot
   *"a signal strength of 0.74"* into client prose.
2. **Every generated sentence is number-checked.** `Llm::GroundedNumbers.grounded?`
   scans for currency, percentages, decimals, thousands and ranges, and drops any
   sentence carrying a figure not traceable to what the writer was given. A blocked
   governing thought falls back to the deterministic prose.
3. **Structural.** `call` returns `nil` on *any* exception. No model, no key, model down
   → the report still generates, from real prose.

### 6.5 Variants — one snapshot, two projections

A variant is **a section allowlist, a page template and a paper size** — never a second
analysis. The tempting alternative (a second generator) is the version that eventually
embarrasses us: two documents, two LLM passes, two sets of numbers, and one day the
brief says 40% while the full report says 55%.

```
   report_snapshot + consultant overlay + expert layer
          (generated once, reviewed once)
                       │
        ┌──────────────┴──────────────┐
        ▼                              ▼
  exec_brief                      full
  A4 portrait · 4pp               A4 landscape · ~24pp
  answer · value · actions        every section + appendix
```

`report_artifacts` is a table (not `exec_*` columns) so a third variant needs no
migration. The full report also stays on `reports.storage_key`, because every existing
download path, share link and approval check reads that column. `?variant=` selects a
rendering; no variant means the full report, so every pre-existing caller is unaffected.

### 6.6 Two render paths — the confusing part

This is the piece a reviewer is most likely to misread, so it is worth being explicit:

| | `GenerateReportService` | `RegenerateWithReviewService` |
|---|---|---|
| When | first generation of a version | at platform approval, and for live preview |
| Builds a snapshot? | **yes** — and persists it | **no** — reads the stored one |
| Delta / narrative / LLM? | yes | **no** |
| Overrides applied? | no | yes, to a deep copy |
| Expert layer injected? | no | yes |
| Review appendix? | no | yes |

**So the PDF a client downloads is produced by the second service, over a snapshot built
by the first.** `render_html` is the shared preview used by both the consultant
workspace and the platform approve screen — so the reviewer sees exactly what the client
will get, with their pending edits already applied.

### 6.7 The expert layer

`Reports::ExpertLayer` gathers the submitted reviews' opportunity figure, the publishable
`executive_conclusion` finding, every validator's credential, and the endorsed section
keys.

It is folded into the **render-time snapshot copy** by `SectionOverridesApplier` — never
into the stored column, for the same reason overrides aren't: reviews are submitted
*after* generation, and the stored snapshot must stay the untouched machine analysis.

Where several consultants each sized the opportunity, the report leads with the
**best-evidenced** figure and states how many corroborated it, rather than averaging
numbers that were reasoned differently.

*(The company API merges this layer into the detail response too — without that, the
portal could never display the one number an owner most wants, because it exists only
at render time.)*

### 6.8 Section order and the override lambda

Order follows the pyramid principle — answer first, method last:

> Cover · Contents · Executive summary · **Expert assessment** · Company context ·
> Delta · *Divider* · Signals · Patterns · Implications · Recommendations · Roadmap ·
> Opportunities · Capabilities · *Divider* · Readiness · Participation · Methodology ·
> *Appendix divider* · Review appendix

Consultant-authored sections interleave, anchored to whichever section they follow.

Every built-in section is wrapped in the same three-way lambda:

```erb
<% unless report_section_hidden?(snapshot, key) %>
  <%= ai_or_edit.call(key, condition, -> { render "reports/#{key}", ... }) %>
<% end %>
<%= custom_after.call(key) %>
```

*hidden* → nothing; *edited* → the consultant's text **replaces** the AI section (not a
note beside it); otherwise the AI render. Then any consultant-added section anchored
here.

### 6.9 Gates

**Generate gate:** readiness must reach 100 unless `allow_early_report`.

**Approve gate** — three independent blocks in `Platform::ReportsController#approve`:

1. Consultant reviews not complete → 422
2. Any review in `needs_info` → 422 (*"a consultant flagged sections needing
   clarification"*)
3. The artifact is not a real `application/pdf` → 503. **Never ship a broken
   deliverable** — a report that fell back to HTML because Gotenberg was down is not a
   PDF and must not be approved.

Only then does visibility flip to `shared_with_company` and the client get notified.

### 6.10 Share links

Per-variant, via `report_shares` — "send the board the brief" and "share everything" are
different acts, and a forwarded PDF must not drag fourteen pages of evidence behind it.
`reports.share_token` is still written for the full variant and the public controller
falls back to it, so links already in a client's inbox keep resolving. Resharing a
variant revokes its previous link.

### 6.11 The in-portal reader

`/company/reports/:id/read?variant=` serves the report's **HTML**, and the portal renders
a real reader: page-at-a-time navigation, a section jump rail, fit-page/fit-width,
arrow-key paging.

HTML rather than the PDF because we already render HTML — this is a viewer, not a
converter, and the jump rail is only possible because the reader can read the document's
own structure. It serves the **stored** markup behind the approved PDF, not a live
re-render, which would drift the moment a consultant touched an override after approval.

Labelling the jump targets is subtler than it appears: `<h1>` in this report is an
*action title* (*"Core system dependency is the deepest recurring friction, cited across
9 pieces of evidence"*) — right for the page, unreadable in a nav rail. So `.eyebrow` is
the label, **except** on consultant pages where every eyebrow reads "Expert consultant"
and four distinct sections would collapse into one target. On a 29-page report this
yields 21 jump targets that read like a table of contents.

### 6.12 Pagination

The report is paginated by us, not by the browser. `.page` is a flex column with the
footer in flow (`margin-top: auto`), and long lists are chunked into page-sized groups:

| Section | Per page |
|---|---|
| Signals (cards) | 9 |
| Patterns | 3 |
| Implications | 3 |
| Recommendations | 3 |
| Opportunities | 3 |
| Appendix findings | 4 |
| Comment groups | 6 |

**Those numbers are measured, not guessed** — by rendering each section alone through
Gotenberg and counting the resulting PDF pages. Exhibit SVGs also get an explicit
height (68mm), because they are emitted with `viewBox` + `width="100%"` and no height,
so the department heatmap rendered 111mm tall and pushed its page over. `max-height`
does **not** clamp a viewBox-sized SVG in Chromium's print path.

The invariant to check after any layout change:

```ruby
sections = html.scan(/<section[^>]*class="[^"]*\bpage\b/).size
pages    = pdf.scan(%r{/Count\s+(\d+)}).flatten.map(&:to_i).max
# equal ⇒ no section overflows
```

---

## 7. Data model reference

**Discovery**

| Table | Notes |
|---|---|
| `employees` | `participation_status`, `department`, `preferred_channel` |
| `conversations` | `status`, `question_count`, **`state_snapshot`** (blackboard lives here), `langgraph_thread_id` |
| `messages` | `direction`, `channel`, `track`, `track_ref`, **`agent_id`**, **`routing_decision`**, `is_discovery_question` |
| `conversation_insights` | per-turn `summary` + `structured_data.topics` |
| `company_memory_facts` | promoted durable facts, pgvector `embedding` |

**Documents**

| Table | Notes |
|---|---|
| `documents` | `department`, `document_type`, `sensitivity`, `consultant_visible`, `insights_preview` |
| `document_chunks` | `chunk_index`, `content`, pgvector `embedding` |
| `company_knowledge_entries` | from document analysis; `entry_type`, `department` |
| `media_attachments` | employee-sent images/PDFs, `structured_insights`, `confidence` |

**Intelligence**

| Table | Notes |
|---|---|
| `company_signals` | `signal_type`, `strength`, `departments[]`, `evidence_count`, `strength_history`, `metadata.source_excerpts` |
| `patterns` | `confidence`, `departments[]`, `linked_signal_ids`, `confidence_history` |
| `recommendations` | `priority`, `catalog_matches`, `related_signal_ids`, `company_feedback` |
| `company_systems` | inferred stack; `source`, `confidence` |
| `agentic_ideas` | `system_fit`, `value_*`, `approx_timeline`, `estimated_cost` |

**Consultant handover**

| Table | Notes |
|---|---|
| `discovery_packages` | per conversation, versioned; `agent_payload` keeps the agent's original |
| `discovery_package_items` | `kind` (issue/solution), **`origin`** (agent/consultant), `status`, `linked_item` |
| `consultant_requirements` | the consultant's need in their words; `status`, `max_questions`, `missing_aspects` |
| `discovery_followup_questions` | `queue_position`, `status`, links to the info request + sent/answered messages |
| `consultant_info_requests` / `consultant_outreaches` | delivery records per channel |

**Reporting**

| Table | Notes |
|---|---|
| `reports` | `version`, `status`, `visibility`, `review_workflow_status`, **`report_snapshot`**, `storage_key` |
| `report_artifacts` | one row per variant; `page_count`, `reader_storage_key` |
| `report_shares` | per-variant share links |
| `report_reviews` | per consultant; `overall_note`, **`opportunity_amount/_unit/_basis`** |
| `report_review_section_states` | per section: `approved` / `needs_info` / pending |
| `report_review_comments` / `_findings` | appendix content; findings carry `publishable` |
| `report_section_overrides` | `action` (hide/edit/add), `section_key`, `anchor_section`, `published` |

---

## 8. Observed behaviour — a real end-to-end run

A full scenario run against a **local Gemma 12B** model on 8 September 2026. Full
transcripts, agent reasoning and outputs are in
`docs/scenario-runs/nimbus_full_run_2026-09-08.txt`.

**Setup:** a UAE import/distribution SME. 4 real operational documents (procurement SOP,
AP three-way-match policy, supplier terms, a proforma invoice). 2 employees interviewed
— one on WhatsApp, one on web. One consultant. Ceiling 6 questions, floor 4.

**Result: 48 of 51 checks passed.** The complete pipeline ran to a real, approved,
downloadable PDF.

### What worked

- Documents ingested, chunked and embedded across two departments
- Interview identified role areas correctly from an open conversation
  (*"LPO management", "Invoice processing"*)
- Every per-turn insight was substantively correct and on-topic
- Package built via LLM: a real recommendation, 2 issues, 2 solutions, 2 drafted
  follow-ups
- The full consultant loop: stated need → agent drafted the question → sent on WhatsApp
  → employee answered through the real inbound path → attributed → re-evaluated
- 6 signals, 3 patterns, correct per-department attribution
- `MetricExtractor` pulled real quantified facts out of the documents (*72% first-pass
  three-way match against a 95% target; 9–12 day invoice-to-pay against a 5-day target;
  1 in 4 PIs mismatched*)
- Consultant's prose edit replaced the AI executive summary in the final PDF; their added
  Risk Register appeared; the `needs_info` gate blocked approval until resolved; the
  company could not download before approval and could after

### What did not, and why

Both failures were root-caused rather than logged:

**1. `slots_filled` came back empty on all 4 turns.** The model's prose was correct every
turn, but the structured field it is asked to report alongside its reply was empty — so
the dossier never marked `how_it_works` or `friction` as filled, even though the answers
plainly covered both (*"Checking the PI is fully manual — I compare it line by line"*).
Both branch turns therefore asked for the **same slot**, and the interview closed on
`stalled` rather than `dossier_complete`.

This is a **model reporting-fidelity gap, not a routing bug** — the `routing_decision`
on every message shows the correct slot was targeted each turn. The pipeline was
resilient: `BuildPackageService` also reads raw per-turn insights and parked asides, so
the handover was still good.

**2. One interview timed out.** The first branch-phase turn for the second employee ran
the full 1800s read timeout before failing, tripped the shared breaker, and every
subsequent scripted message hit the open breaker instantly. Consequence:
`SignalExtractor` only reads **completed** conversations, so that employee's six real
answers contributed nothing.

Branch-phase turns are measured at ~5,700–6,000 reasoning tokens versus ~800 for
orient-phase turns; local throughput degrades further the longer the server has been
handling back-to-back calls. On `gpt-4.1-mini` the same scenario completes both
interviews in minutes with `dossier_complete` firing normally.

**Reviewer takeaway:** the pipeline plumbing is sound and degrades gracefully. Interview
*quality* is materially model-dependent, and the one-call-does-everything turn design is
where that dependency concentrates.

---

## 9. Known gaps and open questions

Listed candidly, roughly in order of how much we would value an outside opinion.

### 9.1 The interview does not capture what a cost-quantified finding needs

This is the most significant structural gap, and it is a design question rather than a
bug.

A genuinely valuable diagnostic finding reads like:

> *Supplier prices are re-keyed item by item every morning — roughly 170 hours a year —
> with error risk on variants.*

Decomposed, that needs: **task · granularity · frequency · duration · annualised cost ·
risk**.

What the dossier actually requires is `how_it_works`, `friction` and `ai_current_usage`.
`volume_or_frequency` is **opportunistic**, with the explicit intent *"take it if they
offer it, never chase it"* — and **duration is not captured at all**. Nothing anywhere
computes an annualised figure; there is no `hours_per_year` in the schema.

`package.py` then correctly refuses to invent one (*"Do NOT introduce numbers, durations,
volumes or percentages that do not appear there"*), so the chain is honest but thin. The
quantified numbers that *do* reach the report come from `MetricExtractor` finding them
pre-stated in documents — not from the interview.

**Open question:** should the dossier require frequency and duration (making interviews
longer and more mechanical), or should quantification move to a separate consultant-led
step?

### 9.2 One LLM call is asked to do eight things

Per turn the model must react, ask, extract an insight, extract a finding, report
`slots_filled`, park an aside, name role areas, and sometimes refresh the summary. On a
strong model this works. On a weaker one, the *prose* stays good while the *structured*
fields degrade silently — precisely the failure in [§8](#8-observed-behaviour--a-real-end-to-end-run).

**Open question:** split into two calls (one to converse, one to extract) and pay the
latency, or keep one call and treat weak-model deployment as unsupported?

### 9.3 Signal detection is keyword-based

Six regex rules over document and message text. Cheap, fast, explainable, zero
hallucination risk — and blind to anything not phrased in its vocabulary, and to
domain-specific friction it has no rule for. Recall is unmeasured.

### 9.4 Agentic ideas over-produce

An observed run generated **52 ideas** from one completed interview and four documents,
many near-duplicates (*"AutoInventory Data Sync Agent"*, *"AutoEntry Sync Agent"*,
*"Smart Data Entry Assistant"* — the same idea three times), plus a formulaic
*"Workflow agent for ⟨signal⟩"* per signal type. Only the top 3 by confidence are
published to a report, so the client never sees the noise, but the generator needs
deduplication.

### 9.5 Document analysis is bypassed in the main flow

`Multimodal::ParseDocumentService` and the docs-analysis LangGraph produce structured
knowledge entries, but the end-to-end scenario creates documents directly. Documents
therefore contribute via chunk keyword matching and metric extraction rather than the
richer analysis. Worth deciding whether that pipeline is load-bearing or vestigial.

### 9.6 Solution detail in a diagnostic report

The current report includes `recommendations.implementation_outline` ("How: …"),
`agentic_ideas` with `approx_timeline` and `estimated_cost`, and a named-vendor
`tools_catalog` with fit scores. That is buildable specification and procurement
guidance. Whether a first-stage diagnostic report *should* contain it is a live
commercial question, not a technical one.

### 9.7 Smaller items

- **`ReportSections::KEYS` is 7; `BUILT_IN_SECTIONS` is 14.** A section can be
  rewritten by a consultant without ever being formally reviewed.
- **Readiness and Participation are internal metrics in a client document.** Readiness is
  our own go/no-go gate (generation is blocked until it hits 100) and Participation is a
  delivery KPI. Both moved to the back matter; whether they belong at all is open.
- **`docs/AGENT_ARCHITECTURE.md` is stale.** It documents the retired specialist-queue
  engine (per-specialist question budgets, `agent/app/router.py`) which no longer
  exists. **This document supersedes it.**
- **The Playwright browser suite is not in CI.** 16 tests, all passing, but they need the
  compose stack plus a seed task, so they currently run on demand.
- **The scenario runner does not wait for retry jobs.** When a turn fails it schedules a
  retry at +30s but the script marches on, so a recoverable failure reads as a permanent
  one.
- **No formal evaluation harness for interview quality.** We have a companion eval and
  scenario checks, but nothing that scores whether an interview *learned the right
  things* other than `close_reason` distribution.

---

## Where to look in the code

| Area | Start here |
|---|---|
| Agent service surface | `agent/app/main.py` |
| Interview control flow | `agent/app/area_flow.py`, `orchestrator.py`, `dossier.py` |
| Interview prompt | `agent/app/multi_agent_llm.py` |
| Model plumbing | `agent/app/openai_factory.py`, `circuit_breaker.py`, `json_parse.py` |
| Other agents | `agent/app/package.py`, `requirements.py`, `companion.py`, `docs_analysis_graph.py` |
| Turn orchestration | `backend/app/services/discovery/process_turn_service.rb` |
| Context assembly | `backend/app/services/discovery/context_builder.rb` |
| Inbound routing | `backend/app/services/inbound/track_router.rb` |
| Intelligence | `backend/app/services/intelligence/` |
| Report pipeline | `backend/app/services/reports/` |
| Report templates | `backend/app/views/reports/` |
| Consultant loop | `backend/app/services/consultant_requirements/` |
| Deeper report detail | `docs/REPORT_GENERATION.md` |
| A real observed run | `docs/scenario-runs/nimbus_full_run_2026-09-08.txt` |
| Department attribution | `docs/SIGNAL_DEPARTMENT_ATTRIBUTION.md` |
