# Worktruth — Production Readiness & Roadmap Plan

> **Status:** Planning document. Nothing here is implemented yet.
> **Audience:** An implementing agent (Cursor) or engineer. Every item is written to be actioned directly.
> **Repo:** `req_app` (brand: **Worktruth**). Rails 7 API + React/Vite/TS frontend + Python LangGraph agent, Docker.
> **Base branch for this doc:** `production-readiness-plan` (cut from `report-update`).
> **Created:** July 2026, from a full read-only audit of `report-update`.

---

## 0. How to use this document

This file is the single source of truth for getting Worktruth to production and closing the product gaps found in review. It is split into:

- **Part A — Production blockers & hardening** (must-fix engineering / security / ops).
- **Part B — Product feature work** (the five product concerns from stakeholder feedback).
- **Part C — Sequencing, milestones, and definition of done.**
- **Appendices** — env-var matrix, file map, testing conventions.

### Conventions used in every work item

Each item follows the same structure so it can be picked up independently:

- **ID** — stable reference (e.g. `BLK-1`, `HIGH-3`, `FEAT-ADDMORE`).
- **Severity / Type.**
- **Problem** — what is wrong today.
- **Evidence** — `path:line` pointers verified against the current tree.
- **Why it matters** — user/business/security impact.
- **Implementation** — concrete, step-by-step, with code sketches. Sketches are illustrative, not copy-paste final; follow existing code style.
- **Acceptance criteria** — how to know it's done.
- **Tests** — what to add.

### Ground rules for the implementer

1. **Do not weaken multi-tenant isolation.** The Pundit scopes (`policy_scope`, `company_scope`, `find_assigned_company!`) and strong params are the app's strongest asset. Every new endpoint must go through them.
2. **Mocks are never allowed to fabricate business data in production.** `MocksAllowed.allowed?` ([backend/app/services/mocks_allowed.rb](backend/app/services/mocks_allowed.rb)) is the only gate that may return canned/mock content. Any `rescue` that returns mock data must check it first.
3. **Every new service gets a spec.** The audit found many new services with zero coverage. New code must not extend that debt.
4. **Backend runs green:** `docker exec req_app-rails-1 bundle exec rspec` must stay at 0 failures. Frontend must pass `npm run build` and `npm run lint` (0 errors).
5. Keep the **Pulse design tokens** (green `#0E9F6E`, Sora/Manrope, pill components, `--chart-1..6`). No hardcoded hexes.

---

# PART A — PRODUCTION BLOCKERS & HARDENING

Severity legend: **BLOCKER** (no production traffic until fixed) · **HIGH** (fix in first hardening sprint) · **MEDIUM** (before scaling / first paying cohort) · **LOW** (backlog).

## Summary table

| ID | Sev | Title | Status |
|----|-----|-------|--------|
| BLK-1 | BLOCKER | OCR fabricates fake business data on OpenAI failure | Done |
| BLK-2 | BLOCKER | No database backups | |
| BLK-3 | BLOCKER | PII stored in plaintext (no encryption at rest) | |
| BLK-4 | BLOCKER | No error tracking in any runtime | Deferred — LangSmith for agent (easy-wins track) |
| BLK-5 | BLOCKER | Stripe webhook fails open; mock checkout wired into prod | Done |
| BLK-6 | BLOCKER | pgvector has no ANN index (full scans on hot path) | |
| HIGH-1 | HIGH | No rate limiting / brute-force protection | |
| HIGH-2 | HIGH | `Rails.cache` is per-container file store (no shared Redis cache) | Done |
| HIGH-3 | HIGH | Internal API auth falls back to a public default token | Done |
| HIGH-4 | HIGH | External calls lack connect timeouts on a single shared queue | |
| HIGH-5 | HIGH | WhatsApp dedup permanently drops messages on transient failure | |
| HIGH-6 | HIGH | MarketIntel matching is O(employees×candidates) with N+1 | |
| HIGH-7 | HIGH | N+1s and missing indexes on hot columns | |
| HIGH-8 | HIGH | No log aggregation; health check too shallow | |
| HIGH-9 | HIGH | No data retention enforcement, erasure, or export (GDPR) | |
| HIGH-10 | HIGH | PII not filtered from logs | |
| HIGH-11 | HIGH | No frontend tests, no coverage gate, no rubocop in CI | |
| HIGH-12 | HIGH | Deploy has no rollback / backup-before-migrate; MinIO unreplicated | |
| MED-1..9 | MEDIUM | See Part A §Medium | |
| LOW-1..5 | LOW | See Part A §Low | |

---

## BLOCKER items

### BLK-1 — OCR fabricates fake business data on OpenAI failure

- **Severity/Type:** BLOCKER / data integrity.
- **Problem:** `Openai::Client#ocr_scanned_pdf` and `#ocr_image` `rescue StandardError` and return hardcoded mock text **without checking whether mocks are allowed**. During a real OpenAI outage or 429, fabricated content (e.g. `mock_image_ocr_text`) is stored as the document's `extracted_text`, then flows into interviews, intelligence, and the client-facing PDF as if it were genuine business data.
- **Evidence:**
  - [backend/app/services/openai/client.rb:176](backend/app/services/openai/client.rb#L176) — `rescue StandardError` → `mock_scanned_pdf_text(language)`.
  - [backend/app/services/openai/client.rb:210-213](backend/app/services/openai/client.rb#L210) — `ocr_image` rescue chain ends in `mock_image_ocr_text(language)`.
  - The top-of-method `return mock_* unless configured?` guard is correct (that's the "no key" case). The bug is the **rescue on a live call**.
  - Downstream: [backend/app/services/multimodal/ocr_fallback.rb](backend/app/services/multimodal/ocr_fallback.rb) already rescues to `""`, and [backend/app/services/multimodal/parse_document_service.rb](backend/app/services/multimodal/parse_document_service.rb) already marks a doc `failed` with `image_ocr_unavailable` when text is empty. So the correct behavior is: on a live-call error, **raise** (or return `""`) instead of fabricating.
- **Why it matters:** Silent fabrication of client evidence is the single most dangerous behavior in the app. A consulting report citing invented invoice figures destroys trust and creates liability.
- **Implementation:**
  1. In both `ocr_scanned_pdf` and `ocr_image`, change the rescue so it only returns mock text when `MocksAllowed.allowed?`; otherwise re-raise so `OcrFallback` converts it to an empty result and the document is cleanly marked `failed`.
     ```ruby
     # ocr_scanned_pdf
     rescue StandardError => e
       raise unless MocksAllowed.allowed?
       Rails.logger.warn("[OCR] scanned_pdf fell back to mock: #{e.class}: #{e.message}")
       mock_scanned_pdf_text(language)
     end
     ```
     ```ruby
     # ocr_image — keep the structured-understanding fallback, but gate the final mock
     rescue StandardError => e
       begin
         structured = understand_image_structured(file_path: file_path, caption: nil, language: language)
         flatten_image_insights_to_text(structured)
       rescue StandardError => inner
         raise inner unless MocksAllowed.allowed?
         Rails.logger.warn("[OCR] image fell back to mock: #{inner.class}")
         mock_image_ocr_text(language)
       end
     end
     ```
  2. **Audit every other `rescue` in `openai/client.rb`** for the same pattern. The structured-image, embeddings, and chat methods must also raise (not mock) in production. Grep: `grep -n "mock_" backend/app/services/openai/client.rb` and confirm each mock call is reachable only when `!configured?` or `MocksAllowed.allowed?`.
  3. Confirm `ParseDocumentService` marks the document `failed` with a user-visible reason when extraction returns empty (it does today — verify the message surfaces in the company Documents UI so the admin knows to re-upload).
- **Acceptance criteria:**
  - With `OPENAI_API_KEY` set and the OpenAI call stubbed to raise (500/timeout), uploading an image results in a document with status `failed` and reason `image_ocr_unavailable` — **never** fabricated `extracted_text`.
  - With no key and `ALLOW_MOCKS=1` (dev), mock text is still returned (dev ergonomics preserved).
- **Tests:** Extend [backend/spec/services/multimodal/ocr_fallback_spec.rb](backend/spec/services/multimodal/ocr_fallback_spec.rb) and add an `openai/client` spec: stub `post_json` to raise, assert it re-raises when mocks disallowed and returns mock when allowed.

---

### BLK-2 — No database backups

- **Severity/Type:** BLOCKER / durability.
- **Problem:** Postgres runs in a single Docker volume `pg_data` on one DigitalOcean host. There is no `pg_dump`, no point-in-time recovery, no offsite copy. A bad migration, disk failure, or `docker volume rm` is unrecoverable.
- **Evidence:** [docker-compose.prod.yml](docker-compose.prod.yml) `pg_data` volume; [scripts/deploy/deploy.sh](scripts/deploy/deploy.sh) runs `db:prepare` on every deploy with no pre-backup; repo grep for `pg_dump`/`wal`/`barman`/`pgbackrest` returns nothing.
- **Why it matters:** One irreversible event wipes all customer data. Table stakes for any paid product.
- **Implementation (pick 2a for speed, plan 2b for later):**
  - **2a — Scheduled logical backups to object storage (DO Spaces / S3).** You already run MinIO (S3-compatible) — provision a **separate, off-host** bucket for backups (do NOT reuse the app's MinIO volume, which is itself unbacked-up).
    1. Add `scripts/deploy/backup.sh`:
       ```bash
       #!/usr/bin/env bash
       set -euo pipefail
       STAMP=$(date -u +%Y%m%dT%H%M%SZ)
       FILE="/tmp/req_app_${STAMP}.sql.gz"
       docker exec req_app-postgres-1 pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" | gzip > "$FILE"
       aws s3 cp "$FILE" "s3://$BACKUP_BUCKET/postgres/${STAMP}.sql.gz" --endpoint-url "$BACKUP_S3_ENDPOINT"
       rm -f "$FILE"
       # retention: delete backups older than 30 days
       ```
    2. Schedule via **host cron / systemd timer** (not Sidekiq — backups must survive an app crash): every 6h + daily. Add to `scripts/deploy/bootstrap-server.sh`.
    3. **Backup MinIO too:** either `mc mirror` the `minio_data` bucket to the backup bucket on the same schedule, or migrate uploads to managed Spaces with versioning (preferred long-term).
  - **2b — Managed Postgres (recommended target).** Move to DigitalOcean Managed Postgres (daily backups + PITR + failover built in). Update `DATABASE_URL` in `.env.production`; remove the `postgres` service from `docker-compose.prod.yml`. This removes the whole class of problem and is the real production answer.
  - **Write `docs/ops/restore-runbook.md`** with the exact restore commands and **run a restore test** into a scratch DB. A backup you haven't restored is not a backup.
- **Acceptance criteria:** Automated backups land in an off-host bucket on schedule with 30-day retention; a documented, **tested** restore procedure exists; `deploy.sh` takes a pre-migration dump (see HIGH-12).
- **Tests:** Ops verification (manual restore into scratch DB documented in the runbook).

---

### BLK-3 — PII stored in plaintext (no encryption at rest)

- **Severity/Type:** BLOCKER / privacy & compliance.
- **Problem:** No model uses `ActiveRecord::Encryption`. Phone numbers, all message bodies/transcripts, and WhatsApp identifiers are plaintext columns on an unencrypted, unbacked-up volume. Given the EU/enterprise positioning, this is a serious GDPR exposure.
- **Evidence:** `db/schema.rb` — phone columns (`employees.phone_number` and access-code/session tables), message bodies (`messages.body`, conversation/insight transcript columns), WhatsApp ids. No `encrypts` anywhere (`grep -rn "encrypts" backend/app/models` → empty).
- **Why it matters:** A DB/volume leak exposes named individuals + verbatim workplace complaints. Regulatory and reputational catastrophe.
- **Implementation:**
  1. **Set up ActiveRecord Encryption keys.** Generate `bin/rails db:encryption:init` and store `active_record_encryption.primary_key`, `deterministic_key`, `key_derivation_salt` in Rails **credentials** (or env for the container). Add to `.env.production.example` and the env matrix (Appendix A).
  2. **Encrypt columns.** Note the **deterministic vs non-deterministic** distinction — phone numbers must be **deterministic** because the WhatsApp inbound path looks employees up by phone:
     ```ruby
     # app/models/employee.rb
     encrypts :phone_number, deterministic: true   # equality lookups still work
     # app/models/message.rb
     encrypts :body                                # non-deterministic (never queried by value)
     # transcripts / insight bodies, whatsapp ids similarly
     ```
     Inventory every column first: `grep -niE "phone|body|transcript|wa_id|whatsapp_id" backend/db/schema.rb` and encrypt each PII/transcript column. Deterministic only where equality queries exist (phone, wa_id); non-deterministic elsewhere.
  3. **Backfill existing rows.** Encryption is transparent for new writes but existing plaintext must be re-saved. Write a one-off task `lib/tasks/encrypt_pii.rake` that iterates in batches and `update_column`-rewrites through the model so values get encrypted. Run once per environment; document in the restore runbook.
  4. **Phone normalization must happen before encryption** so deterministic lookups match — verify [backend/app/services/phone_normalizer.rb](backend/app/services/phone_normalizer.rb) output is what's stored and queried.
  5. **`support_unencrypted_data`** — set `true` during rollout so reads don't break before the backfill completes, then flip to `false`.
- **Acceptance criteria:** New phone/message/transcript rows are ciphertext in the DB (verify with raw SQL `SELECT`); WhatsApp inbound still resolves employees by phone; existing rows backfilled; `support_unencrypted_data = false` after backfill.
- **Tests:** Model specs asserting `Employee.find_by(phone_number:)` still works and that `Employee.connection.select_value("SELECT phone_number FROM employees LIMIT 1")` is not plaintext.

---

### BLK-4 — No error tracking in any runtime

- **Severity/Type:** BLOCKER / observability.
- **Problem:** No Sentry/Rollbar/Honeybadger/Bugsnag/AppSignal in Rails, Sidekiq, React, or the Python agent. Production errors go only to STDOUT (which is itself not aggregated — see HIGH-8). You will be blind to failures.
- **Evidence:** No exception-tracker gem in `backend/Gemfile`; no `@sentry/*` in `frontend/package.json`; no `sentry_sdk` in `agent/` requirements.
- **Implementation (Sentry recommended — one vendor across all four runtimes):**
  1. **Rails + Sidekiq:** add `sentry-ruby`, `sentry-rails`, `sentry-sidekiq`. Initializer `config/initializers/sentry.rb` with `dsn: ENV["SENTRY_DSN"]`, `traces_sample_rate: 0.1`, `environment: Rails.env`, and **`config.before_send`** to scrub PII (phone, body — reuse the filter list from HIGH-10).
  2. **React:** add `@sentry/react`, init in [frontend/src/main.tsx](frontend/src/main.tsx) with `VITE_SENTRY_DSN`, `tracesSampleRate`, and a router integration; wrap the app in an error boundary.
  3. **Python agent:** add `sentry-sdk`, init in [agent/app/main.py](agent/app/main.py) at startup with `SENTRY_DSN`.
  4. Add all three DSNs to the env matrix. Sample rates conservative (0.1) to control cost.
- **Acceptance criteria:** A deliberately raised error in each runtime appears in Sentry with environment tag and **no PII in the payload**.
- **Tests:** Manual smoke (trigger a test error per runtime); assert `before_send` scrubbing with a unit test on the Rails side.

---

### BLK-5 — Stripe webhook fails open; mock checkout wired into prod

- **Severity/Type:** BLOCKER / security & billing integrity.
- **Problem:** If `STRIPE_WEBHOOK_SECRET` is blank, `parse_event` falls through to `JSON.parse(payload)` with **no signature verification** — anyone can POST forged billing events (activate plans, extend trials). The secret is **absent from every env template**, so it is almost certainly unset in prod. Separately, a `GET /api/v1/billing/mock_checkout` that activates paid plans is routed in production.
- **Evidence:**
  - [backend/app/controllers/api/v1/webhooks/stripe_controller.rb:23-26](backend/app/controllers/api/v1/webhooks/stripe_controller.rb#L23) — `if ENV["STRIPE_WEBHOOK_SECRET"].present? ... else JSON.parse(payload)`.
  - `STRIPE_WEBHOOK_SECRET` not in `.env.example` or `deploy/.env.production.example`.
  - Mock checkout: [backend/config/routes.rb](backend/config/routes.rb) (`billing/mock_checkout`), [backend/app/controllers/api/v1/billing/mock_checkout_controller.rb](backend/app/controllers/api/v1/billing/mock_checkout_controller.rb).
- **Why it matters:** Forgeable billing = revenue integrity hole and a trivial privilege path (activate your own trial to paid, bypass access gating).
- **Implementation:**
  1. **Fail closed.** In production, a missing secret must reject, not bypass:
     ```ruby
     def parse_event(payload)
       secret = ENV["STRIPE_WEBHOOK_SECRET"]
       if secret.blank?
         raise "STRIPE_WEBHOOK_SECRET missing" if Rails.env.production?
         return JSON.parse(payload) if MocksAllowed.allowed?  # dev only
         return nil
       end
       require "stripe"
       Stripe::Webhook.construct_event(payload, request.env["HTTP_STRIPE_SIGNATURE"], secret).to_hash
     rescue JSON::ParserError, Stripe::SignatureVerificationError => e
       Rails.logger.warn("[Stripe webhook] #{e.message}")
       nil
     end
     ```
  2. Add `STRIPE_WEBHOOK_SECRET` (and `STRIPE_SECRET_KEY`, `STRIPE_PRICE_*`) to `.env.example`, `deploy/.env.production.example`, and the env matrix.
  3. **Gate mock checkout out of production.** Wrap the route in `unless Rails.env.production?` or guard the controller with `head :not_found unless MocksAllowed.allowed?`. Confirm the real Stripe checkout path ([backend/app/services/billing/checkout_service.rb](backend/app/services/billing/checkout_service.rb)) is the only live path in prod.
  4. Add a production **boot check** (initializer) that raises if `STRIPE_WEBHOOK_SECRET` is blank when Stripe is enabled — fail fast at deploy, not at first webhook.
- **Acceptance criteria:** In prod config, a webhook with a bad/missing signature returns 400 and does nothing; mock checkout returns 404 in prod; app refuses to boot in prod without the secret when billing is on.
- **Tests:** Request spec: forged payload without valid signature → 400, no subscription change. Add specs for `Billing::StripeWebhookHandler` and `CheckoutService` (currently untested).

---

### BLK-6 — pgvector has no ANN index (full scans on hot path)

- **Severity/Type:** BLOCKER at scale / performance.
- **Problem:** The `vector(1536)` columns have no ivfflat/hnsw index, so `nearest_neighbors` does a sequential scan. This runs **per inbound WhatsApp message** during discovery. The catalog matcher loads all rows and computes cosine in Ruby.
- **Evidence:** `db/schema.rb` — `company_memory_facts.embedding`, `document_chunks.embedding`, `solution_catalog.embedding` (no vector index). [backend/app/services/discovery/context_builder.rb:76](backend/app/services/discovery/context_builder.rb#L76) and `:115` call `nearest_neighbors` per turn. [backend/app/services/catalog/hybrid_matcher.rb:20](backend/app/services/catalog/hybrid_matcher.rb#L20) loads all catalog rows.
- **Why it matters:** Fine for a 3-company demo; at a few hundred companies × thousands of facts, discovery latency (already on a synchronous WhatsApp path) degrades badly.
- **Implementation:**
  1. Add **HNSW cosine** indexes via migration (the `neighbor` gem supports this). Use `algorithm: :concurrently` inside `disable_ddl_transaction!` (see MED-6):
     ```ruby
     disable_ddl_transaction!
     def change
       add_index :company_memory_facts, :embedding, using: :hnsw, opclass: :vector_cosine_ops, algorithm: :concurrently
       add_index :document_chunks,       :embedding, using: :hnsw, opclass: :vector_cosine_ops, algorithm: :concurrently
       add_index :solution_catalog,      :embedding, using: :hnsw, opclass: :vector_cosine_ops, algorithm: :concurrently
     end
     ```
  2. Push the catalog cosine into SQL (use `neighbor`'s `nearest_neighbors` on the scope instead of loading all rows into Ruby) in `hybrid_matcher.rb`.
  3. Add a **similarity threshold** to memory retrieval so irrelevant nearest-neighbors aren't injected (ties into agent quality, FEAT-AGENTS).
- **Acceptance criteria:** `EXPLAIN` shows index usage on the three vector queries; catalog matching no longer loads the full table.
- **Tests:** Existing `hybrid_matcher`/`context_builder` specs stay green; add a spec asserting the catalog matcher scopes the query (doesn't `.all`).

---

## HIGH items

### HIGH-1 — No rate limiting / brute-force protection

- **Problem:** `rack-attack` is not installed; all three login endpoints do plain `find_by` + `authenticate` with no lockout. Credential stuffing is unmitigated.
- **Evidence:** [backend/app/controllers/api/v1/auth/company_sessions_controller.rb:8](backend/app/controllers/api/v1/auth/company_sessions_controller.rb#L8), `reviewer_sessions_controller.rb:8`, `platform_sessions_controller.rb:8`. No `rack-attack` in Gemfile.
- **Implementation:**
  1. Add `rack-attack`; `config/initializers/rack_attack.rb`. Backed by the Redis cache store (**depends on HIGH-2**).
  2. Throttles: login by IP (e.g. 10/min) and by email (5/20min); `/api/v1/public/discover/**/verify` by IP + token; `/api/v1/public/demo_requests` (already app-limited, move to rack-attack); a global fallback throttle. Exponential backoff / temporary lockout on repeated login failures.
  3. Return 429 with `Retry-After`; ensure the frontend login form surfaces it.
- **Acceptance:** Repeated bad logins get 429; verified in a request spec.
- **Tests:** Request spec hitting the login throttle.

### HIGH-2 — `Rails.cache` is a per-container file store

- **Problem:** `config.cache_store` is commented out in production, so `Rails.cache` defaults to a per-container file store. The hand-rolled rate limits (access-code verify, demo requests) and mock-checkout tokens are therefore **not shared** between the `rails` and `sidekiq` containers and are wiped on redeploy. rack-attack (HIGH-1) also needs a shared store.
- **Evidence:** [backend/config/environments/production.rb:66](backend/config/environments/production.rb#L66) (commented `cache_store`). Uses of `Rails.cache`: [backend/app/services/employee_web_sessions/verify_service.rb:52](backend/app/services/employee_web_sessions/verify_service.rb#L52), [backend/app/controllers/api/v1/public/demo_requests_controller.rb:34](backend/app/controllers/api/v1/public/demo_requests_controller.rb#L34).
- **Implementation:** `config.cache_store = :redis_cache_store, { url: ENV["REDIS_URL"], namespace: "cache" }`. Ensure `REDIS_URL` is set for both containers. Keep Sidekiq on its own Redis DB or namespace to avoid `FLUSHDB` collisions.
- **Acceptance:** Rate-limit counters persist across a redeploy and are consistent between containers.

### HIGH-3 — Internal API auth falls back to a public default token

- **Problem:** `ENV.fetch("INTERNAL_API_TOKEN", "dev-internal-token")` — if unset in prod, the entire internal namespace is "protected" by a known string.
- **Evidence:** [backend/app/controllers/concerns/internal_authenticatable.rb:14](backend/app/controllers/concerns/internal_authenticatable.rb#L14).
- **Implementation:** Remove the default. Raise on boot in production if `INTERNAL_API_TOKEN` is blank. Compare with `ActiveSupport::SecurityUtils.secure_compare`.
- **Acceptance:** App refuses to boot in prod without the token; internal endpoints reject a wrong token with constant-time compare.

### HIGH-4 — External calls lack connect timeouts on a single shared queue

- **Problem:** Sidekiq is one `default` queue at concurrency 5. OpenAI/Gotenberg have only read timeouts; **WhatsApp MetaClient and media fetch have no timeouts at all**. A few hung sockets starve every job. No `retry_on`/`Retry-After` handling for 429s.
- **Evidence:** [backend/config/sidekiq.yml:1](backend/config/sidekiq.yml#L1); [backend/app/services/whatsapp/meta_client.rb:118](backend/app/services/whatsapp/meta_client.rb#L118); [backend/app/services/whatsapp/meta_media_fetcher.rb:46](backend/app/services/whatsapp/meta_media_fetcher.rb#L46); [backend/app/services/openai/client.rb](backend/app/services/openai/client.rb) (read_timeout 120s, no open_timeout); [backend/app/services/reports/pdf_generator.rb:25](backend/app/services/reports/pdf_generator.rb#L25).
- **Implementation:**
  1. Set `open_timeout` (5s) and sane `read_timeout` on **every** `Net::HTTP` client: OpenAI, Gotenberg, MetaClient, MetaMediaFetcher, Langgraph client (already has them).
  2. Split Sidekiq queues by risk/latency: `critical` (webhooks, discovery turns), `default`, `low` (market intel, catalog sync, digests). Give the slow/bulk jobs their own queue so they can't starve inbound processing. Bump concurrency and add a `sidekiq.yml` queue weight config.
  3. Add `sidekiq_options retry:` tuning and, for OpenAI 429s, honor `Retry-After` (raise a typed error → `retry_on` with backoff).
- **Acceptance:** A hung external host times out in ≤ its configured limit; bulk jobs run on a separate queue; load test shows inbound discovery unaffected by a slow market-intel run.

### HIGH-5 — WhatsApp dedup permanently drops messages on transient failure

- **Problem:** Inbound processing early-returns if a `WebhookEvent` with the `wamid` exists. On failure it persists the event as `failed` **and re-raises**; the Sidekiq retry then hits the existence guard and skips reprocessing — the user's message is lost forever.
- **Evidence:** [backend/app/services/whatsapp/inbound_processor.rb:29](backend/app/services/whatsapp/inbound_processor.rb#L29) (existence guard), `:57-58` (persist failed + re-raise).
- **Implementation:** Gate on **successful processing**, not mere existence. Skip only if a `WebhookEvent` for the `wamid` is in a terminal `processed` state; if it exists but is `failed`/`pending`, allow reprocessing (idempotently). Add a `status` column/scope on `WebhookEvent` if not present. Ensure the actual side effects (message create, turn) are idempotent per `wamid`.
- **Acceptance:** Simulate a transient failure on first delivery; the Sidekiq retry reprocesses and the message is captured. Spec covering "fails once then succeeds → message persisted exactly once."

### HIGH-6 — MarketIntel matching is O(employees × candidates) with N+1

- **Problem:** `match_and_notify_service` nests employees × up to 50 candidates in Ruby; `sent_count_this_month`/`exists?` run per pair, and `employee_fit_service` re-runs the same per-employee `conversation_insights` query for every candidate. Runs every 6h on the shared queue.
- **Evidence:** [backend/app/services/market_intel/match_and_notify_service.rb:17](backend/app/services/market_intel/match_and_notify_service.rb#L17); [backend/app/services/market_intel/employee_fit_service.rb:106](backend/app/services/market_intel/employee_fit_service.rb#L106).
- **Implementation:** Memoize the per-employee insight/profile blob once per employee (not per candidate). Batch the monthly-count and existence checks into grouped queries (`group(:employee_id).count`, preloaded set of existing `(employee_id, candidate_id)` pairs). Run on the `low` queue (HIGH-4). Add indexes (HIGH-7).
- **Acceptance:** Query count for a run is O(employees + candidates), not O(employees × candidates); verified via query-count assertion.
- **Tests:** Add the missing `employee_fit_service` and `send_alert_service` specs (flagged in review) plus a query-count test.

### HIGH-7 — N+1s and missing indexes on hot columns

- **Problem:** Multiple N+1s and unindexed status/token columns scanned by jobs and list endpoints.
- **Evidence:**
  - N+1: [backend/app/controllers/api/v1/company/reports_controller.rb:10](backend/app/controllers/api/v1/company/reports_controller.rb#L10) (per-report `report_share_accesses.count`/`.maximum`); [backend/app/controllers/api/v1/company/employees_controller.rb:9](backend/app/controllers/api/v1/company/employees_controller.rb#L9) (per-employee nudge lookup, no `includes`).
  - Missing indexes: `conversations.status`, `messages.processing_status`, `employees.participation_status`, `notifications.read_at`/`notification_type`, `media_attachments.status`, and `company_users.invitation_token` (**not indexed and not unique** — invite acceptance full-scans and can collide).
- **Implementation:** Preload/counter-cache the N+1s. Add indexes (concurrently — MED-6). Add a **unique** index on `company_users.invitation_token`.
- **Acceptance:** Query-count tests on the two endpoints; `EXPLAIN` shows index usage on the job scans.

### HIGH-8 — No log aggregation; health check too shallow

- **Problem:** Prod logs to STDOUT only with no shipping (lost on `down`/prune). `/up` is process-liveness only; the Sidekiq container has no healthcheck. The rich checks exist but are platform-admin-gated, unusable as external probes.
- **Evidence:** [backend/config/environments/production.rb:52](backend/config/environments/production.rb#L52); [docker-compose.prod.yml](docker-compose.prod.yml) (no logging driver, no sidekiq healthcheck); [backend/config/routes.rb:4](backend/config/routes.rb#L4) (`/up`); [backend/app/controllers/api/v1/platform/system_controller.rb:6](backend/app/controllers/api/v1/platform/system_controller.rb#L6).
- **Implementation:**
  1. Add an **unauthenticated readiness endpoint** `GET /health/ready` checking DB, Redis, and (shallow) Sidekiq — return 503 if any is down. Keep `/up` for liveness.
  2. Add a Docker healthcheck for the Sidekiq container (e.g. `bundle exec sidekiqmon` or a small ping job).
  3. Ship logs: add a logging driver in compose (json-file with rotation at minimum; ideally ship to a hosted log service). Consider `lograge` for structured request logs.
- **Acceptance:** `/health/ready` returns 503 when DB or Redis is down; logs persist across a container restart; Sidekiq container reports health.

### HIGH-9 — No data retention enforcement, erasure, or export (GDPR)

- **Problem:** `retained_until` is set on documents but nothing enforces it — no purge cron. `Documents::PurgeService` is manual and only deletes one document's file/chunks, never messages/transcripts/phone numbers. There is no company/employee deletion or data-export endpoint. GDPR erasure/SAR requires manual DB surgery.
- **Evidence:** [backend/app/controllers/api/v1/company/documents_controller.rb:52](backend/app/controllers/api/v1/company/documents_controller.rb#L52) (sets `retained_until`); [backend/app/services/documents/purge_service.rb](backend/app/services/documents/purge_service.rb); no purge job in [backend/config/sidekiq_schedule.yml](backend/config/sidekiq_schedule.yml); no `destroy` on platform companies.
- **Implementation:**
  1. **Retention cron:** daily job that purges documents past `retained_until` (files + chunks + embeddings), and optionally ages out raw transcripts per a company retention setting.
  2. **Right to erasure:** an `Employee` deletion path that removes/anonymizes the employee, their messages, media, insights, and access codes (cascade or explicit); and a `Company` off-boarding path (platform-gated) that tears down all tenant data.
  3. **Data export (SAR):** a platform/company endpoint that exports a company's or an employee's data as JSON/zip.
  4. Document retention defaults and the erasure/export process in `docs/ops/data-retention.md` and reflect it on the Privacy page.
- **Acceptance:** Expired documents are purged automatically; an employee can be fully erased via one action; a company export produces a complete archive.
- **Tests:** Service specs for the purge cron and the erasure cascade (assert no orphaned PII remains).

### HIGH-10 — PII not filtered from logs

- **Problem:** `filter_parameter_logging` filters only credential-style keys. Phone numbers, message bodies, names, and access codes can leak via param/webhook logging.
- **Evidence:** [backend/config/initializers/filter_parameter_logging.rb:6](backend/config/initializers/filter_parameter_logging.rb#L6).
- **Implementation:** Extend the filter list: `:phone_number, :phone, :body, :text, :access_code, :code, :transcript, :name, :email, :wa_id`. Reuse this list in the Sentry `before_send` scrubber (BLK-4).
- **Acceptance:** A request/webhook log line shows `[FILTERED]` for those params.

### HIGH-11 — No frontend tests, no coverage gate, no rubocop in CI

- **Problem:** Frontend CI runs only `lint` + `vite build`; no test runner in `frontend/package.json`. Backend rspec has no coverage threshold and no rubocop. Payment/webhook and most jobs (16 of 19) are untested — including `billing/stripe_webhook_handler`, `billing/checkout_service`, `platform/impersonation_service`, `reports/generate_report_service`, and the newer services flagged in review (`AgenticIdeaSynthesizer`, `CompanyStackInferrer`, `EmployeeFitService`, `SendAlertService`, `CompanyFitService`).
- **Evidence:** [.github/workflows/ci.yml:66](.github/workflows/ci.yml#L66); [frontend/package.json](frontend/package.json).
- **Implementation:**
  1. Add **Vitest + React Testing Library**; write smoke tests for the critical flows (login, employee discovery chat, reviewer report submit, company report download). Add `test` to the CI frontend job.
  2. Add **SimpleCov** with a floor (start at current %, ratchet up); fail CI below floor.
  3. Add **rubocop** (rubocop-rails) to CI.
  4. Backfill specs for the untested billing/webhook/impersonation/report/agentic/market-intel services listed above.
- **Acceptance:** CI runs backend rspec (+coverage floor +rubocop) and frontend lint+build+vitest; the listed services have specs.

### HIGH-12 — Deploy has no rollback / backup-before-migrate; MinIO unreplicated

- **Problem:** `deploy.sh` does `git reset --hard origin/main`, rebuilds in place, and runs `db:prepare` migrations with no pre-backup and no rollback; auto-triggered on any green push to main as root. Uploads live in a single unreplicated `minio_data` volume.
- **Evidence:** [scripts/deploy/deploy.sh:8](scripts/deploy/deploy.sh#L8); [.github/workflows/deploy.yml:1](.github/workflows/deploy.yml#L1).
- **Implementation:**
  1. **Backup before migrate:** call `scripts/deploy/backup.sh` (BLK-2) at the start of `deploy.sh`, before migrations.
  2. **Rollback path:** tag the previous image/commit; provide a `scripts/deploy/rollback.sh` that redeploys the last-good SHA and (if needed) restores the pre-deploy dump. Document in the runbook.
  3. **Gate auto-deploy:** require CI green **and** a manual approval (GitHub Environment protection) for the prod deploy, or deploy on tags only — not every main push.
  4. **MinIO:** mirror to the backup bucket (BLK-2) or move to managed Spaces with versioning.
- **Acceptance:** Deploy takes a dump first; a documented one-command rollback exists; prod deploy requires approval; uploads are backed up.

---

## MEDIUM items

- **MED-1 — Access-code re-auth bypasses status/expiry.** Returning employees are verified with a raw BCrypt compare that skips the `active && expires_at.future?` guard. A used/revoked/expired code still grants sessions. Also `employee_access_codes.code_digest` has no unique index. Evidence: [backend/app/services/employee_web_sessions/verify_service.rb:87](backend/app/services/employee_web_sessions/verify_service.rb#L87); [backend/app/models/employee_access_code.rb:32](backend/app/models/employee_access_code.rb#L32). Fix: apply the same `active?`/expiry guard on the returning path; add unique index.
- **MED-2 — Discover access-code rate limit is per-IP and bypassable** (nil IP shares one bucket; IP rotation resets). Evidence: `verify_service.rb:63`. Fix: key on token as well as IP; depends on HIGH-2 shared cache.
- **MED-3 — Outreach reply tokens never expire.** High-entropy but no TTL or per-token revoke. Evidence: [backend/app/controllers/api/v1/public/outreach_replies_controller.rb:44](backend/app/controllers/api/v1/public/outreach_replies_controller.rb#L44). Fix: add `expires_at` + revoke.
- **MED-4 — `force_ssl` vs plaintext origin / Cloudflare Flexible.** Caddy origin is plain `:80` and the Caddyfile permits Cloudflare Flexible, risking unencrypted CF→origin and redirect loops. Evidence: [backend/config/environments/production.rb:41](backend/config/environments/production.rb#L41); [deploy/Caddyfile:2](deploy/Caddyfile#L2). Fix: require Cloudflare **Full (strict)**, document, trust `X-Forwarded-Proto`.
- **MED-5 — Secrets are plaintext `.env.production` on host, no manager/rotation.** Evidence: [scripts/deploy/bootstrap-server.sh:40](scripts/deploy/bootstrap-server.sh#L40); `config.require_master_key` commented in `production.rb:20`. Fix: chmod 600, enable master key or a secrets manager, define rotation.
- **MED-6 — Non-concurrent index builds + a destructive dedup migration** take ACCESS EXCLUSIVE locks; fine while small, will lock in prod. Fix: use `disable_ddl_transaction!` + `algorithm: :concurrently` for all new indexes (applies to BLK-6, HIGH-7).
- **MED-7 — Silent error swallowing in catalog/market jobs** (log-and-continue; a permanently failing source is skipped every run with no alert). Evidence: [backend/app/jobs/catalog_sync_all_sources_job.rb:19](backend/app/jobs/catalog_sync_all_sources_job.rb#L19); `market_intel/match_and_notify_service.rb:43`. Fix: report to Sentry (BLK-4); add a failure counter / alert threshold.
- **MED-8 — Sidekiq boot wipes and reloads all cron** (`destroy_all!` then reload on every boot) — brief window with no schedules and a race if two Sidekiq servers boot concurrently. Evidence: [backend/config/initializers/sidekiq.rb:38](backend/config/initializers/sidekiq.rb#L38). Fix: reconcile schedule declaratively (`load_schedule!` diff) instead of destroy-all; ensure single-scheduler.
- **MED-9 — Missing notification/media indexes** (`notifications.read_at`/`notification_type`, `media_attachments.status`) scanned by unread-count and polling jobs. Fix: add indexes (folds into HIGH-7/MED-6).

## LOW items

- **LOW-1 — CORS trusts localhost in all envs.** [backend/config/initializers/cors.rb:8](backend/config/initializers/cors.rb#L8). Restrict to prod origins in production.
- **LOW-2 — JWT 24h expiry, no refresh; `JWT_SECRET` falls back to `secret_key_base`.** [backend/app/services/json_web_token.rb:6](backend/app/services/json_web_token.rb#L6). Acceptable; plan key rotation + optional refresh tokens.
- **LOW-3 — Report share tokens not individually revocable** (only expiry/overwrite). [backend/app/services/reports/share_link_service.rb:18](backend/app/services/reports/share_link_service.rb#L18). Add a revoke flag.
- **LOW-4 — Whisper empty-transcript treated as hard failure** → 25 retries re-downloading media and re-calling OpenAI. [backend/app/services/whatsapp/process_media_service.rb:44](backend/app/services/whatsapp/process_media_service.rb#L44). Treat empty transcript as a terminal, non-retried soft-fail.
- **LOW-5 — No Sidekiq Web UI mounted.** Mount `Sidekiq::Web` behind platform auth for queue visibility.

## Immediate housekeeping

- **Rotate the OpenAI key.** The dev-container `.env` contains a live `sk-proj-…` key. It is gitignored and was **never committed** (verified — no git-history leak), but it's plaintext in the working tree and exposed to local tooling. Rotate it; keep prod keys only in host `.env.production`.

---

# PART B — PRODUCT FEATURE WORK

These implement the five stakeholder concerns. They are product-facing; sequence them after the BLOCKERs but they can proceed in parallel with HIGH/MEDIUM hardening.

## FEAT-ADDMORE — Employees can always share more, even after completion

- **Type:** Core product / high priority.
- **Problem:** The 10-question target is a soft cap, but once a conversation is `completed` there is **no reopen path**, and a completed employee who sends more gets the generic closing message echoed while their content is **silently dropped as evidence** — stored as a raw message row but never turned into an insight, never added to the blackboard, never promoted to memory, and never re-aggregated.
- **Evidence:**
  - Cap/close: [backend/app/services/discovery/process_turn_service.rb:61](backend/app/services/discovery/process_turn_service.rb#L61); [agent/app/orchestrator.py:75](agent/app/orchestrator.py#L75); close node [agent/app/multi_agent_graph.py:44](agent/app/multi_agent_graph.py#L44).
  - Finalize is idempotent and never resets `onboarding_step`: [backend/app/services/discovery/finalize_conversation_service.rb:15](backend/app/services/discovery/finalize_conversation_service.rb#L15).
  - Completed convo is re-selected (only `abandoned` excluded) and routed back to discovery: [backend/app/services/whatsapp/inbound_processor.rb:88](backend/app/services/whatsapp/inbound_processor.rb#L88), `:181`; [backend/app/services/web/turn_router.rb:51](backend/app/services/web/turn_router.rb#L51).
  - Empty insight from close node → no `ConversationInsight` created: `process_turn_service.rb:113`.
- **Design — an "addendum / reopen" capability.** Two viable models; **recommend Option 1** (explicit reopen) for clarity and cost control:
  - **Option 1 — Reopen with a small budget top-up (recommended).** When a completed employee sends new content, transition `completed → discovery`, grant a bounded budget increment (e.g. `+3` questions or config `discovery_addendum_budget`), and let the normal flow run. Re-finalize at the end (make finalize non-idempotent for re-runs, or add a `finalize!(force:)` that re-enqueues aggregation/memory).
  - **Option 2 — Addendum ingestion (no reopen).** Keep status `completed` but route post-completion messages to an "addendum" path that still extracts a `ConversationInsight`, appends a blackboard `shared_findings` entry, and re-enqueues `AggregateIntelligenceJob` + `MemoryPromotionJob`. No new agent questions; the system acknowledges and captures. Lower cost, but the employee can't be re-interviewed.
- **Implementation (Option 1):**
  1. **Detect the addendum.** In `inbound_processor` and `web/turn_router`, when the selected conversation is `completed` and the employee sends a substantive message, call a new `Discovery::ReopenConversationService`.
  2. **`ReopenConversationService`:** set `conversation.status = "discovery"`; bump the per-agent/target budget by `discovery_addendum_budget` (new setting on `Company::DEFAULT_SETTINGS`, default 3); record a timeline event (`conversation_reopened`); ensure the Python `should_close` gate re-opens (it will, because `question_count < new target`). Add a rolling-summary note "Employee volunteered additional info after completion."
  3. **Python side:** no structural change needed — with budget available, `prepare` routes to `interview` again. Optionally add a system-prompt note that the interview was reopened by the employee so the agent acknowledges warmly and asks a focused follow-up.
  4. **Re-finalize:** when the reopened turn completes, `FinalizeConversationService` must run again — change the early-return so a **reopened** conversation can re-finalize (e.g. track `finalized_at`; allow re-finalize if there are new insights since `finalized_at`) and re-enqueue `AggregateIntelligenceJob` + `MemoryPromotionJob`.
  5. **Web `create` guard:** the web `discover_messages#create` endpoint has no completed-guard today; make the reopen explicit there too (accept the message, reopen, process) rather than echoing the closing message.
  6. **Frontend (employee web chat):** when `state_json.completed` is true, instead of disabling the composer, show a friendly "Interview complete — but you can always add more anytime" state with the composer enabled; on send, it hits the reopen path. Files: the employee discovery chat under `frontend/src/portals/public/` (discover chat page) and its `state_json` handling.
  7. **WhatsApp copy:** update `CLOSING_MESSAGES` ([agent/app/multi_agent_llm.py:22](agent/app/multi_agent_llm.py#L22)) to invite the employee to message anytime with more ("Thanks! We've got what we need for now — but if anything else comes to mind, just message me anytime and I'll add it.").
- **Acceptance criteria:**
  - A completed employee (WhatsApp **and** web) can send new information; it produces a new `ConversationInsight`, updates the blackboard, and re-runs aggregation + memory promotion.
  - The employee receives an acknowledging response, not a dead echo.
  - Reopen is bounded (can't be abused to run unlimited questions) via the addendum budget.
  - Intelligence/readiness reflect the late additions.
- **Tests:** Service spec for `ReopenConversationService`; `process_turn_service` spec for the reopened path producing an insight; a "completed → new message → re-aggregated" integration spec on both channels.

## FEAT-CLUSTER — Employee relationship / "map with links" view

- **Type:** Product / high perceived value. **~70% of the data already exists and is already served to the reviewer frontend — it's a presentation + edge-derivation gap, not a data gap.**
- **Problem:** Reviewers and admins face 10+ employees with only flat tables and one-at-a-time transcripts. There's no way to see "these N employees share this pain point / department / pattern," so cross-employee links are missed. The existing Evidence Graph is close but its backend builder **never wires the important edges**.
- **Evidence:**
  - Employee↔signal provenance already computed and served: `CompanySignal.metadata["source_excerpts"]` with `{employee_id, conversation_id, excerpt}` built at [backend/app/services/intelligence/signal_extractor.rb:105](backend/app/services/intelligence/signal_extractor.rb#L105), exposed at [backend/app/controllers/api/v1/reviewer/intelligence_controller.rb:38](backend/app/controllers/api/v1/reviewer/intelligence_controller.rb#L38).
  - Signals carry `departments`; patterns carry `linked_signal_ids` + `departments`; employees carry `department`/`role_title`/`seniority`.
  - Evidence graph builder does **not** connect signals (zero edges), only pattern→recommendation: [backend/app/services/evidence/graph_builder.rb:136](backend/app/services/evidence/graph_builder.rb#L136).
  - Frontend graph uses type-ring layout (position is meaningless): [frontend/src/portals/reviewer/ReviewerEvidenceGraph.tsx](frontend/src/portals/reviewer/ReviewerEvidenceGraph.tsx).
  - Dishonest coverage stats: `supported_edges` counts edge types never generated; "signals covered" = node count. [backend/app/services/evidence/graph_builder.rb:212](backend/app/services/evidence/graph_builder.rb#L212).
- **Design.** Deliver an **"Employee clusters" view**: pins = employees; edges = shared signal / shared department / shared pattern; node size = evidence contributed; clustering/force layout so groups read visually. Keep the existing filter/select/highlight UI and Pulse palette. Ship in the reviewer portal first, then reuse for company admins.
- **Implementation:**
  1. **(Optional but recommended) `signal_sources` join table.** Today employee↔signal lives in a JSONB `source_excerpts` capped at 10 (`MAX_EVIDENCE`, [signal_extractor.rb:14](backend/app/services/intelligence/signal_extractor.rb#L14)) — lossy and not SQL-queryable. Add `signal_sources (company_signal_id, employee_id, conversation_id, message_id, excerpt)` with indexes, populated by `signal_extractor`/`signal_upsert_service`. This makes clustering robust and queryable. If deferring, derive edges from `source_excerpts` for now.
  2. **Wire edges in `Evidence::GraphBuilder`:**
     - `signal → employee` (`extracted_from`) from `source_excerpts`/`signal_sources`.
     - `signal → pattern` (`aggregates_into`) from `pattern.linked_signal_ids`.
     - `recommendation → signal/pattern` (`derived_from`) where available.
     - `employee ↔ employee` (`shares_signal`, weighted by count) computed from co-occurrence on the same signal; optionally `same_department`.
     This also makes the existing `supported_edges` coverage stat truthful (those edge types finally exist).
  3. **Fix the coverage stats** to count real edges (BLK-adjacent honesty; see FEAT-STATS).
  4. **Frontend:** add a force-directed / clustering layout mode (e.g. a lightweight force simulation, or precompute clusters server-side by connected components over shared-signal edges and lay out clusters). Node size ∝ evidence count; color by department (Pulse `--chart-1..6`); edge thickness ∝ shared-signal count. Clicking an employee highlights their cluster and lists shared signals in the Selection panel (replace the raw `Type id → Type id` dump with human labels — already partly done in the recent evidence-graph re-skin).
  5. **Company admin surface:** expose the same view (read-only) in the company portal intelligence section so admins get the same overview.
- **Acceptance criteria:**
  - Reviewer can open a cluster view showing employees grouped by shared pain points/departments, with visible links and per-link evidence.
  - Clicking a link shows which employees share which signal and the supporting excerpts.
  - Coverage stats reflect real edges (no phantom metrics).
- **Tests:** `graph_builder` spec asserting signal↔employee and signal↔pattern edges exist and coverage counts match; a `signal_sources` model spec if added.
- **Note:** Signal extraction is regex/keyword-based ([signal_extractor.rb:5](backend/app/services/intelligence/signal_extractor.rb#L5)); clustering quality inherits that. Improving extraction (LLM-assisted) is a separate, larger effort — track under FEAT-AGENTS.

## FEAT-ENRICH — Company profile enrichment at onboarding

- **Type:** Product / medium priority. **Capture + downstream wiring must ship together, or the fields are dead data.**
- **Problem:** Onboarding captures almost nothing (display name, locale, engagement mode, employee phones). The Company model has no industry, region, size, org structure, or goals, so discovery, reports, and catalog fit run "cold" — `build_context` passes only name/department/language.
- **Evidence:** [frontend/src/portals/company/CompanyOnboarding.tsx](frontend/src/portals/company/CompanyOnboarding.tsx); [backend/app/controllers/api/v1/company/onboarding_controller.rb](backend/app/controllers/api/v1/company/onboarding_controller.rb); `Company::DEFAULT_SETTINGS` [backend/app/models/company.rb:35](backend/app/models/company.rb#L35); downstream `build_context` [backend/app/services/discovery/process_turn_service.rb:60](backend/app/services/discovery/process_turn_service.rb#L60); catalog fit [backend/app/services/catalog/company_fit_service.rb](backend/app/services/catalog/company_fit_service.rb); report snapshot [backend/app/services/reports/snapshot_builder.rb:23](backend/app/services/reports/snapshot_builder.rb#L23).
- **Implementation:**
  1. **Capture fields.** Add a `company_profile` JSONB (or explicit columns) to `companies`: `industry`, `sub_industry`, `size_band` (headcount), `region`/`country`, `annual_revenue_band` (optional), `business_goals` (free text / tags), `known_systems` (seed `CompanySystem` rows with `source: "manual"`), `org_structure`/`departments`. Expose in Onboarding Step 1 and in `company/settings#update_organization` (`organization_params`).
  2. **Known-systems upfront:** when the admin lists tools, create `CompanySystem` rows (`source: "manual", confidence: 1.0`) so `catalog/company_fit_service` benefits from turn one.
  3. **Wire downstream (the important half):**
     - `discovery/process_turn_service#build_context` — include industry/size/region/goals so agents tailor questions.
     - `discovery/context_builder` — pass the profile into the multi-agent context.
     - `catalog/company_fit_service` — factor industry/size into fit scoring/prioritization.
     - `reports/snapshot_builder` — include a company-profile block in the report and use it to frame the executive summary (also helps the generic-exec-summary issue).
  4. **(Optional) External enrichment.** You already capture the work-email domain in the demo form; add a domain-based firmographic lookup (e.g. Clearbit/again-provider) at signup/onboarding to pre-fill industry/size/region. Make it best-effort and editable. Defer if it adds vendor cost/scope.
- **Acceptance criteria:** Onboarding captures firmographics + known systems; the agent context, catalog fit, and report each demonstrably use them (e.g. a report references industry; catalog fit changes with size/industry).
- **Tests:** Controller spec for the expanded onboarding params; a `build_context` spec asserting the profile is included; a `company_fit_service` spec asserting industry/size affects scoring.

## FEAT-AGENTS — Agent logic improvements

- **Type:** Quality / medium priority.
- **Problems & fixes (each independent):**
  1. **JSON parsing brittleness → false "outage".** `_parse_payload` naive fence-strip + `json.loads`; a verbose reply throws, counts against the breaker, surfaces as "OpenAI unavailable." Evidence: [agent/app/multi_agent_llm.py:204](agent/app/multi_agent_llm.py#L204). Fix: use OpenAI **structured outputs / JSON mode** (response_format) and a tolerant parser; on parse failure, one reformat retry before counting a breaker failure; distinguish parse errors from transport errors.
  2. **Two circuit breakers can desync / fail open.** Rails and Python both key `openai:circuit_open` but only coordinate if they share the exact same Redis; both fail open on Redis error. Evidence: [agent/app/circuit_breaker.py:9](agent/app/circuit_breaker.py#L9); `backend/app/services/openai_circuit_breaker.rb`. Fix: ensure both point at the **same** Redis URL/DB (document in env matrix); consider a single owner (Python) that Rails reads. Decide fail-open vs fail-closed deliberately and document.
  3. **Agent-service errors are all mapped to "unavailable."** A 4xx (bad payload) is retried like an outage. Evidence: [backend/app/services/langgraph/client.rb:80](backend/app/services/langgraph/client.rb#L80). Fix: treat 4xx as a permanent error (log + surface), only 5xx/timeouts as retryable `UnavailableError`. Shorten the 120s read timeout on the synchronous path.
  4. **Shallow routing; COMPLIANCE persona never used.** Routing is fixed rules; personas differ only in prompt; `COMPLIANCE` defined but never routed. Evidence: [agent/app/router.py:17](agent/app/router.py#L17); [agent/app/personas.py:30](agent/app/personas.py#L30). Fix: either route COMPLIANCE for regulated departments (finance/legal/hr) or remove it to avoid dead code; optionally re-prioritize agents based on coverage/findings mid-interview.
  5. **Memory retrieval injects nearest-3 regardless of relevance.** Evidence: [backend/app/services/discovery/context_builder.rb:8](backend/app/services/discovery/context_builder.rb#L8). Fix: add a cosine similarity threshold; skip injection below it (ties to BLK-6 index).
  6. **Mock mode stores memory facts without embeddings** (unretrievable later). Evidence: [backend/app/jobs/memory_promotion_job.rb](backend/app/jobs/memory_promotion_job.rb). Fix: skip promotion (or mark `pending_embedding`) when no key, and re-embed when a key is available.
  7. **Phase D groundwork (future):** Postgres LangGraph checkpointer (durability for partial-turn failures), a **Gap Analyst** agent (pairs naturally with FEAT-CLUSTER — "who didn't we ask / what's missing"), and a **Reviewer Liaison** agent (suggest follow-up drafts). All planned, none started ([PROJECT_STATUS.md](PROJECT_STATUS.md) lines ~99, 352-354, 383-387).
- **Acceptance criteria:** Malformed LLM JSON no longer trips the breaker; 4xx from the agent isn't retried as an outage; the two breakers provably share state; irrelevant memory isn't injected; no dead persona.
- **Tests:** Python unit tests for the tolerant parser and 4xx handling; Rails spec for `langgraph/client` error classification.

## FEAT-SIGNUP — Self-serve signup & approval flows

- **Type:** Product / medium priority. Nothing exists today — three login endpoints only, no registration controller, dead "Forgot password."
- **Evidence:** [backend/config/routes.rb:10](backend/config/routes.rb#L10) (login only); no registrations controller; [frontend/src/auth/LoginForm.tsx](frontend/src/auth/LoginForm.tsx) (hardcoded demo password, dead forgot-password); [frontend/src/marketing/MarketingNav.tsx](frontend/src/marketing/MarketingNav.tsx) / [frontend/src/marketing/sections/MarketingFooter.tsx](frontend/src/marketing/sections/MarketingFooter.tsx) (no signup entry). `CompanyUser` already has an unused `pending` status ([backend/app/models/company_user.rb:8](backend/app/models/company_user.rb#L8)); `ReviewerUser` has only active/deactivated ([backend/app/models/reviewer_user.rb:13](backend/app/models/reviewer_user.rb#L13)). `DemoRequest` has a `status` field but no admin queue consumes it.
- **Implementation:**
  1. **Company signup (with admin approval):**
     - Public endpoint `POST /api/v1/public/company_registrations` creating a `Company` in a **pending** state + a `CompanyUser` in the existing `pending` status. Add a `pending_approval`/`approved` concept to `Company` (or reuse subscription state) and **defer** the `company/login` active-subscription hard-requirement for pending companies (so they can't fully log in until approved, or can log in to a limited "awaiting approval" state).
     - Platform approval queue: `GET /api/v1/platform/registrations` + `approve`/`reject` actions; on approve, activate the company + user and send a welcome/set-password email.
     - Reuse or supersede `DemoRequest` as the backing store (it already has `status`), or add a dedicated `CompanyRegistration` model — recommend the latter for clarity.
  2. **Reviewer signup (footer entry):**
     - Public endpoint `POST /api/v1/public/reviewer_applications`. Add `pending`/`approved`/`rejected` to `ReviewerUser` (currently only active/deactivated) + `approved_at`.
     - Platform approval queue + emails.
     - Entry point in `MarketingFooter.tsx` ("Become a reviewer") and a `/reviewer/apply` route/page.
  3. **Password setup + reset (shared prerequisite):** implement a token-based set-password flow (email a signed token → set password) and a working "forgot password." Today passwords are set by admins at creation; self-serve needs this. There is no reset backend today.
  4. **Frontend:** new routes/pages for both signups; company signup CTA in `MarketingNav.tsx`; reviewer link in the footer; platform-portal approval-queue UI (the platform portal has no pending-approvals view today).
  5. **Emails:** applicant confirmation, admin notification, approval, rejection. Only `DemoRequestMailer` exists in this area.
- **Acceptance criteria:** A prospect can request a company account and cannot access data until a platform admin approves; a reviewer can apply from the footer and is inert until approved; both get emails; set-password and forgot-password work.
- **Tests:** Request specs for the registration endpoints and approval transitions; a spec asserting a pending company/reviewer cannot authenticate.

## FEAT-STATS — Stats honesty pass

- **Type:** Trust / low-effort, high-signal.
- **Problems & fixes:**
  1. Company dashboard **"Signals" tile capped at 5** (`top_pain_points.length`, capped at [backend/app/services/reports/snapshot_builder.rb:40](backend/app/services/reports/snapshot_builder.rb#L40)) — show the true signal count.
  2. Evidence graph **"Signals covered"** = signal node count and **`supported_edges`** counts edge types never generated ([backend/app/services/evidence/graph_builder.rb:212](backend/app/services/evidence/graph_builder.rb#L212)) — fix once FEAT-CLUSTER wires real edges; until then, don't display them.
  3. Platform **"Reports" tile** sums ready+generating+failed into one ambiguous number ([frontend/src/portals/platform/PlatformDashboard.tsx:79](frontend/src/portals/platform/PlatformDashboard.tsx#L79)) — split or label by state.
  4. Reviewer **"co-reviewers"** count includes the viewer themselves ([frontend/src/portals/reviewer/ReviewerCompanyOverview.tsx:102](frontend/src/portals/reviewer/ReviewerCompanyOverview.tsx#L102)) — count others only.
  5. Reviewer structured-findings `evidence_refs` are **free-text** strings not validated against real IDs ([frontend/src/portals/reviewer/workspace/ReviewerStructuredFindingsPanel.tsx:199](frontend/src/portals/reviewer/workspace/ReviewerStructuredFindingsPanel.tsx#L199)) — replace with a picker resolving to real signal/pattern IDs.
  6. GulfLink report issues still open: generic executive summary, "1 of 0 employees completed discovery" count bug, and `report_kind` mislabeled `discovery` for docs-only runs (should be `baseline`). See [docs/manual-test/scenario-gulflink/OBSERVATIONS.md](docs/manual-test/scenario-gulflink/OBSERVATIONS.md). Fix the count logic and `report_kind` derivation in the snapshot builder / report readiness path.
- **Acceptance criteria:** Every displayed stat is either accurate or removed; the exec-summary count bug and `report_kind` are fixed.
- **Tests:** `snapshot_builder` spec asserting signal count is not capped for the tile and `report_kind` is `baseline` for docs-only.

---

# PART C — SEQUENCING, MILESTONES, DEFINITION OF DONE

## Recommended order

**Milestone 1 — Production safety (blockers).** BLK-1 (OCR fabrication), BLK-5 (Stripe/mock checkout), BLK-3 (PII encryption), BLK-2 (backups), BLK-4 (error tracking), BLK-6 (vector indexes). Ship before any real customer data enters the system. These are mostly contained and independent.

**Milestone 2 — Hardening.** HIGH-1/2 (rate limiting + Redis cache), HIGH-5 (WhatsApp message loss), HIGH-4 (timeouts + queue split), HIGH-3 (internal token), HIGH-8 (health/logs), HIGH-10 (log PII), HIGH-9 (retention/erasure), HIGH-12 (deploy rollback), HIGH-11 (tests/CI), HIGH-6/7 (perf + indexes). Then the MEDIUM items.

**Milestone 3 — Core product gap.** FEAT-ADDMORE (employees can always add more) — highest product priority; currently actively misleads employees.

**Milestone 4 — Reviewer effectiveness.** FEAT-CLUSTER (employee relationship view) + FEAT-STATS (honest stats, incl. fixing the graph coverage metrics as a side effect).

**Milestone 5 — Growth & quality.** FEAT-SIGNUP (self-serve + approval), FEAT-ENRICH (company profile), FEAT-AGENTS (agent robustness). FEAT-AGENTS #7 (Phase D: checkpointer, Gap Analyst, Reviewer Liaison) is a later, larger track.

## Definition of done (applies to every item)

- Backend `bundle exec rspec` = 0 failures; new services have specs.
- Frontend `npm run build` + `npm run lint` clean; critical-flow Vitest tests added (once HIGH-11 lands).
- No new hardcoded colors (Pulse tokens only); no new `permit!`; multi-tenant scopes respected.
- No mock/fabricated data reachable in production (`MocksAllowed.allowed?` gate honored).
- Any new env var added to **Appendix A** and to `.env.example` + `deploy/.env.production.example`.
- User-facing changes screenshot-verified against the running stack.

---

# APPENDICES

## Appendix A — Environment variable matrix (target state)

Add missing entries to `.env.example` and `deploy/.env.production.example`. **Bold = currently missing / must add.**

| Var | Used by | Notes |
|-----|---------|-------|
| `DATABASE_URL` | Rails | Managed PG target (BLK-2) |
| `REDIS_URL` | Rails, Sidekiq, cache, agent | Must be **shared** for cache (HIGH-2) & breaker sync (FEAT-AGENTS) |
| **`REDIS_CACHE_URL`** | Rails cache | HIGH-2 — optional; defaults to `REDIS_URL` with Redis DB `/1` |
| `OPENAI_API_KEY` | Rails, agent | Rotate current dev key |
| `OPENAI_VISION_MODEL` | Rails | default `gpt-4o-mini` |
| **`SENTRY_DSN`** | Rails/Sidekiq | BLK-4 |
| **`VITE_SENTRY_DSN`** | Frontend | BLK-4 |
| **`SENTRY_DSN` (agent)** | Python agent | BLK-4 |
| **`STRIPE_SECRET_KEY`** | Rails | BLK-5 |
| **`STRIPE_WEBHOOK_SECRET`** | Rails | BLK-5 — hard-required in prod |
| `INTERNAL_API_TOKEN` | Rails internal API | HIGH-3 — remove default, require in prod |
| `JWT_SECRET` | Rails | LOW-2 — set explicitly, don't rely on `secret_key_base` |
| **`BACKUP_BUCKET` / `BACKUP_S3_ENDPOINT` / AWS creds** | backup script | BLK-2 |
| **AR Encryption keys** (`primary_key`, `deterministic_key`, `key_derivation_salt`) | Rails | BLK-3 — via credentials |
| `WHATSAPP_*` (token, phone id, verify token, app secret) | Rails | verify all set; app secret enables signature check |
| `GOTENBERG_URL` | Rails | PDF |
| `LANGGRAPH_URL` / agent host | Rails | discovery |
| `ALLOW_MOCKS` | Rails/agent | **must be unset/0 in prod** |
| `SALES_INBOX` | Rails | demo-request notifications (defaults to sales@worktruth.com) |

## Appendix B — Key file map

- **OCR / multimodal:** `backend/app/services/openai/client.rb`, `multimodal/ocr_fallback.rb`, `multimodal/parse_document_service.rb`, `multimodal/document_text_extractor.rb`.
- **Billing:** `backend/app/controllers/api/v1/webhooks/stripe_controller.rb`, `billing/mock_checkout_controller.rb`, `services/billing/{checkout_service,stripe_webhook_handler}.rb`.
- **Discovery flow:** `services/discovery/{process_turn_service,finalize_conversation_service,context_builder,proactive_start_service}.rb`; `services/whatsapp/{inbound_processor,discovery_handler}.rb`; `services/web/turn_router.rb`; `controllers/concerns/employee_web_authenticatable.rb`.
- **Agent (Python):** `agent/app/{main,multi_agent_graph,orchestrator,router,multi_agent_llm,personas,state,config,circuit_breaker}.py`.
- **Intelligence / evidence:** `services/intelligence/{signal_extractor,signal_upsert_service,aggregate_company_intelligence,pattern_detector}.rb`; `services/evidence/graph_builder.rb`; `controllers/api/v1/reviewer/intelligence_controller.rb`.
- **Catalog / market intel:** `services/catalog/{company_fit_service,hybrid_matcher,sync_source_service,analyze_candidate_service}.rb`; `services/market_intel/{employee_fit_service,match_and_notify_service,send_alert_service}.rb`.
- **Auth / onboarding:** `controllers/api/v1/auth/*_sessions_controller.rb`; `controllers/api/v1/company/onboarding_controller.rb`; `models/{company,company_user,reviewer_user,demo_request}.rb`.
- **Ops / deploy / config:** `docker-compose.prod.yml`, `scripts/deploy/*`, `.github/workflows/{ci,deploy}.yml`, `deploy/Caddyfile`, `backend/config/environments/production.rb`, `backend/config/initializers/{sidekiq,cors,filter_parameter_logging}.rb`, `backend/config/sidekiq.yml`, `backend/config/sidekiq_schedule.yml`.
- **Frontend:** `frontend/src/App.tsx` (routes), `frontend/src/portals/{platform,company,reviewer,public}/**`, `frontend/src/marketing/**`, `frontend/src/lib/api.ts`.

## Appendix C — Testing & verification conventions

- **Backend:** RSpec in the `req_app_test` DB (isolated). Stub external HTTP with WebMock; a global OpenAI embeddings stub already exists in `backend/spec/support/openai_stubs.rb`. Never hit real OpenAI in tests.
- **Frontend:** add Vitest + RTL (HIGH-11). Screenshot critical screens against the running Docker stack (login helper pattern: POST to `/api/v1/auth/<portal>/login`, stash session in `localStorage` under key `req_app_session`, navigate).
- **Agent:** add pytest for the parser / error-classification changes.
- **Full-cycle:** the `scenario:gulflink` runner (`backend/lib/gulflink_scenario_runner.rb`) is a useful end-to-end harness, but note it **injects synthetic data to force green checks** (fabricates a confirmed pattern, overwrites weak doc summaries, force-publishes agentic ideas). Do not treat its green run as proof the underlying pipeline is strong — verify real extraction separately.

---

*End of plan. Keep this file updated as items are completed (check them off in the summary table). Each item is independently actionable; prefer small, reviewed PRs per ID.*
