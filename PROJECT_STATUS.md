# Worktruth — Project Status & Demo Guide

> Last updated: July 2026  
> Brand: **Worktruth** (repo/codename: `req_app`)

This document explains **what Worktruth is**, **what has been built**, **where we are now**, **how the demo seed works**, and **what is left to do**.

---

## Table of contents

1. [What Worktruth is](#what-worktruth-is)
2. [Architecture at a glance](#architecture-at-a-glance)
3. [What we have done (by phase)](#what-we-have-done-by-phase)
4. [Multi-agent discovery (latest major feature)](#multi-agent-discovery-latest-major-feature)
5. [Demo seed — companies, users, employees](#demo-seed--companies-users-employees)
6. [How to run locally](#how-to-run-locally)
7. [How to test / dry-run](#how-to-test--dry-run)
8. [Portal capabilities today](#portal-capabilities-today)
9. [Where we are currently](#where-we-are-currently)
10. [What is left](#what-is-left)
11. [Key file map](#key-file-map)

---

## What Worktruth is

**Worktruth** is an enterprise workflow discovery platform. It:

1. **Builds a document baseline** — upload SOPs, policies, and exports for signals without inviting employees yet.
2. **Interviews employees over WhatsApp or web chat** — adaptive AI questions, voice notes, images, documents.
3. **Structures evidence into intelligence** — signals, patterns, recommendations, readiness scores.
4. **Delivers governed reports** — versioned HTML/PDF, reviewer QA, platform approval, share links.

Three authenticated portals serve different audiences:

| Portal | Audience |
|--------|----------|
| **Platform** (`/platform`) | Worktruth operators — companies, trials, playbooks, audit, system health |
| **Company** (`/company`) | Client admins — employees, documents, intelligence, reports, billing |
| **Reviewer** (`/reviewer`) | External experts — assigned companies, report review, WhatsApp follow-ups |

The **marketing site** (`/`) is the public homepage for prospects (light shadcn-based theme). Privacy: `/privacy`.

---

## Architecture at a glance

```
┌─────────────────────────────────────────────────────────────────┐
│  Frontend (React + Vite + Tailwind)                             │
│  Marketing /  Platform portal / Company portal / Reviewer portal│
└────────────────────────────┬────────────────────────────────────┘
                             │ REST API (JWT)
┌────────────────────────────▼────────────────────────────────────┐
│  Rails 7 API                                                    │
│  WhatsApp webhooks · Discovery orchestration · Intelligence     │
│  Reports · Billing (Stripe) · Sidekiq jobs                      │
└──────┬──────────────────────────────┬───────────────────────────┘
       │                              │
       ▼                              ▼
┌──────────────┐              ┌──────────────────┐
│ PostgreSQL   │              │ LangGraph agent  │
│ + pgvector   │              │ (FastAPI/Python) │
│ MinIO, Redis │              │ Single + multi-  │
└──────────────┘              │ agent discovery  │
                              └──────────────────┘
```

**Employee journey (WhatsApp):**

```
Invite → Onboarding (name, access code, consent)
      → Profiling (role, department, seniority, tools)   [flag-gated]
      → Multi-agent discovery interview                  [flag-gated]
      → Conversation completed → memory promotion → intelligence aggregate
```

Rails owns **canonical state** (`conversations.state_snapshot` blackboard). The agent service is **stateless per turn** — blackboard travels in/out on each HTTP call.

---

## What we have done (by phase)

| Phase | Status | Summary |
|-------|--------|---------|
| **1 — Auth & portals** | Done | Dual JWT (platform/company/reviewer), onboarding wizard, company CRUD |
| **2 — WhatsApp** | Done | Meta webhook, onboarding state machine, access codes, consent, nudges, simulate rake task |
| **3 — LangGraph discovery** | Done | Single-agent turns, playbooks, circuit breaker, conversation insights |
| **4 — Multimodal** | Done | Voice (Whisper), images (Vision), PDF upload + chunk embed (pgvector) |
| **5 — Intelligence** | Done | Signals, patterns, recommendations, timeline, readiness score |
| **6 — Reports** | Done | Versioned HTML/PDF (Gotenberg), share links, platform approval gate |
| **7 — Hardening & billing** | Done | Notifications, Stripe/mock checkout, impersonation, conversation limits, monitoring |
| **8 — Reviewer role** | Done | Reviewer portal, report section review, WhatsApp follow-ups, co-reviewer chat |
| **Demo wiring** | Done | Rich Acme + Beta seed, platform/company/reviewer dashboards wired to APIs |
| **Multi-agent (A/B/C)** | Done | Profiling, supervisor agents, blackboard, company memory, debug UI, dry-run simulator |
| **Marketing redesign** | Done | Light theme, dual-path docs + interviews positioning, Worktruth brand |
| **Portal UI refresh** | In progress | Docs-first IA, empty states, honesty banners |
| **Multi-agent Phase D** | Planned | Postgres checkpointer, Reviewer Liaison + Gap Analyst agents |

---

## Multi-agent discovery (latest major feature)

Enabled per company via `company.settings` (Acme and Beta have these **on** in seed):

| Setting | Default | Demo (Acme/Beta) |
|---------|---------|------------------|
| `discovery_profiling_enabled` | `false` | `true` |
| `discovery_multi_agent_enabled` | `false` | `true` |
| `discovery_memory_retrieval_enabled` | `false` | `true` |
| `discovery_question_target` | `10` | `12` |
| `discovery_max_followup_depth` | `2` | `2` |
| `discovery_max_questions_per_agent` | `5` | `5` |
| `discovery_max_active_agents` | `4` | `4` |

### Phase A — Profiling

- New conversation status: `profiling`
- [`Whatsapp::ProfilingHandler`](backend/app/services/whatsapp/profiling_handler.rb) asks: role title, department, seniority, responsibilities, team size (managers+), primary tools
- Profile stored on `employees` (`role_title`, `seniority`, `metadata.profile`)
- Routing: consent → profiling → discovery (when flag on)

### Phase B — Multi-agent supervisor

- Python supervisor graph: `prepare → interview → finalize` (+ `close` when budgets exhausted)
- Specialist agents: **domain**, **process**, **technical**, **strategic** (routed from profile)
- Shared **blackboard** in `conversations.state_snapshot` — agent queue, findings, coverage, rolling summary
- [`Discovery::ProcessTurnService`](backend/app/services/discovery/process_turn_service.rb) extended payload; legacy single-agent path when flag off
- Mock mode works without `OPENAI_API_KEY` **only** when `ALLOW_MOCKS=1` or in development/test; production fails closed.

### Phase C — Company memory + debug UI

- `company_memory_facts` table with pgvector embeddings
- [`MemoryPromotionJob`](backend/app/jobs/memory_promotion_job.rb) on conversation finalize (confidence ≥ 0.6)
- Flag-gated retrieval of similar facts + document chunks into agent turns
- Platform conversation detail: **Discovery agents** panel (queue, coverage, findings, routing)

### Dry-run simulator

End-to-end test without WhatsApp:

```bash
docker compose run --rm rails bundle exec rails demo:simulate
PERSONA=hr_manager CLEANUP=1 docker compose run --rm -e PERSONA -e CLEANUP rails bundle exec rails demo:simulate
```

Runs onboarding → profiling → multi-agent interview → memory promotion with ~32 automated checks.

---

## Demo seed — companies, users, employees

### How seeding works

```bash
# Full seed (base accounts + Acme + Beta demo data)
docker compose run --rm rails bash -c "bundle install && bundle exec rails db:seed"

# Re-run demo data only
docker compose run --rm rails bundle exec rails demo:seed        # Acme only
docker compose run --rm rails bundle exec rails demo:seed_beta   # Beta only
docker compose run --rm rails bundle exec rails demo:reset       # Both
```

Seed flow in [`backend/db/seeds.rb`](backend/db/seeds.rb):

1. Platform admin, consent texts (EN/ES), discovery playbooks (finance, sales, hr, operations, support, executive, default)
2. Solution catalog entries (Zapier, UiPath, Bill.com, Make, Notion AI)
3. **Acme Corp** + **Beta Industries** with multi-agent flags enabled
4. [`DemoSeeder`](backend/lib/demo_seeder.rb) + [`BetaDemoSeeder`](backend/lib/demo_seeder.rb)
5. Prints [`DemoScript.print_walkthrough`](backend/lib/demo_seeder.rb) at the end

**All demo passwords:** `password123`

---

### Login accounts (dummy users)

| Portal | Email | Password | Notes |
|--------|-------|----------|-------|
| Platform | `admin@reqapp.local` | `password123` | Super admin — all companies, audit, playbooks, approve reports |
| Company (Acme) | `admin@acme.local` | `password123` | Acme Corp admin — full happy-path demo |
| Company (Beta) | `admin@beta.local` | `password123` | Beta Industries — expiring trial, report in review |
| Reviewer | `reviewer@reqapp.local` | `password123` | Published profile, assigned to Acme + Beta |
| Reviewer 2 | `reviewer2@reqapp.local` | `password123` | Draft profile, **not assigned** to any company |

Portal URLs (dev): http://localhost:5173/platform/login · `/company/login` · `/reviewer/login`

---

### Acme Corp (`slug: acme-corp`)

**Purpose:** Happy-path demo — completed interviews, intelligence, approved shared report, reviewer activity.

| Setting | Value |
|---------|-------|
| Plan | Trial (30 days) |
| Onboarding | Complete |
| Multi-agent flags | All enabled |
| Report | Generated, platform-approved, `shared_with_company` (downloadable) |
| Reviewer | `reviewer@reqapp.local` assigned |

#### Demo employees

| Name | Phone | Department | Role | Status | Conversation |
|------|-------|------------|------|--------|--------------|
| **Jordan Lee** | +14155551001 | finance | Accounts Payable Specialist (IC) | completed | completed — SAP/Excel invoice reconciliation |
| **Sam Rivera** | +14155551002 | operations | Logistics Coordinator (team lead) | completed | completed — cross-team handoffs, Jira/Slack |
| **Alex Kim** | +14155551003 | sales | — | invited | none (nudge demo) |
| **Taylor Morgan** | +14155551004 | hr | HR Operations Manager (manager) | completed | completed — manual onboarding paperwork |

Each completed employee has profile card data (`role_title`, `seniority`, `metadata.profile`) for multi-agent routing demos.

#### Other Acme seed data

- **Documents:** `month-end-checklist.pdf`, `onboarding-playbook.docx` (ready, with insights preview)
- **Question feedback:** 3 discovery questions flagged (2 relevant, 1 not relevant)
- **Nudge:** Alex Kim received a reminder nudge 1 day ago
- **Timeline events:** interview_completed for each finished conversation
- **Reviewer profile:** Published with experience, expertise tags, LinkedIn
- **Reviewer activity:** Follow-up with Sam Rivera (replied), co-reviewer chat, partial report review (executive summary approved, comment on signals)
- **Platform audit logs:** company created, reviewer assigned, report generated, report approved

---

### Beta Industries (`slug: beta-industries`)

**Purpose:** “In review” demo — expiring trial, report awaiting platform approval.

| Setting | Value |
|---------|-------|
| Plan | Trial (**4 days left**) |
| Multi-agent flags | All enabled |
| Report | Ready, reviewer submitted, **awaiting platform approval** |
| Reviewer | `reviewer@reqapp.local` assigned |

#### Demo employees

| Name | Phone | Department | Status | Conversation |
|------|-------|------------|--------|--------------|
| **Casey Brooks** | +14155552001 | operations | started | discovery (in progress) |
| **Riley Chen** | +14155552002 | finance | invited | none |

---

### Suggested demo walkthrough

Printed automatically after `db:seed`:

1. **Company (Acme)** → dashboard KPIs, employees with profiles, conversations, intelligence, download approved report
2. **Reviewer** → report section review, follow-ups, co-reviewer chat on Acme
3. **Platform** → companies list, Acme intelligence/conversations (agent debug panel), trials, audit log, **approve Beta report**
4. **Company (Beta)** → verify report download after platform approval

---

## How to run locally

```bash
docker compose up --build

# First time or after Gemfile changes
docker compose run --rm rails bash -c "bundle install && bundle exec rails db:migrate db:seed"
```

| Service | URL |
|---------|-----|
| Marketing + portals | http://localhost:5173 |
| Rails API | http://localhost:3000 |
| LangGraph agent | http://localhost:8000/health |
| Mailpit | http://localhost:8025 |

Set `OPENAI_API_KEY` in `docker-compose.yml` or `.env` for real LLM questions; without it, mock mode cycles canned questions per agent.

---

## How to test / dry-run

| Task | Command |
|------|---------|
| Full multi-agent dry run | `rails demo:simulate` |
| HR manager persona | `PERSONA=hr_manager rails demo:simulate` |
| Clean up sim data | append `CLEANUP=1` |
| WhatsApp simulate | `rails whatsapp:simulate PHONE=+1... TEXT="..."` |
| Single discovery turn | `rails discovery:turn PHONE=+1... TEXT="..."` |
| Backend specs | `bundle exec rspec` (83 examples; uses isolated `req_app_test` DB) |
| Re-seed demo | `rails demo:reset` |

---

## Portal capabilities today

### Platform (`admin@reqapp.local`)

- Companies, trials, impersonation
- Conversations tab with **agent debug panel** (queue, coverage, findings)
- Intelligence tab (snapshot, signals, patterns, recommendations, timeline)
- Reviewers CRUD + assignment (max 2 per company)
- Playbooks, solutions catalog, audit log, system monitoring
- Report approval gate

### Company (`admin@acme.local` / `admin@beta.local`)

- Dashboard with KPIs, participation summary, emerging patterns
- Employees (with `role_title`, `seniority`, profile), nudges
- Conversations, documents, intelligence snapshot
- Reports (download when `shared_with_company`)
- Settings, billing, onboarding wizard

### Reviewer (`reviewer@reqapp.local`)

- Dashboard with portfolio KPIs, action queue, recent follow-ups
- Assigned company cards with report/review status
- Report section-by-section review
- WhatsApp follow-ups with employees (hidden from company API)
- Co-reviewer chat, notifications

### Marketing (`/`)

- 10 sections: hero (discovery graph animation), problem, how it works, discover bento, platform, personas, social proof, FAQ, CTA, footer
- Dark Innoventures-inspired palette (cyan accent, gold eyebrows)
- `motion/react` scroll reveals + hero graph animation
- **Planned:** light theme redesign inspired by ImagineArt / workflow canvas aesthetics

---

## Where we are currently

### Done and on `main`

- Full WhatsApp → discovery → intelligence → report pipeline
- Three portals wired to real APIs with rich demo data
- Multi-agent discovery (profiling, supervisor, memory, platform debug UI)
- Dry-run simulator with automated checks
- CI workflow (`.github/workflows/ci.yml`) — backend RSpec + frontend lint/build
- Test DB isolation fix (`database.yml` forces `req_app_test` in test env)

### In progress / next up

1. **Marketing website redesign** (user priority — start here before portals)
   - Light, modern palette suited to enterprise AI / workflow discovery
   - Inspiration: ImagineArt business site, node-based “open workflows” canvas aesthetic
   - 21st.dev components (bento grid hero, staggered hero, feature blocks)
   - UI UX Pro Max skill for design intelligence
   - Smooth Motion frame: scroll-linked reveals, workflow node animations, reduced-motion fallbacks
   - Scope: `frontend/src/marketing/**` only — portal tokens unchanged

2. **Internal portal UI refresh** (after marketing)
   - Apply modern light design system to platform/company/reviewer

3. **Multi-agent Phase D** (later)
   - Postgres LangGraph checkpointer (ephemeral, for human-in-the-loop)
   - Reviewer Liaison + Gap Analyst agents with suggest-only follow-up drafts

### Known gaps / polish

- Marketing site still dark; copy in `content.ts` has unused hero fields
- `reviewer2@reqapp.local` has draft profile only (intentional — shows unpublished state)
- Alex Kim (Acme) stays `invited` to demo nudge flow
- Beta report requires platform approval step in walkthrough
- `agent/app/__pycache__/` should stay out of git (add to `.gitignore` if needed)

---

## What is left

### Marketing site (immediate)

- [ ] Define light color system (replace dark `marketing-*` tokens)
- [ ] Redesign hero — workflow canvas / node graph visual (ImagineArt-inspired)
- [ ] Adopt 21st.dev blocks (bento grid, hero stagger, testimonials)
- [ ] Motion system doc: entrance, scroll, hover, hero loop timings
- [ ] Install UI UX Pro Max skill in Cursor for design passes
- [ ] Mobile polish, contrast audit, `npm run build` pass

### Portals (phase 2 of UI work)

- [ ] Shared modern light design tokens for `/platform`, `/company`, `/reviewer`
- [ ] Dashboard density and visual hierarchy refresh
- [ ] Reviewer notification bell in layout (optional)

### Product / agent (phase D)

- [ ] LangGraph Postgres checkpointer (24h TTL, blackboard stays authoritative)
- [ ] Reviewer Liaison agent — suggest follow-up drafts in reviewer portal
- [ ] Gap Analyst agent — async cross-conversation gap detection

### Ops / docs

- [ ] Update root [`README.md`](README.md) with multi-agent + demo:simulate sections
- [ ] Add `__pycache__/` to `.gitignore`

---

## Key file map

| Area | Path |
|------|------|
| Demo seed (Acme) | [`backend/lib/demo_seeder.rb`](backend/lib/demo_seeder.rb) |
| Demo seed (Beta) | [`backend/lib/demo_seeder.rb`](backend/lib/demo_seeder.rb) (class `BetaDemoSeeder`) |
| Demo rake tasks | [`backend/lib/tasks/demo.rake`](backend/lib/tasks/demo.rake) |
| Dry-run simulator | [`backend/lib/discovery_simulator.rb`](backend/lib/discovery_simulator.rb) |
| Base seed | [`backend/db/seeds.rb`](backend/db/seeds.rb) |
| Profiling handler | [`backend/app/services/whatsapp/profiling_handler.rb`](backend/app/services/whatsapp/profiling_handler.rb) |
| Turn orchestration (Rails) | [`backend/app/services/discovery/process_turn_service.rb`](backend/app/services/discovery/process_turn_service.rb) |
| Multi-agent graph (Python) | [`agent/app/multi_agent_graph.py`](agent/app/multi_agent_graph.py) |
| Agent router | [`agent/app/router.py`](agent/app/router.py) |
| Company memory | [`backend/app/models/company_memory_fact.rb`](backend/app/models/company_memory_fact.rb) |
| Marketing page | [`frontend/src/marketing/MarketingPage.tsx`](frontend/src/marketing/MarketingPage.tsx) |
| Marketing tokens | [`frontend/src/marketing/marketing-tokens.ts`](frontend/src/marketing/marketing-tokens.ts) |
| Marketing design skill | [`.cursor/skills/req-marketing-design/SKILL.md`](.cursor/skills/req-marketing-design/SKILL.md) |
| Platform agent debug UI | [`frontend/src/portals/platform/DiscoveryAgentPanel.tsx`](frontend/src/portals/platform/DiscoveryAgentPanel.tsx) |

---

## Quick reference — all demo credentials

```
Platform:   admin@reqapp.local      / password123
Acme:       admin@acme.local        / password123
Beta:       admin@beta.local        / password123
Reviewer:   reviewer@reqapp.local   / password123
Reviewer 2: reviewer2@reqapp.local  / password123  (draft, unassigned)
```

Re-seed anytime:

```bash
docker compose run --rm rails bash -c "bundle install && bundle exec rails db:seed"
```
