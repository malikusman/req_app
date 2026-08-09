# Companion local eval observations

- **When:** 2026-08-09T22:44:28Z (~11 min wall clock on Gemma-4-12b via LM Studio)
- **Model:** `google/gemma-4-12b-qat`
- **Base URL:** `http://host.docker.internal:1234/v1`
- **ALLOW_MOCKS:** false
- **Structural OK:** true
- **Judge pass rate:** 1.0 (threshold 0.7)
- **Overall:** PASS

All 8 scenarios passed Layer A. Companion turns (C1–C4, C7, W1) all passed Layer B (scores 0.95–1.0, no interview leak). C5/C6 discovery turns stubbed after reopen as planned.

| ID | Label | Status | Agent | A score | B score | Pass |
|----|-------|--------|-------|---------|---------|------|
| C1 | casual | completed | companion | 1.0 | 1.0 | true |
| C2 | ask | completed | companion | 1.0 | 0.95 | true |
| C3 | tools | completed | companion | 1.0 | 1.0 | true |
| C7 | refuse-interview-feel | completed | companion | 1.0 | 1.0 | true |
| C4 | share | completed | companion | 1.0 | 0.95 | true |
| C5 | promote | discovery | domain_finance | 1.0 | skip | true |
| C6 | addendum | discovery | domain_finance | 1.0 | skip | true |
| W1 | web-casual | completed | companion | 1.0 | 1.0 | true |

## Sample replies

### C1 — casual

**User:** thanks!

**Assistant:**

> You're very welcome, Aisha! I'm here whenever you need anything else. If you think of any other details regarding those AP bottlenecks, just say 'add this to my interview'.

### C2 — ask

**User:** how do I chase overdue approvals faster?

**Assistant:**

> It sounds like those dual approval bottlenecks before SAP are a real hurdle for your workflow. You might consider setting up automated reminders or a shared tracker — and say 'add this to my interview' if you want that friction in the report.

_Judge score:_ 0.95

### C3 — tools

**User:** any tools for invoice matching?

**Assistant:**

> From your company catalog / matches:
> 1. Worktruth AP Copilot (Worktruth) — tag_match:finance; keyword_match:invoice,matching
> 2. Bill.com …

(Company-catalog-first formatting confirmed.)

### C4 — share

**User:** Today I spent 2 hours retyping handwritten POD notes into Excel before dual approval

**Assistant:**

> Thanks — I've noted that. Want me to add it to your discovery interview so it can inform the company report? Reply yes to add it.

### C5 — promote

**User:** yes

**Assistant:**

> Thanks — I've captured that addendum for discovery.

(Status → `discovery`; reopen asserted.)

### W1 — web-casual

**User:** thanks!

**Assistant:**

> You're very welcome, Aisha! That manual retyping of POD notes sounds like a real time sink. If you'd like me to include that in your company report, just say 'add this to my interview'.

## Ops notes

- First live `companion_chat` to Gemma took ~40–45s; full matrix ~11 minutes.
- Initial artifact write failed because Compose mounted `docs/manual-test` as `:ro`. Mount is now read-write; `ARTIFACT_DIR` prefers `/docs/manual-test/companion-eval`.
- Recreate rails after compose change if needed: `docker compose up -d rails`

## How to re-run

```bash
docker compose exec -e OPENAI_BASE_URL=http://host.docker.internal:1234/v1 \
  -e OPENAI_API_KEY=lm-studio \
  -e OPENAI_MODEL=google/gemma-4-12b-qat \
  -e DOCS_MODEL_FAST=google/gemma-4-12b-qat \
  -e OPENAI_JSON_MODE=false \
  -e OPENAI_MAX_TOKENS=2500 \
  -e OPENAI_READ_TIMEOUT=300 \
  -e ALLOW_MOCKS=0 \
  -e LIVE=1 -e WRITE=1 \
  rails bundle exec rails scenario:companion
```
