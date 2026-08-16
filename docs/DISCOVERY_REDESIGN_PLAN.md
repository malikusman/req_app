# Discovery interview redesign — map, then branch

**Problem:** after ~Q7 the WhatsApp discovery interview feels repetitive and pushy,
usually circling inter-department communication / handoffs, with an "expert
interrogator" tone. **Goal:** same intel, same 10-question cap, but a companion
voice and a flow that maps the person's real work first, then explores each area
in short threads — including a light "have you thought about AI here?" beat.

This is a **routing + coverage + prompt** change, not copy-only. It lives almost
entirely in the Python agent (`agent/app/`), with two small Rails touches.

---

## Why it stalls today (verified in code)

| # | Root cause | Where |
|---|---|---|
| 1 | Q5–8 is the `process` specialist, whose whole persona is "handoffs between people and teams" — and the `domain` agent already asked about coordination in Q1–4. Same lens twice. | `personas.py` (PROCESS, DOMAIN), `router.py` build order |
| 2 | The 5-topic coverage checklist is usually "all covered" by ~Q5–6, so the only prompt nudge toward new ground disappears. | `state.py` `COVERAGE_TOPICS`; `multi_agent_llm.py` "topics still missing" |
| 3 | `followup.topic` = topic of the **new** question; `prepare_turn` re-injects it next turn as "follow up on handoffs" → self-reinforcing loop. | `orchestrator.py` `finalize_turn` / `prepare_turn` |
| 4 | Depth-2 cap keys on a free-text topic string, so relabeling ("handoffs"→"coordination") starts a fresh thread; threads never pruned; `prepare` always takes `open_threads[0]`. | `orchestrator.py` |
| 5 | Only last **6** messages + a summary refreshed every **3** turns are visible; by Q7–8 the model can't see Q1–4 and re-asks. Prompt never lists prior questions. | `multi_agent_llm.py` (`history[-6:]`), `orchestrator.py` `SUMMARY_REFRESH_EVERY=3` |
| 6 | Persona tone is "McKinsey-caliber" / "systems architect"; companion warmth only starts after `completed`. | `personas.py` |
| — | No content-based routing: the queue is built once and agents change only when their question budget is spent. | `router.py`, `orchestrator.py pick_active_agent` |

---

## Target flow

**Phase A — Orient (Q1–3).** One warm interviewer, building on the profile already
captured (`role_title`, `responsibilities`, `primary_tools` from `ProfilingHandler`),
asks 2–3 light questions to surface the person's **2–3 main role areas** (the concrete
chunks of what they actually do) and writes them to the blackboard as `role_areas`.

**Phase B — Branch (Q4–10).** For each area, run a short 1–3 question arc, then
**force-switch to the least-covered area**. Each area cycles the same friendly beats:
- **How it works / tools** — "walk me through how you do X; what do you use?"
- **Where it snags** — "what's the annoying part / where does it wait?"
- **AI openness** — "have you thought about letting AI take a slice of this? what would you try?"

**Tone.** Curious friendly colleague, plain language, one easy question at a time,
no pushing — from Q1, not just post-completion. Specialists stay hidden behind the
one voice; the same evidence (workflow, tools, pain, handoffs, approvals, AI-openness)
still gets collected, just organized by the person's areas instead of by fixed personas.

```
Orient Q1–3 (map 2–3 areas) → rotate least-covered area → [Area: how → pain → AI] → … → close at 10
```

---

## Changes, file by file

### Python — `agent/app/`

1. **`state.py` — per-area coverage, not a global 5-topic list.**
   - Add `role_areas: list[{name, how, pain, ai}]` to the blackboard (each cell bool).
   - Keep the 5 evidence topics as a *derived* rollup, but drive steering off the
     per-area matrix so "all covered" can't fire while areas remain unexplored.
   - Add `orient_done: bool`.

2. **`router.py` — orient phase + area-driven queue.**
   - New first agent `orient` (budget 3) that always leads.
   - After orient, build the branch queue from `role_areas` instead of the fixed
     `domain → process → technical` walk. Keep specialist personas as a *lens library*
     the branch turns can borrow, but selection is area-driven, not priority-walk.
   - Retire the "process gets budget 4 for handoffs" block as the Q5–8 default.

3. **`orchestrator.py` — content-based switching + honest follow-ups.**
   - `pick_active_agent`/`prepare_turn`: after **N questions in an area (default 2)**,
     force-switch to the least-covered area; never let one area exceed a small cap.
   - Fix `followup.topic` semantics to mean the topic **answered**; only allow a
     follow-up when the last answer was genuinely thin, and never re-inject a topic
     already marked covered for that area.
   - Prune resolved threads; stop always taking `open_threads[0]`.

4. **`multi_agent_llm.py` — anti-repeat + wider context + AI beat + tone.**
   - Pass the **list of prior question stems** into the prompt with an explicit
     "do not re-ask these" guard.
   - Widen raw history from `[-6:]` to ~`[-10:]` (or always include a compact
     per-area coverage recap so earlier ground stays visible).
   - Add the **AI-openness beat** as a first-class coverage cell per area.
   - Rewrite the framing/rules from "specialist interviewer" to companion voice.

5. **`personas.py` — tone rewrite + orient persona.**
   - Add a warm `ORIENT` persona ("a friendly colleague getting to know how you work").
   - Rewrite `DOMAIN/PROCESS/TECHNICAL/…` tone strings from "McKinsey-caliber" to
     curious-and-plain, keeping their *topic focus* as the lens for area threads.
   - Widen `PROCESS` beyond handoffs, or fold it into the per-area "pain" beat so it
     isn't a standalone 4-question block.

### Rails — `backend/app/`

6. **`discovery/context_builder.rb`** — surface `role_areas` (and profiling
   `responsibilities`/`primary_tools`) so the graph can seed orient/branch. Consider
   raising the history window sent on the turn payload to match (4).

7. **Settings (`company.rb DEFAULT_SETTINGS`)** — add tunables:
   `discovery_orient_questions` (3), `discovery_max_questions_per_area` (3),
   `discovery_switch_after` (2). Keep `discovery_question_target` (10).

*(No change needed to `ProfilingHandler` — it already collects the role card the
orient phase builds on.)*

---

## Guardrails

- Keep the **10-question cap** and the deterministic close.
- Keep specialists **hidden** (one voice); this is about *how questions are chosen
  and phrased*, not exposing agents.
- Preserve fail-safe: LangGraph/LLM errors still fall back to the delay copy +
  `RetryDiscoveryTurnJob`.
- The AI-openness answers should flow into the same insight → `AgenticIdeaWriter`
  path so "have you thought about AI" directly enriches the report's opportunity ideas.

## Suggested phasing

1. **Tone-only** rewrite of `personas.py` + `multi_agent_llm.py` framing (fast, low-risk, immediate UX win).
2. **Anti-repeat + wider context + follow-up fix** (kills the loop without restructuring routing).
3. **Orient + area-driven routing + per-area coverage** (the structural change).

Each phase is shippable and independently testable via the local Gemma discovery
harness (`agent/tests` + the scenario runners).
