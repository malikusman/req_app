# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

**Worktruth** — an AI-powered enterprise workflow-discovery platform. Companies get onboarded and interviewed (via WhatsApp and/or a web questionnaire) about their internal workflows/systems; the platform ingests documents and interview data, and produces reports. Three audiences/portals: **platform** (internal ops), **company** (tenant/customer), **reviewer** (expert reviewers who QA reports).

## Stack

- **Backend**: Rails 7.1 / Ruby 3.1.2 API app, PostgreSQL (pgvector), Sidekiq for background jobs, JWT auth. Run via Docker Compose.
- **Frontend**: React 18 + TypeScript + Vite + Tailwind, in `frontend/`, run via Docker Compose.
- **Agent service**: LangGraph + FastAPI (Python) in `agent/`, port 8000 — drives the AI interview/discovery agent. Not explored in depth; treat as a separate service boundary.
- **Supporting services** (see root `docker-compose.yml`): Redis, MinIO (S3-compatible storage), Mailpit (dev email capture), Gotenberg (PDF generation).
- **Dev environment**: `docker compose up -d` for services (first-time setup: `docker compose run --rm rails bundle exec rails db:migrate db:seed`). Backend commands run via `docker compose run --rm --no-deps rails bash -lc "..."`. Frontend via `docker compose run --rm --no-deps frontend sh -c "..."`.
- No bundler/ruby/npm on the host — everything runs through the containers.
- Known gotcha: `stripe` gem sometimes missing on first boot — restart the rails container or run `bundle install` inside it, don't change code for this.

## Commands

### Backend (Rails) — via `docker compose run --rm --no-deps rails bash -lc "<cmd>"`

- Full test suite: `bundle exec rspec`
- Single file: `bundle exec rspec spec/requests/api/v1/company/onboarding_spec.rb`
- Single example by line: `bundle exec rspec spec/path/to/spec.rb:42`
- Migrations: `bundle exec rails db:migrate`
- Seed: `bundle exec rails db:seed`
- Console: `bundle exec rails console`
- Server (normally started via `docker compose up`, not run manually): `bundle exec rails server`
- **No Ruby linter is configured** (no `rubocop` gem, no `.rubocop.yml`) — don't invent a lint command for the backend.

### Frontend — via `docker compose run --rm --no-deps frontend sh -c "<cmd>"`

- Dev server: `npm run dev`
- Build (includes typecheck via `tsc -b`): `npm run build`
- Lint: `npm run lint`
- Standalone typecheck only: `npx tsc -b --noEmit`
- **No test framework is configured** (no test script, no Jest/Vitest deps, no test files under `src/`) — don't invent a test command for the frontend.

CI (`.github/workflows/ci.yml`) mirrors these: backend job runs `db:create db:schema:load` then `bundle exec rspec`; frontend job runs `npm ci`, `npm run lint`, `npx vite build`.

## Architecture

### Backend (`backend/app/`)

- Controllers are namespaced by audience: `api/v1/{platform,company,reviewer,public,internal,webhooks}/...`. `public` is unauthenticated/token-based (reports, discover sessions, registrations).
- Business logic lives in namespaced service objects under `app/services/` (PORO pattern, not fat models/controllers) — e.g. `Companies::`, `Discovery::`, `Whatsapp::`, `Documents::`, `Intelligence::`, `Reports::`, `Reviewers::`, `Outreaches::`, `Billing::`, `Registrations::`, `MarketIntel::`, `Multimodal::`.
- Authorization via Pundit policies in `app/policies/`.
- **Auth**: JWT with an `aud` claim (`platform`/`company`/`reviewer`) issued by a `JsonWebToken` service. Per-namespace controller concerns (`app/controllers/concerns/{company,platform,reviewer}_authenticatable.rb`) decode the token, check `aud`, and load the current actor by `sub`+`jti` (supports revocation). `company_authenticatable.rb` additionally enforces an active subscription and supports platform-as-company impersonation sessions.
- **Multi-tenancy**: `Company` is the tenant root (`companies` table); most domain tables (`company_users`, `employees`, `documents`, `conversations`, `reports`, `company_systems`, ...) are scoped by `company_id`. `CompanyUser` is a distinct login identity from `PlatformUser` and `ReviewerUser`.
- Onboarding-questionnaire domain specifics are covered in the "Current work" section below — that's the actively-changing part of this backend right now.

### Frontend (`frontend/src/`)

- `App.tsx` is the route root (React Router v7, classic `<BrowserRouter>`/`<Routes>` API, not the data-router API), with portal guard components (e.g. `PlatformGuard`) wrapping protected routes.
- `portals/{platform,company,reviewer,public,shared}/` — role-specific screens (e.g. `portals/company/CompanyOnboarding.tsx`).
- `auth/` — login/signup; `marketing/` — public marketing site; `employee/` — employee-facing discovery chat; `components/{ui,shadcn,layout,motion}/` — shared UI (shadcn/Radix-based); `dev/` — internal UI showcase.
- **State**: no Redux/Zustand. Auth/session is a plain React Context (`lib/auth.tsx`, a `Session` discriminated union over platform/company/reviewer, persisted to `localStorage`). Server state uses TanStack React Query.
- **API client**: hand-rolled fetch wrapper (`lib/api.ts`) — prefixes `VITE_API_URL`, attaches a Bearer token, exposes a flat `api.*` object of typed methods. No axios.

## Current work: Onboarding questionnaire v2 rebuild

Branch: `feature/onboarding-questionnaire-v2` (pushed to origin — **other work may be happening on this app in parallel, keep diffs contained**).

**Authoritative spec**: `docs/questionnaire-v2-field-mapping.md`. Section 6 is the field-by-field build target for all 45 v2 fields. Read it before touching questionnaire content.

**What's done and verified** (do not redo, do not "improve" without being asked):
- `companies.questionnaire_version` column (default 1). v1 and v2 companies coexist; v1 behaviour must always stay byte-identical.
- Backend v2 field registry: `Companies::QuestionnaireV2Config` (`backend/app/services/companies/questionnaire_v2_config.rb`) — 45 keys, step, tier.
- Version-aware onboarding controller: whitelist, step clamp (1..10 v1 / 1..8 v2), completion via `Companies::QuestionnaireV2Progress` for v2, `Companies::QuestionnaireProgress` for v1 (dispatched through `call_for_company`).
- Frontend v2 config: `frontend/src/lib/questionnaireV2Config.ts` — all 8 steps, all 45 fields, audited against Section 6 with zero content mismatches.
- Scroll/focus on section change (both v1 and v2).
- Cross-check spec: `backend/spec/services/companies/questionnaire_v2_frontend_keys_spec.rb` — asserts frontend config keys exactly match the backend registry. Keep this passing; if it fails, that's a real drift, not a spec to "fix."

**Not built yet**: autosave, "Step X of 8" progress display, tier indicators, tier-based completion counting, advanced field-type components (chip-select, matrix, per-item numeric, etc. — currently on Stage-2 placeholders per Section 7 of the spec), `_other` sidecar text capture, screen-based pagination within multi-screen steps, the profile fields (name/phone/website) above the questionnaire.

## Test accounts (dev only)

- `admin@acme.local` / `password123` — company `acme-corp`, **version 1**. The v1 regression control — always verify this still works exactly as before any questionnaire change.
- `admin@beta.local` / `password123` — company `beta-industries`, **version 2**.
- Seeded trials expire against the system clock. If login fails with "Subscription inactive", extend `trial_ends_at` via `bin/rails runner` — never change code for this.
- Additional seeded platform/reviewer/company accounts (all `password123`) exist beyond the two above — see root `README.md` for the full list.

## Conventions for this branch

- **Read-only investigation vs. implementation are different modes.** Some sessions are explicitly investigation-only (no file writes). Follow whatever the task prompt says.
- **Propose a plan before writing code** for any non-trivial task. Wait for confirmation.
- **One logical change per commit.** Verify (backend suite + frontend build) between commits, not just at the end.
- **Never amend, rebase, or squash existing commits** unless explicitly told to. New commits only.
- **Never push** unless explicitly told to.
- **Never touch `docker-compose.yml` or other infra config** without flagging it first — one prior session needed a mount change and asked before making it.
- If any command output looks duplicated, truncated, or inconsistent with a prior read, **stop and say so** rather than acting on it — this has caused real errors before in this project. Prefer `node -e "..."` reading explicit line ranges for large files if shell tools misbehave.
- Do not fabricate question wording, option text, or any content not present in `docs/questionnaire-v2-field-mapping.md`. If something needed isn't in that doc, stop and ask.
</content>
