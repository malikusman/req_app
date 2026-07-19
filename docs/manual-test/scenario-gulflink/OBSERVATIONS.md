# GulfLink Logistics scenario — observations

Generated: 2026-07-19T09:26:43Z  
Company: **GulfLink Logistics LLC** (`gulflink-logistics`) — Dubai logistics 3PL, CEO docs-first demo  
Runner: `rails scenario:gulflink`  
Checks: **28/28 passed** (final run)

## Scenario summary

| Step | Result |
|------|--------|
| 5 fixtures (pdf/xlsx/docx/txt/png) | 4 ready, 1 failed (PNG) |
| Intelligence | 6 signals, 6 patterns, 4 recommendations, readiness ~88 |
| Reviewer | Nadia Al-Rashid (ex-McKinsey logistics EM + Aramex) published & assigned |
| Report | v3 ready, review bootstrapped, PDF ~350KB with appendix |
| Q&A | Outreach replied + discussion thread/reply |
| Findings | executive endorse + risk needs_more_evidence submitted |

## Logins

- Company CEO: `ceo@gulflink.ae` / `password123`
- Finance Controller (seeded for Q&A): `controller@gulflink.ae` (employee channel)
- Reviewer: `nadia.mckinsey@reviewers.worktruth.local` / `password123`
- Platform: `admin@reqapp.local` (seed password)
- Report id: 29 (version 3)

---

## Gaps (in depth)

### Blocker

None for the happy path with 4 text-capable docs.

### Major

1. **[ingest] Image / POD scans do not become evidence**  
   `pod-scan-sample.png` failed with `invalid byte sequence in UTF-8`. `DocumentTextExtractor` has no image/OCR branch for portal uploads (only PDF OCR fallback). Handwritten POD exceptions—the exact artifact logistics teams upload—never enter signals.  
   **Impact:** Reviewer finding correctly flagged weak POD evidence; product still cannot use the image.  
   **Fix direction:** Route `image/*` through `OcrFallback` (or multimodal vision) before `insufficient_text` / binary `File.read`.

2. **[communication] CEO-only docs demo cannot receive reviewer questions**  
   Outreaches and employee-targeted discussions require an `Employee`. We had to seed Finance Controller Layla Hassan. A CEO exploring “docs only” has no native channel to answer Nadia without inventing staff.  
   **Impact:** Breaks the sales story “upload docs → expert asks you questions.”  
   **Fix direction:** Allow outreaches to company admins / named contacts, or a “CEO reply” portal inbox not tied to discovery employees.

3. **[text_generation] Executive summary is generic and employee-count confused**  
   Actual summary: *“1 of 0 employees completed discovery interviews. Findings are reinforced by 4 internal documents. Top friction areas include Manual data entry and spreadsheets, Core system dependency, Approval bottlenecks…”*  
   - “1 of 0” is nonsensical copy.  
   - Friction labels are template buckets (spreadsheets / approvals), not GulfLink-specific (freight billing exceptions, demurrage, Jebel Ali customs, AED thresholds).  
   - `report_kind` was `discovery` even though engagement_mode is documents (docs-only path expected `baseline`).  
   **Impact:** CEO reads a report that does not sound like their logistics company.  
   **Fix direction:** Docs-first snapshot builder should prefer document entities (TMS, demurrage, freight SOP) and never emit “N of 0 employees”; force `report_kind=baseline` when no completed interviews.

### Minor

4. **[communication] Discussion UX is reviewer-monologue unless WhatsApp follow-up fires**  
   Creating an employee-targeted `ReviewDiscussion` also triggers `ReviewerFollowup::SendService`, but the “reply” we created in-thread was still authored by the reviewer. There is no clear company-portal surface for Layla to answer the discussion itself.  
   **Impact:** Dual channels (discussion + info-request/WhatsApp) without a single conversation UI.  
   **Fix direction:** One inbox for clarification requests with status visible to CEO and reviewer.

5. **[intelligence] Signal taxonomy is domain-agnostic**  
   Labels matched keyword friction patterns (`Manual data entry and spreadsheets`, `Approval bottlenecks`) rather than named logistics workflows. Content *triggered* the right buckets (good), but titles would look identical for a bank or a factory.  
   **Impact:** Expert and CEO cannot scan for “demurrage” / “freight billing” in the signal list.  
   **Fix direction:** Domain-aware labeling from document entities or LLM titles grounded in chunk text.

6. **[reviewer_profile] McKinsey experience is not first-class in the PDF**  
   Profile + experiences are rich in portal data; appendix relies on finding body text mentioning McKinsey. No structured “Expert credentials” block pulled from `reviewer_experiences`.  
   **Impact:** Credibility signal underused in the deliverable the CEO downloads.

7. **[dubai_locale] AED / Dubai timezone are fixture-only**  
   Settings include `timezone: Asia/Dubai`, locale stays `en`. Report does not surface AED or UAE framing unless present in free text.  
   **Impact:** Mild for EN demos; weak for bilingual/GCC localization claims.

8. **[ingest] Chunking is shallow**  
   PDF/DOCX/XLSX each produced ~1 chunk (338–610 chars). Enough for keyword signals; thin for RAG citations and long SOPs.  
   **Impact:** Recommendations and report quotes stay high-level.

### Info (working as intended)

- PDF, XLSX, DOCX, TXT all reached `ready` with extractable text.  
- `skip_platform_review: false` + assign-before-generate correctly bootstrapped Nadia’s review.  
- Gated outreach (create → CEO approve → reply) worked end-to-end.  
- Submit requires comment when section is `needs_info` (caught during run; runner now seeds comment).  
- Regenerated PDF ~350KB includes review overlay findings.

---

## Communication & text-generation scorecard

| Surface | Quality | Notes |
|---------|---------|-------|
| Outreach question wording | Good | Specific AED threshold + SOP reference |
| Outreach reply capture | Good | Portal reply recorded as `replied` |
| Discussion → employee | Weak | No employee-authored discussion reply path exercised |
| Exec summary | Poor | Generic + “1 of 0 employees” |
| Signal labels | Fair | Right themes, wrong specificity |
| Reviewer finding prose | Good | McKinsey voice + logistics substance |
| Methodology honesty | Mixed | Docs counted; still discovery-flavored kind/summary |

---

## Checklist (final run)

- PASS: Company provisioned  
- PASS: skip_platform_review false  
- PASS: engagement_mode documents  
- PASS: CEO admin  
- PASS: Documents uploaded (5); ≥4 ready; multi-dept  
- PASS: Intelligence + readiness  
- PASS: McKinsey reviewer + assignment  
- PASS: Finance Controller seeded  
- PASS: Report + review bootstrap  
- PASS: Outreach + discussion Q&A  
- PASS: Findings submit + appendix regenerate  

---

## How to re-run

```bash
docker compose exec rails bundle exec rails scenario:gulflink
# Observations also written to backend/tmp/gulflink_OBSERVATIONS.md (docs mount is read-only in Docker)
```
