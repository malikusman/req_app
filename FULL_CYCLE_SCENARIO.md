# Full-cycle scenario test — Scenario Corp

End-to-end product walkthrough for local Docker: company docs → RAG-aware discovery → intelligence → report → dual reviewers → admin-gated outreach → structured findings → evidence graph → PDF expert validation.

**Companion observation log:** [`FULL_CYCLE_OBSERVATIONS.md`](FULL_CYCLE_OBSERVATIONS.md) (filled after a run)  
**Automator:** `docker compose exec rails bundle exec rails scenario:full_cycle`

---

## 0. Preconditions

| Check | How |
|-------|-----|
| Stack up | `docker compose ps` — rails, frontend, postgres, redis, sidekiq, minio, gotenberg, mailpit |
| Schema | Evidence-to-action migration applied (`report_review_findings`, `reviewer_outreaches`, …) |
| OpenAI | `OPENAI_API_KEY` set for live discovery + real embeddings; without it, expect mock questions / weaker RAG |
| Portals | http://localhost:5173 · API http://localhost:3000 · Mailpit http://localhost:8025 |

Company settings required (runner sets these):

- `discovery_profiling_enabled`
- `discovery_multi_agent_enabled`
- `discovery_memory_retrieval_enabled`
- `discovery_media_indexing_enabled`
- `discovery_multimodal_enabled`
- `allow_early_report`

---

## 1. Actors and credentials

Password for all seeded portal users: **`password123`**

| Role | Email / identity | Portal |
|------|------------------|--------|
| Platform | `admin@reqapp.local` | `/platform/login` |
| Company admin | `admin@scenario.local` | `/company/login` |
| Reviewer A | `reviewer@reqapp.local` | `/reviewer/login` |
| Reviewer B | `reviewer2@reqapp.local` | `/reviewer/login` |
| Employee | Jordan Scenario (phone `+14155558001`) | WhatsApp sim / discover token |

Max **2 active reviewers** per company — A and B only.

---

## 2. Narrative

**Company:** Scenario Corp (`scenario-corp`) — finance ops under month-end pressure.  
**Employee:** Jordan Scenario, Accounts Payable IC.  
**Docs:** Internal SOPs with **golden phrases** the interview answers deliberately echo so RAG retrieval is observable.

| Fixture | Golden phrase |
|---------|---------------|
| [`docs/manual-test/scenario/month-end-close-sop.md`](docs/manual-test/scenario/month-end-close-sop.md) | `SCENARIO_GOLDEN_PHRASE_MONTH_END_FREEZE` |
| [`docs/manual-test/scenario/invoice-approval-policy.md`](docs/manual-test/scenario/invoice-approval-policy.md) | `SCENARIO_GOLDEN_PHRASE_TRIPLE_APPROVAL` |
| [`docs/manual-test/scenario/sap-handoff-notes.txt`](docs/manual-test/scenario/sap-handoff-notes.txt) | `SCENARIO_GOLDEN_PHRASE_SAP_SHADOW_LEDGER` |

---

## 3. Phase checklist

### Phase A — Provision

1. Create `scenario-corp`, trial subscription, company admin.
2. Assign Reviewer A + B (active).
3. Upload the three fixtures via MinIO → `ParseDocumentJob` / parse service.
4. Confirm each document `status=ready` and `document_chunks` count > 0.

**Expected:** Documents ready; chunks embedded when OpenAI present.

### Phase B — Discovery interview (scripted)

Persona: `scenario_finance_ic` (via `DiscoverySimulator` / `scenario:full_cycle`).

**Profiling answers**

| Step | Reply |
|------|--------|
| Role | Accounts Payable Specialist |
| Department | Finance |
| Seniority | I'm an individual contributor |
| Responsibilities | I reconcile vendor invoices in Excel and chase approvals before SAP entry |
| Tools | SAP, Excel and Outlook |

**Discovery answers (echo golden phrases)**

1. Invoice lifecycle starts in email and ends when SAP shows paid — around 8 days.
2. Matching POs fails often; about 1 in 5 needs rework.
3. During close we hit **SCENARIO_GOLDEN_PHRASE_MONTH_END_FREEZE** and stop non-critical posts.
4. Approvals require **SCENARIO_GOLDEN_PHRASE_TRIPLE_APPROVAL** across manager, finance lead, and controller.
5. We keep a **SCENARIO_GOLDEN_PHRASE_SAP_SHADOW_LEDGER** in Excel because SAP reporting is rigid.
6. Invoices sit 2–3 days in manager inboxes.
7. Handoffs are email with PDF attachments — no shared tracker.
8. SAP and Excel do not sync; I re-key amounts and vendor codes daily.
9. At quarter end the approval backlog doubles first.
10. A perfect flow would auto-match POs and nudge approvers.
11. The weekly status email I compile could disappear.
12. That covers my work.

**Expected:** Conversation completes; insights/memory present; when RAG is on, retrieved context may include golden phrases after overlapping answers.

### Phase C — Intelligence + report

1. Aggregate company intelligence.
2. Generate report (Gotenberg PDF or HTML fallback).
3. Confirm snapshot keys: signals, patterns, recommendations, `supporting_documents`, `tools_catalog`.

### Phase D — Reviewer scenarios

**Reviewer A (endorse)**

- Mark all sections `approved`
- Add publishable findings: `executive_conclusion` + `risk`
- Open evidence graph — expect employee / message / document / signal nodes
- Optional: endorse a catalog entry

**Reviewer B (clarification)**

- Mark `signals` as `needs_info` with a comment
- Create outreach clarification → must be `pending_admin_approval` (not sent)
- Company admin approves → delivery queued/sent
- Record a reply; outreach moves toward replied/closed

**Meeting**

- Reviewer A creates meeting request → company admin approves

### Phase E — Submit + PDF

1. Submit Reviewer A (requires executive finding).
2. Submit Reviewer B (`needs_info` allowed with comment).
3. Regenerate-with-review / platform path: Expert validation appendix includes findings.

---

## 4. Portal URLs (after provision)

| Surface | URL |
|---------|-----|
| Company dashboard | `/company/dashboard` |
| Documents | `/company/documents` |
| Clarifications | `/company/outreaches` |
| Meetings | `/company/meeting-requests` |
| Reviewer company | `/reviewer/companies/:id` |
| Evidence graph | `/reviewer/companies/:id/evidence-graph` |
| Report workspace | `/reviewer/companies/:id/reports/:reportId/review` |
| Platform candidates | `/platform/catalog/candidates` |

---

## 5. ETA release gates (verify during run)

| Gate | Pass signal |
|------|-------------|
| A Trusted review | Submit blocked without executive finding; outreach not sent pre-approval |
| B Cited evidence | Graph + docs link to conclusions; supporting docs in snapshot |
| C Governed knowledge | Catalog candidates not matchable until curated (spot-check) |
| D Reproducible report | PDF/HTML regenerates from snapshot + reviewer overlay |
| E Safe employee value | Prefs API exists; digest job only for opted-in (spot-check) |

---

## 6. Commands

```bash
# Full automated scenario (provision → discovery → ETA checks → JSON checklist)
docker compose exec -T rails bundle exec rails scenario:full_cycle

# Cleanup scenario company data afterward
CLEANUP=1 docker compose exec -T rails bundle exec rails scenario:full_cycle

# Manual discovery only against scenario-corp (after provision)
SLUG=scenario-corp PERSONA=scenario_finance_ic docker compose exec -T rails bundle exec rails demo:simulate
```

---

## 7. Observation template

For each phase record in `FULL_CYCLE_OBSERVATIONS.md`:

- **Expected**
- **Actual** (IDs, statuses, counts)
- **Evidence** (log line / API field / DB query)
- **Why** (pass, or root cause if fail)
