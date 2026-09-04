# Companion local eval observations

- **When:** 2026-09-04T13:28:33Z
- **Model:** `google/gemma-4-12b-qat`
- **Base URL:** `http://host.docker.internal:1234/v1`
- **ALLOW_MOCKS:** false
- **Structural OK:** true
- **Judge pass rate:** 1.0 (threshold 0.7)
- **Overall:** PASS

| ID | Label | Status | Agent | A score | B score | Pass |
|----|-------|--------|-------|---------|---------|------|
| C1 | casual | completed | companion | 1.0 | 1.0 | true |
| C2 | ask | completed | companion | 1.0 | 1.0 | true |
| C3 | tools | completed | companion | 1.0 | 1.0 | true |
| C7 | refuse-interview-feel | completed | companion | 1.0 | 1.0 | true |
| C4 | share | completed | companion | 1.0 | 1.0 | true |
| C5 | promote | discovery | domain_finance | 1.0 | skip | true |
| C6 | addendum | discovery | domain_finance | 1.0 | skip | true |
| W1 | web-casual | completed | companion | 1.0 | 1.0 | true |

## Sample replies

### C1 — casual

**User:** thanks!

**Assistant:**

> You're very welcome, Aisha! I'm here whenever you need help. If you think of any other details about your workflow or the AP process, just say 'add this to my interview' to include them in your report.

_Judge:_ Perfect closing response that acknowledges the user's thanks and provides a clear way to follow up without initiating new discovery questions.

### C2 — ask

**User:** how do I chase overdue approvals faster?

**Assistant:**

> To help clear those dual approval bottlenecks before SAP, you could try sending a weekly summary email that highlights only the overdue items for quick review. This makes it easier for approvers to see what needs immediate attention. You can say 'add this to my interview' to include this process improvement in your report.

_Judge:_ Provides a specific, actionable solution based on previous context without initiating a new discovery process.

### C3 — tools

**User:** any tools for invoice matching?

**Assistant:**

> From your company catalog / matches:
> 1. Worktruth AP Copilot (Worktruth) — tag_match:finance; keyword_match:invoice,matching
> 2. Bill.com (Bill.com) — tag_match:finance; keyword_match:invoice
> 3. Automate POD exception capture — Reduce Excel retyping of handwritten POD notes before SAP posting.
> 
> Want something added to your discovery interview for the company report? Say "add this to my interview".

_Judge:_ The assistant directly answers the user's request with specific tools from the catalog and provides a clear next step.

### C7 — refuse-interview-feel

**User:** cool, I'll check those later

**Assistant:**

> Sounds good! Take your time looking through those. If you think of any other details about your workflow or those approval bottlenecks, just say "add this to my interview" to include them in your report.

_Judge:_ The assistant correctly acknowledges the user's intent to review the materials later and provides a clear, non-intrusive way to update the report without starting a new interview.

### C4 — share

**User:** Today I spent 2 hours retyping handwritten POD notes into Excel before dual approval

**Assistant:**

> Thanks — I've noted that. Want me to add it to your discovery interview so it can inform the company report? Reply yes to add it.

_Judge:_ The assistant correctly acknowledges the user's input and offers a clear, relevant next step to include the information in the final output.

### C5 — promote

**User:** yes

**Assistant:**

> Thanks — I've captured that addendum for discovery.

### C6 — addendum

**User:** add this to my interview: dual CFO approval takes 5 days on average

**Assistant:**

> Thanks — I've captured that addendum for discovery.

### W1 — web-casual

**User:** thanks!

**Assistant:**

> You're very welcome, Aisha! I'm here whenever you'd like to share more about your workflow or if you need help with anything else.

_Judge:_ The assistant provides a polite, friendly closing that acknowledges the user's thanks without initiating any new discovery questions.

## How to re-run

```bash
# LM Studio on :1234 with gemma loaded, then:
docker compose exec -e OPENAI_BASE_URL=http://host.docker.internal:1234/v1 \
  -e OPENAI_API_KEY=lm-studio \
  -e OPENAI_MODEL=google/gemma-4-12b-qat \
  -e DOCS_MODEL_FAST=google/gemma-4-12b-qat \
  -e OPENAI_JSON_MODE=false \
  -e OPENAI_MAX_TOKENS=2500 \
  -e ALLOW_MOCKS=0 \
  -e LIVE=1 -e WRITE=1 \
  rails bundle exec rails scenario:companion
```