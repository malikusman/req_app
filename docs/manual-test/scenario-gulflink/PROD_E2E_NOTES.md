# Production E2E — Multi-employee GulfLink (2026-08-02)

Portal: https://req.pebbleintelligentsolutions.com  
Bot WhatsApp: **+971 55 290 9236**

## Credentials

| Role | Login |
|------|--------|
| Company admin | `pilot-admin@gulflink-pilot.test` / `PilotPass1!` |
| Consultant (100%) | `nadia.pilot@reqapp.review` / `ConsultantPass1!` |
| Usman (WhatsApp) | **+971526187620** · employee_id **13** · onboarding `awaiting_consent` |

Company: **GulfLink Freight Pilot** (`id=5`)  
Report: **id=5** version **2** · Review **id=5** · 5 findings · 3 section comments · `shared_with_company` / `platform_approved` · ~452 KB appendix

## Automated results

| Stage | Result |
|-------|--------|
| Questionnaire | **100%** |
| First-party catalog | Worktruth AP Copilot + Ops Copilot matched |
| Consultant Nadia | ProfileCompleteness **100%**, assigned |
| Usman WA invite | **sent** (Meta wamid present) · **no profile seed** |
| James / Elena / Ahmer | Full web discovery **completed** · 10 insights each · media attached |
| Docs | **7/7 ready** · analyze run id=5 completed |
| Intelligence | signals=6 · patterns=7 · recs=4 |
| Consultant richness | overall note ≥400 chars · 3 section comments · 5 publishable findings · CEO Q&A closed · Usman outreach pending admin · discussion thread |
| Checks | Web sims **15/15** · Full cycle **23/23** |

## Web employees (simulated — emails not SMTP-delivered)

**SMTP_ADDRESS is blank on prod** → Mailinator did **not** receive invite mail. Conversations were driven via discover tokens (now **consumed** / one-shot).

| Person | Email | Dept | Status |
|--------|-------|------|--------|
| James Chen | james@mailinator.com | Finance | completed · PDF SOP shared |
| Elena Rossi | elena@mailinator.com | Operations | completed · POD PNG shared |
| Ahmer Khan | ahmer@mailinator.com | Customer Success | completed · PDF shared |

(Original discover URLs were used by the simulator and cannot be reopened.)

## Your live WhatsApp (Usman) — do this now

1. Message **+971 55 290 9236** from **+971 52 618 7620**
2. Send **`YES`**
3. Profiling (expected):
   - Title → `Accounts Payable Specialist`
   - Department → `Finance`
   - Seniority → `I'm an individual contributor`
   - Responsibilities → `I reconcile freight invoices in Excel, chase dual approvals, retype POD exceptions, then post into SAP FB60`
   - Tools → `SAP, Excel, WhatsApp, CargoWise and SharePoint`
4. Discovery — freight AP answers (PO match ~1/5, approvals 8–12 days, POD retyping, demurrage late). Optional POD photo.
5. When finished, tell us — or run on server:

```bash
cd /opt/req_app
docker compose -f docker-compose.prod.yml --env-file .env.production \
  exec -T rails bundle exec rails runner /tmp/prod_e2e_post_wa_refresh.rb
```

That refreshes intelligence, generates a new report version, and re-approves for company share.

## Portal walkthrough

- [x] Company questionnaire 100%, systems, 7 docs
- [x] James / Elena / Ahmer conversations completed with media
- [x] Report v2 with first_party tools + rich consultant appendix
- [x] Platform shared with company
- [ ] Usman live WhatsApp discovery
- [ ] Post-WA report refresh

## Scripts on prod (`/tmp` in rails)

- `prod_e2e_provision.rb`
- `prod_e2e_web_conversations.rb`
- `prod_e2e_full_cycle.rb`
- `prod_e2e_post_wa_refresh.rb`
- Results: `prod_e2e_results.json`, `prod_e2e_web_results.json`, `prod_e2e_web_invites.json`
