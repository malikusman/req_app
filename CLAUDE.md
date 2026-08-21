# req_app — Project Context

Read this before doing anything. If a task references files or conventions below, use them rather than re-deriving from scratch.

## Stack

- **Backend**: Rails 7.1 / Ruby 3.1.2, PostgreSQL, run via Docker Compose.
- **Frontend**: React + TypeScript, in `frontend/`, run via Docker Compose.
- **Dev environment**: `docker compose up -d` for services. Backend commands run via `docker compose run --rm --no-deps rails bash -lc "..."`. Frontend via `docker compose run --rm --no-deps frontend sh -c "..."`.
- No bundler/ruby/npm on the host — everything runs through the containers.

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

## Conventions for this branch

- **Read-only investigation vs. implementation are different modes.** Some sessions are explicitly investigation-only (no file writes). Follow whatever the task prompt says.
- **Propose a plan before writing code** for any non-trivial task. Wait for confirmation.
- **One logical change per commit.** Verify (backend suite + frontend build) between commits, not just at the end.
- **Never amend, rebase, or squash existing commits** unless explicitly told to. New commits only.
- **Never push** unless explicitly told to.
- **Never touch `docker-compose.yml` or other infra config** without flagging it first — one prior session needed a mount change and asked before making it.
- If any command output looks duplicated, truncated, or inconsistent with a prior read, **stop and say so** rather than acting on it — this has caused real errors before in this project. Prefer `node -e "..."` reading explicit line ranges for large files if shell tools misbehave.
- Do not fabricate question wording, option text, or any content not present in `docs/questionnaire-v2-field-mapping.md`. If something needed isn't in that doc, stop and ask.
