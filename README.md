# Req — Enterprise Workflow Discovery Platform

AI-powered workflow discovery via WhatsApp, with dual portals for platform operators and company admins.

## Stack

- **Backend:** Rails 7 API, PostgreSQL + pgvector, Sidekiq, JWT auth
- **Frontend:** React + TypeScript (Vite), dual portal routing
- **Agent:** LangGraph + FastAPI (Python), OpenAI
- **Infra:** Docker Compose (Postgres, Redis, MinIO, Mailpit, LangGraph, Gotenberg)

## Quick start

### Prerequisites

- Docker & Docker Compose
- Ruby 3.1+ (for local Rails without Docker)

### Run with Docker

```bash
cd req_app
docker compose up --build

# First time (or after Gemfile changes): migrate + seed
docker compose run --rm rails bundle exec rails db:migrate db:seed
```

If Rails/Sidekiq fail with `Could not find stripe-...`, restart after `docker compose up --build` (compose runs `bundle install` on start) or run:

```bash
docker compose run --rm rails bundle install
docker compose up
```

- **Frontend:** http://localhost:5173
- **API:** http://localhost:3000
- **LangGraph:** http://localhost:8000/health
- **Mailpit:** http://localhost:8025

### Run locally (without Docker for Rails)

```bash
# Start dependencies only
docker compose up postgres redis mailpit -d

# Backend
cd backend
cp .env.example .env
bundle install
bundle exec rails db:create db:migrate db:seed
bundle exec rails server

# Frontend (separate terminal)
cd frontend
npm install
npm run dev
```

## Seed accounts

| Portal   | Email               | Password     |
|----------|---------------------|--------------|
| Platform | admin@reqapp.local  | password123  |
| Company  | admin@acme.local    | password123  |
| Reviewer | reviewer@reqapp.local | password123 |

Acme Corp has the seed reviewer assigned (max 2 per company; invisible to company admins).

## Phase 8 (implemented) — Reviewer role & Pundit authorization

- **Reviewer portal** — http://localhost:5173/reviewer/login — assigned companies, discovery read-only, report section review, WhatsApp follow-ups (hidden from company APIs), co-reviewer chat
- **Platform reviewers** — `/platform/reviewers` — CRUD reviewer users; assign up to 2 active reviewers per company from Companies → Reviewers
- **Report review workflow** — on report ready, `report_reviews` bootstrapped per assigned reviewer; platform approve gated until `reviews_complete` (unless `skip_platform_review` in company settings)
- **Pundit** — `AuthorizationContext` for platform / company / reviewer audiences; policies on reports, employees, documents, assignments, etc.

```bash
# WhatsApp reviewer follow-up template (Meta)
export META_TEMPLATE_REVIEWER_FOLLOWUP=reviewer_followup_reopen
```

## Phase 7 (implemented) — Hardening & billing

- **In-app notification bell** — `GET/PATCH /api/v1/company/notifications`, mark-all-read; polls every 30s (ActionCable broadcast from backend when Redis available)
- **Stripe billing** — webhook `POST /api/v1/webhooks/stripe`; mock checkout when `STRIPE_SECRET_KEY` unset (`/api/v1/billing/mock_checkout`)
- **Company billing** — `/company/billing` — plan usage, upgrade to starter/growth
- **Platform impersonation** — `POST /api/v1/platform/companies/:id/impersonate` (2h session, audit logged); yellow banner + exit to platform
- **Conversation limits** — per plan (trial 25, starter 100, growth 500); enforced at WhatsApp consent → discovery
- **Platform monitoring** — `/platform/monitoring` — cross-tenant metrics

```bash
# Optional Stripe (otherwise mock checkout works)
export STRIPE_SECRET_KEY=sk_test_...
export STRIPE_WEBHOOK_SECRET=whsec_...

docker compose run --rm rails bundle exec rails db:migrate
```

## Phase 6 (implemented) — Reports, settings & system health

- **Versioned reports** — HTML/PDF via Gotenberg (HTML fallback), delta vs previous version
- **Share links** — `POST /api/v1/company/reports/:id/share` → public `GET /api/v1/public/reports/:token` (access logged)
- **Company portal:** `/company/reports`, `/company/settings` (organization + rotate access codes)
- **Platform portal:** `/platform/system` — LangGraph, Gotenberg, Redis + WhatsApp delivery metrics (24h)
- **Platform report approval** — `POST /api/v1/platform/companies/:company_id/reports/:id/approve` (when `skip_platform_review` is false)
- Acme seed has `allow_early_report` and `skip_platform_review` for local demos

```bash
docker compose run --rm rails bundle exec rails db:migrate
docker compose exec rails bundle exec rails reports:generate SLUG=acme-corp
```

Report generation requires readiness 100% unless `allow_early_report` is set in company settings.

## Phase 5 (implemented) — Intelligence

- **Signals** — extracted from conversation insights, messages, and documents
- **Patterns** — cross-signal detection (e.g. approval + manual work)
- **Recommendations** — catalog-aware (`solution_catalog`) with company feedback
- **Insights timeline** — `/company/intelligence/timeline`
- **Discovery questions preview** — flag not relevant / off-track
- **Intelligence dashboard** — pain points, patterns, readiness breakdown
- **Employee phone update** — `PATCH /api/v1/company/employees/:id/phone`
- Platform **Solutions** catalog at `/platform/solutions`

```bash
docker compose exec rails bundle exec rails intelligence:aggregate SLUG=acme-corp
```

## Phase 4 (implemented) — Multimodal

- **WhatsApp:** voice notes (Whisper), images (Vision), documents (PDF text extract)
- Async pipeline: `ProcessMediaAttachmentJob` → transcript/description → discovery turn
- **Company portal:** `/company/documents` — upload PDFs, `ParseDocumentJob` chunks + embeds (pgvector) + insights preview
- MinIO object storage for media and documents
- Report readiness includes **multimodal** dimension (15% weight)

### Test voice note (dev, no Meta)

```bash
docker compose exec rails bundle exec rails multimodal:simulate_voice PHONE=+14155559999
```

Requires employee in `discovery` status (complete onboarding first).

## Phase 3 (implemented) — LangGraph discovery

- **LangGraph agent** (`agent/`, port 8000): adaptive interview turns, per-turn insight extraction
- **Mock mode** when `OPENAI_API_KEY` is unset — cycles through department questions in the employee's language
- Rails `Discovery::ProcessTurnService` orchestrates turns; `Whatsapp::DiscoveryHandler` sends replies
- DB-backed **discovery playbooks** — Platform portal `/platform/playbooks` (create version, activate)
- Internal API: `GET /api/v1/internal/playbooks/active?department=operations`
- **Circuit breaker** (Redis `openai:circuit_open`) + `RetryDiscoveryTurnJob` (30s → 2m → 8m)
- `conversation_insights` table stores per-turn summaries
- Session expiry via `MarkAbandonedConversationsJob`

### Test discovery locally

```bash
docker compose up --build
docker compose run --rm rails bundle exec rails db:migrate

# After onboarding an employee (whatsapp:simulate flow):
docker compose run --rm rails bundle exec rails discovery:turn PHONE=+14155559999 TEXT="I manage vendor invoices in SAP"
```

Set `OPENAI_API_KEY` in `docker-compose.yml` or `.env` for real LLM questions.

## Phase 2 (implemented) — WhatsApp

- Meta webhook (`GET/POST /api/v1/webhooks/whatsapp`) with signature verification
- Employee onboarding via WhatsApp: name → company (optional if invited) → access code → consent → verified
- Per-employee access codes (never sent in template body)
- `SendEmployeeInvitationJob` + `SendEmployeeNudgeJob` (24h cooldown)
- `NotificationService` + email via Mailpit
- Language detection on consent message (en/es/fr/de heuristics)
- Local simulation: `docker compose run --rm rails bundle exec rails whatsapp:simulate PHONE=+15551234567 TEXT="Hola"`

### Meta setup

1. Create Meta App → WhatsApp → set webhook URL to `https://<tunnel>/api/v1/webhooks/whatsapp`
2. Verify token must match `META_VERIFY_TOKEN`
3. Register templates: `employee_discovery_invite`, `employee_discovery_nudge`
4. Set env vars in `backend/.env` (see `.env.example`)

Without Meta credentials, invites log to Rails console and `whatsapp:simulate` works for full onboarding flow testing.

## Phase 1 (implemented)

- Dual JWT auth (`platform` / `company` audiences)
- Platform: company CRUD, trial extension, audit logs
- Company: onboarding wizard (profile → invite → instructions)
- Per-employee access codes on invite
- Company intelligence dashboard shell

## Project structure

```
req_app/
├── agent/            # LangGraph FastAPI service
├── backend/          # Rails API
├── frontend/         # React portals
├── docker-compose.yml
└── README.md
```

## API namespaces

- `POST /api/v1/auth/platform/login`
- `POST /api/v1/auth/company/login`
- `GET  /api/v1/platform/companies`
- `GET  /api/v1/company/me`
- `GET  /api/v1/company/onboarding`

See the architecture plan in `.cursor/plans/` for Phases 2–7 (WhatsApp, LangGraph, intelligence, reports).
