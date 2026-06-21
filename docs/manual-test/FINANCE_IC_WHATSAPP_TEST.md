# Finance IC — WhatsApp Full-Cycle Manual Test

**Phone:** +971526187620  
**Company:** Acme Corp  
**Portal:** https://req.pebbleintelligentsolutions.com

Save these files to your phone before discovery:

- `sap-invoice-entry.jpg` — caption: `SAP invoice entry screen`
- `month-end-close-checklist.pdf` — caption: `Month-end close SOP`

---

## Phase 1 — Onboarding

Message **+971 55 290 9236** (Req discovery bot).

Your name is already on file from the invite — **start with your access code**, not your name.

| Step | You send | Expected reply |
|------|----------|----------------|
| 1 | `{ACCESS_CODE}` | Consent text — reply `YES` |
| 2 | `YES` | Profiling intro + job title question |

If you ever onboard without a preset name, the bot will ask **"What's your name?"** before accepting your reply.

---

## Phase 2 — Profiling

| Step | You send | Expected next question |
|------|----------|------------------------|
| 3 | `Accounts Payable Specialist` | Department? |
| 4 | `Finance` | Seniority level? |
| 5 | `I'm an individual contributor` | Daily responsibilities? |
| 6 | `I reconcile vendor invoices in Excel and chase approval emails before entering everything into SAP` | Tools used daily? |
| 7 | `SAP, Excel and Outlook` | Bridging message, then first discovery question |

---

## Phase 3 — Discovery (~10–12 turns)

Send **text only** unless noted. Discovery answers can be your own words or copy below.

1. `It starts when a vendor emails an invoice and ends when SAP shows it as paid, usually 8 days later`
2. `Matching invoices to purchase orders goes wrong the most — about 1 in 5 needs rework`
3. **IMAGE** — send `sap-invoice-entry.jpg` with caption `SAP invoice entry screen`  
   Expected ack: `Got your image — analyzing it now…`
4. `I depend on department managers for approvals, mostly chased over email and Slack`
5. **PDF** — send `month-end-close-checklist.pdf` with caption `Month-end close SOP`  
   Expected ack: `Got your document — processing it now…`
6. `Invoices sit in managers' inboxes for 2-3 days before anyone acts on them`
7. `Handoffs go through email with the invoice attached, no shared tracker`
8. `SAP and Excel don't talk to each other at all, I re-enter everything by hand`
9. `I copy invoice numbers, amounts and vendor codes between Excel and SAP daily`
10. `When SAP is down I keep a paper list and batch-enter everything after`

**Completion:** Closing thank-you message; employee status → completed.

**Quality checks during interview:**

- [ ] Follow-up questions feel relevant (not repetitive)
- [ ] Topics shift from finance → process → technical naturally
- [ ] After image/PDF, later questions may reference manual entry or approvals
- [ ] No long silence (>60s); delay message acceptable once

---

## Phase 4 — Portal verification

| Step | Login | Check |
|------|-------|-------|
| 1 | `admin@acme.local` / `password123` | Employee **Usman Test** → completed |
| 2 | Company → Conversations | Full transcript + 2 media attachments |
| 3 | Documents / Media | WhatsApp uploads indexed with extracted text |
| 4 | Intelligence | Signals on invoices/SAP; multimodal evidence present |
| 5 | Reports → Generate | Report generates (early report allowed on Acme) |
| 6 | Download PDF | Supporting media section lists 2 attachments |
| 7 | `reviewer@reqapp.local` / `password123` | Report review → supporting media in sidebar |
| 8 | *(Optional)* Reviewer follow-up | Reviewer sends question → you reply on WhatsApp |

Platform admin: `admin@reqapp.local` / `password123`

---

## Re-run / reset

On the server:

```bash
PHONE=+971526187620 COMPANY=acme-corp ./scripts/manual_test/provision_whatsapp_user.sh
```

Or from Rails (inside backend container):

```bash
PHONE=+971526187620 COMPANY=acme-corp rails runner lib/manual_test/provision_whatsapp_user.rb
```
