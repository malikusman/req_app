# Production E2E — GulfLink Freight Pilot (2026-07-26)

Portal: https://req.pebbleintelligentsolutions.com  
Bot WhatsApp: **+971 55 290 9236**

## Credentials

| Role | Login |
|------|--------|
| Platform admin | `masood.albastaki@pebbleintelligentsolutions.com` / `PebbleIntl@2026!` |
| Company admin (client) | `pilot-admin@gulflink-pilot.test` / `PilotPass1!` |
| Reviewer (100% profile) | `nadia.pilot@reqapp.review` / `ReviewerPass1!` |
| Employee (WhatsApp) | Phone **+971526187620** · Access code **`OGZP7MZJ`** · Name on file: Sara Al Mansouri |

Company: **GulfLink Freight Pilot** (`id=5`, slug `gulflink-freight-pilot`)

### Why the access code is not on the portal

Full access codes are shown **once** right after invite (green banner on Employees). After that the portal only keeps a bcrypt hash + last-two hint — by design, so codes cannot be read back from the employee list. Reply to WhatsApp with **`OGZP7MZJ`** (still active / hint `ZJ`).

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

1. **CRITICAL — blank `OPENAI_BASE_URL` breaks embeddings** — **FIXED + pushed** (`6797fef`). Compose defaults blank base URLs to `https://api.openai.com/v1`.

2. **RSS sync redirects** — **FIXED**. Catalog sync / article fetch use `Http::GetWithRedirects`; seed feed URLs updated to final destinations.

3. **Concurrent DocumentAnalysisRunJob** — **FIXED**. Company row lock + partial unique index on one active run per company; chunk embedder locks the document around delete/recreate.

4. **Website research** — **HARDENED**. Follows redirects with SSRF re-check, browser-like Accept headers, clearer errors (`blocked_by_site` for 403). Sites behind aggressive WAFs (e.g. Aramex/Akamai) can still block automated fetch — that is expected, not a silent `fetch_failed`.

5. **Upload MIME** — curl needs explicit `type=` for XLSX/DOCX; product upload path is fine.

## Next checks after you finish WhatsApp

- Company → Employees / Conversations: Sara progressing  
- Intelligence refresh / report generate  
- Reviewer login → company 5 report workspace  

## Log tails used

`docker compose -f docker-compose.prod.yml --env-file .env.production logs -f rails sidekiq langgraph`
