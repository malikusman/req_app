# Production E2E — GulfLink Freight Pilot (2026-07-26)

Portal: https://req.pebbleintelligentsolutions.com  
Bot WhatsApp: **+971 55 290 9236**

## Credentials

| Role | Login |
|------|--------|
| Company admin | `pilot-admin@gulflink-pilot.test` / `PilotPass1!` |
| Reviewer (100% profile) | `nadia.pilot@reqapp.review` / `ReviewerPass1!` |
| Employee (WhatsApp) | Phone **+971526187620** · Access code **`OGZP7MZJ`** · Name on file: Sara Al Mansouri |

Company: **GulfLink Freight Pilot** (`id=5`, slug `gulflink-freight-pilot`)

## What was provisioned

| Stage | Result |
|-------|--------|
| RSS catalog sources | 5 seeded; sync partial (OpenAI/Google/VentureBeat redirect 301/307/308 — candidates still created from HF/TechCrunch) |
| Solution catalog tools | UiPath, Bill.com, Zapier, Make, Notion AI |
| Questionnaire | **100%** |
| Company systems | SAP, HubSpot, BambooHR, Excel, WhatsApp Business, Teams, NetSuite (+ inferred) |
| Website | `https://www.aramex.com` — web research **fetch_failed** (site/SSRF/network) |
| Reviewer | Nadia Al-Rashid — **ProfileCompleteness 100%**, published, assigned |
| WhatsApp invite | **delivered** (Meta message id present) |
| Documents | **5 ready** (PDF, TXT, PNG, XLSX, DOCX) |
| Docs Analyze | KB **27** active entries; clarifications **3**; readiness **~87%**; signals **6**; patterns **1**; recs **1** |

## WhatsApp script (do this now)

Message **+971552909236**. Start with the access code (name already on file).

| Step | You send |
|------|----------|
| 1 | `OGZP7MZJ` |
| 2 | `YES` |
| 3 | `Accounts Payable Specialist` |
| 4 | `Finance` |
| 5 | `I'm an individual contributor` |
| 6 | `I reconcile freight invoices in Excel and chase approvals before SAP entry` |
| 7 | `SAP, Excel and WhatsApp` |
| 8+ | Discovery answers (examples): `PO matching fails ~1 in 5`; `Approvals take 8–12 days over email/WhatsApp`; `POD exceptions are retyped from handwritten notes`; optional photo of POD / Excel |

More lines: [FINANCE_IC_WHATSAPP_TEST.md](./FINANCE_IC_WHATSAPP_TEST.md).

## Bugs found on prod

1. **CRITICAL — blank `OPENAI_BASE_URL` breaks embeddings**  
   Compose `${OPENAI_BASE_URL:-}` injects `""`, so `Openai::Client` uses empty base → `ArgumentError: not an HTTP URI` on embed → all docs failed Analyze.  
   **Mitigated:** set `OPENAI_BASE_URL` / `EMBEDDING_BASE_URL` to `https://api.openai.com/v1` in `.env.production`. Compose defaults should be updated in repo.

2. **RSS sync redirects** — some seed feed URLs return 301/307/308; sync client does not follow redirects. Candidates still ingested from other sources.

3. **Concurrent DocumentAnalysisRunJob** — double-enqueue caused `PG::UniqueViolation` on `document_chunks (document_id, chunk_index)`. Re-ingest recovered.

4. **Website research** — `Companies::WebResearchService` returned `fetch_failed` for aramex.com.

5. **Upload MIME** — curl without explicit `type=` rejected XLSX/DOCX; with correct MIME they upload fine.

## Next checks after you finish WhatsApp

- Company → Employees / Conversations: Sara progressing  
- Intelligence refresh / report generate  
- Reviewer login → company 5 report workspace  

## Log tails used

`docker compose -f docker-compose.prod.yml --env-file .env.production logs -f rails sidekiq langgraph`
