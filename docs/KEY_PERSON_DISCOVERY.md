# The conversation with leadership (key-person discovery)

How the Doc 08 conversation is built, what it stores, what it lets out, and what is still
open. For where it sits among the other model steps, see [AGENTS.md](AGENTS.md) §4 rows
18–20 and Flow 9; for what the client sees, [APPLICATION_GUIDE.md](APPLICATION_GUIDE.md)
§4.4a.

## Where it lives, and why

The employee interview's engine (the LangGraph `record → prepare → talk` graph, the
dossier, `Discovery::ProcessTurnService`, the WhatsApp handlers) would be its natural home,
but that code is changing in parallel. So this conversation is built in Rails, in
`backend/app/services/key_person/`, in the same three-step shape:

| Step | Class | Model |
|---|---|---|
| Record the answer | `KeyPerson::Capture` | P03 (JSON) |
| Decide the next turn | `KeyPerson::Planner` | none — plain Ruby over stored state |
| Say it | `KeyPerson::Interviewer` + `KeyPerson::Guard` | P02 (text) |
| After the last turn | `KeyPerson::ContextBuilder` (`KeyPersonContextJob`) | P04 (JSON) |

`KeyPerson::Turn` runs one step: the answer is saved first, then capture, effects
(profile facts, review flags), the planner, the reply, all under a lock on the session.
It has its own tables (`conversation_sessions`, `conversation_turns`), so no employee-side
job ever reads it. Once both engines settle they can be compared and merged.

Prompts are files: `app/prompts/p00a_analytical_base.v1.txt` and
`p00c_conversational_base.v1.txt` (Doc 24 §5, verbatim; a spec keeps P01's preamble equal
to P00-A), `p02_key_person_interviewer.v1.txt` (rules, then one block per turn mode after
`@@ MODE`), `p03_key_person_turn_capture.v1.txt`, `p04_key_person_findings.v1.txt`.

## The planner

State lives in `conversation_sessions.state_snapshot`: coverage per area, the current
instruction, recent questions, a running summary, and what was mentioned (documents,
people, contradictions). After each answer, in order:

1. a wish to pause or stop, or a question from the participant, comes first
   (`HANDLE_ASIDE` answers it, then returns to the same area);
2. a vague answer gets **at most one** follow-up on that area (`FOLLOW_UP`, or `EXAMPLE`
   when they stressed it), never after they went into operational detail;
3. one light clarification per conversation of a fact that contradicts the profile;
4. close at the ceiling, after a stall, or once coverage is sufficient and the floor is
   reached;
5. otherwise ask the most valuable open area: Essential areas for the persona first, then
   the rest, with a reflection every fourth question.

Closing is always read-back → scope and participants → documents (if any were mentioned,
at most three) → "anything else?" → closing words.

**Coverage:** 16 areas (Doc 08 §8 plus ambition and released time), weighted Essential,
Important or Where relevant for three columns — CEO/owner, GM/COO, department head (§8.2).
Every functional head is weighted as a department head. **Sufficient** = every Essential
area usable or settled as unknown, and every Important one at least raised.

**Limits:** floor 8, ceiling 24, stall 3 participant turns — a company's
`key_person_limits` setting, then `KEY_PERSON_FLOOR` / `_CEILING` / `_STALL`, then those
defaults. The close reason (`COVERAGE_COMPLETE`, `STALLED`, `CEILING`,
`PARTICIPANT_ENDED`, `ABANDONED`) is the health measure: `rails key_person:health`.

## What it stores (Doc 06 objects)

| Table | Doc 06 | Notes |
|---|---|---|
| `engagement_participants` (+ columns) | Participant | persona, participation status, link digest and expiry, consent, reminders, consultant focus; the key user has a `KEY_USER` row |
| `conversation_sessions` | ConversationSession | Doc 08 states, plus `ABANDONED`; `needs_review` is a flag, not a state |
| `conversation_turns` | ConversationTurn | text as said; `capture` is the validated P03 output; locator `t<n>` is the evidence id |
| `management_discovery_contexts` | ManagementDiscoveryContext + PoliticalContext | one version per session; `consultant_private` holds political context and notes |
| `strategic_findings` | StrategicFinding | a correction is a new version; rejected ones are kept |
| `planned_initiatives` | PlannedInitiative | |
| `document_requests` | DocumentRequest | uploads are `documents` with source `key_person_upload` |
| `ai_runs` | AI run (Doc 05 §21) | every P02/P03/P04 call: model, tokens, time, status, fallback reason |

## The firewall — the contract for the employee interview

Nothing from these conversations reaches the employee interview, the agent pack, document
analysis, the client portal (beyond the other managers' *status*), or another key
person. `spec/firewall/key_person_context_spec.rb` plants a sentinel in every store and
checks every one of those paths.

The **one** sanctioned route to staff is:

```ruby
Companies::AgentContext.neutral_management_context(company, department: "Finance")
# => ["The company wants to respond to customer enquiries faster.", ...]
```

Short neutral lines P04 wrote for a department (or the whole company), already stripped
of anything that attributes a view to management, names a person, suggests a solution or
carries a number. It is **not** added to `for_agents`: the employee interview opts in
where it builds its context. Whether a consultant must approve these lines first is an
open question (below).

Leadership uploads are stored but never ingested, chunked or marked ready — the employee
interview's context builder reads every ready chunk the company has — and never listed in
the client portal or picked into a document analysis run.

## Switches and models

- `AI_KEY_PERSON=false`, or no model configured: the conversation isn't offered; the
  dashboard says the team will arrange it; a Mjadi user can still move the engagement on.
- `KEY_PERSON_MODEL`, `KEY_PERSON_CAPTURE_MODEL`, `KEY_PERSON_CONTEXT_MODEL`, each falling
  back to `OPENAI_MODEL`.
- Outside production, a company's `key_person_scripted_replies` setting (or
  `KEY_PERSON_SCRIPTED_REPLIES=1`) runs it on `KeyPerson::ScriptedClient` — for the demo
  and the browser test only.

## Running it

```sh
# after demo:onboarding, or with FRESH=1 to run onboarding first
docker compose exec rails bundle exec rails demo:key_person            # scripted replies
docker compose exec rails bundle exec rails demo:key_person REAL=1     # the configured model

docker compose exec rails bundle exec rails key_person:eval            # benchmark scenarios, real model
docker compose exec rails bundle exec rails key_person:eval SCRIPTED=1 # smoke-test the harness
docker compose exec rails bundle exec rails key_person:health

# browser test
docker compose exec rails bundle exec rails e2e:seed_key_person
docker run --rm --network req_app_default -v "$PWD/frontend:/src:ro" -e E2E_BASE_URL=http://frontend:5173 \
  mcr.microsoft.com/playwright:v1.56.1-noble bash -c "mkdir -p /work && cp -r /src/e2e /src/playwright.config.ts /work && \
  cd /work && npm init -y >/dev/null && npm i --silent @playwright/test@1.56.1 && npx playwright test e2e/key_person.spec.ts"
```

Scenarios for the benchmark are in `backend/spec/fixtures/key_person/scenarios/*.yml`:
answers per area, lines injected at given answers, and what the scenario expects.

## Decided here, open with the client

Where the documents disagree or are silent, this build chose:

1. **Pricing waits for the key user's conversation only.** Other managers' conversations
   continue; anyone they add is flagged `added_after_pricing`.
2. **Managers are invited when onboarding is submitted** (Doc 07 §12), not after the key
   user's conversation.
3. **Managers get a link, not a portal account** (J3 is "assumed" in the Decision Register).
4. **Text and voice notes at launch** (Doc 22 E2's fallback); streaming two-way voice waits
   for the vendor evaluation (Doc 14 §16).
5. **No one-time code on a new device** for managers' links (Doc 14 §4.3).
6. **The production model** for P02–P04 is not decided; release decisions need it (Doc 05 §3.2).
7. **P00-C is used verbatim**, though its first paragraph is written for employees.
8. **Neutral context reaches staff without consultant approval**, on the code check alone.
9. **Retention** of transcripts is described to participants as "while Mjadi works with
   your company"; the actual policy needs confirming.

Also chosen without a document to settle it: Doc 08's conversation states rather than Doc
06's generic set; `NEEDS_CONSULTANT_REVIEW` as a flag; P04's `DECISIONS_APPROVALS` example
category stored as `GOVERNANCE`; Doc 08's twelve personas mapped onto Doc 08 §8.2's three
weighting columns.

## Not built yet

Streaming voice; WhatsApp replies from key persons (the inbound handler only knows
employees, so reminders are email); document masking and OCR, so P04 doesn't read
uploads; the `EvidenceReference` table (turn locators stand in); the server-side block on
inviting staff before the Stage 1 fee is agreed (part of the pricing work); wiring the
neutral context into the employee interview (the teammate's side).
