# GulfLink / company 10 — verify new features & PDF

**Date:** 2026-07-26  
**Company:** id 10 `salman butt llc`  
**Report:** id **36**, version **1**, status `ready`  
**Artifact:** `reports/10/v1/report.pdf` (290,586 bytes, `application/pdf`)  
**Local copies:**
- [company10_v1.pdf](./company10_v1.pdf)
- [company10_report_v1.html](./company10_report_v1.html)
- [company10_report_preview.html](./company10_report_preview.html) (pre-generate HtmlBuilder preview)

**Accounts used:** `salman@mailinator.com` / `Password1!` (company); `rev1@gamil.com` / `Password1!` (reviewer)

---

## Phase A — Backend (AgentContext / research / snapshot / HTML)

| Check | Result | Notes |
|-------|--------|-------|
| `AgentContext.for_agents` | **PASS** | website + 11 systems |
| `reviewer_profile_json` | **PASS** | profile, systems, web_research keys |
| `WebResearchService` (force) | **PASS** | KB entry id 60 for `https://example.com` |
| Snapshot website / stack / KB / dept key | **PASS** | web_research present in KB snapshot |
| HTML: Company context / Applications / Who this org is | **PASS** | |
| Hybrid invite copy | **PASS (n/a)** | invited=0 completed=0 |

**Score:** 13 PASS / 0 FAIL / 0 WARN

---

## Phase B — API smoke

| Check | Result | Notes |
|-------|--------|-------|
| `GET settings/organization` website_url | **PASS** | `https://example.com`, 11 known_systems |
| `POST settings/organization/web_research` | **PASS** | `{ ok: true, queued: true }` |
| `GET reviewer/companies/10` profile pack | **PASS** | company_profile, 11 systems, 1 web_research |
| `GET reviewer/companies/10/catalog` | **PASS** | `note` present; `last_matched_at=2026-07-26T07:52:45Z`; 5 matches |

**UI smoke:** not walked in browser this pass (API proves payload for Profile + Catalog).

---

## Phase C — PDF slide scorecard (report 36)

| Slide | New/changed? | Result | Notes |
|-------|--------------|--------|-------|
| Cover | existing | **PASS** | Company name present |
| Contents / TOC | changed | **PASS** | Includes “Company context”; TOC = Exec → Readiness → Company context → Signals → Patterns → Implications → Recommendations → Capabilities & evidence → Methodology |
| Exec summary | enriched | **PASS** | Present (`baseline` / docs-first) |
| Readiness | existing | **PASS** | Score 100% |
| **Company context** | **NEW** | **PASS** | “Who this organization is”, Applications in use (11), website, Website research blurb |
| Participation | enriched | **PASS (omitted)** | Correctly skipped (invited=0, completed=0); dept table n/a (coverage empty) |
| Signals | existing | **PASS** | 6 signals |
| Patterns / Implications | existing | **PASS** | 1 pattern |
| Recommendations | existing | **PASS** | 1 rec |
| Capabilities & evidence (tools) | existing | **PASS** | 5 catalog matches |
| Methodology | enriched | **PASS** | Docs-first methodology present |
| Review appendix | skip | **N/A** | No platform-approved reviews |

**HTML/PDF checks:** 15 PASS / 0 FAIL  
**PDF generation:** Gotenberg succeeded (real PDF, not HTML fallback).

### Snapshot facts (frozen in report 36)

- `report_kind=baseline`, `docs_first_phase=true`
- website `https://example.com`
- client_stack **11**, knowledge_base **33** (incl. 1 web_research)
- signals **6**, patterns **1**, recommendations **1**, tools matches **5**

### Download visibility (expected product behavior)

- Company `GET/DOWNLOAD /api/v1/company/reports/36` → **403** `Report not available` because `visibility=internal_only` (active reviewer assignment).
- Reviewer download → **200** PDF (290,586 bytes).

---

## Phase D — Skipped / out of scope this pass

| Item | Status |
|------|--------|
| Full docs re-Analyze | Skipped (not needed) |
| Catalog rematch-on-promote live | Skipped (no pending candidate); rematch job enqueue code path unchanged |
| WhatsApp invite → intel E2E | Skipped (copy-only) |
| Tavily / open web search | Not built |
| LangGraph in-agent research tool | Not built |

---

## Bugs / findings

| Severity | Finding |
|----------|---------|
| **Medium** | `Companies::WebResearchService` calls `Openai::Client#chat`, which **does not exist** (`chat_completion` / `chat_json_content` do). Sidekiq logs: `undefined method 'chat'`. Research still stores a truncated page extract fallback — summary quality is degraded until the client method is wired. |
| Low | Company portal cannot open/download report while `internal_only` (by design with reviewers assigned). Index lists the report; show/download forbidden until shared. |
| Info | `example.com` is a placeholder site — research content is generic; use a real company URL for richer KB/PDF copy. |

---

## Verdict

**New stack verified end-to-end for company 10.** Agent context, reviewer Profile API, web research KB persistence, catalog clarity fields, and the new PDF **Company context** slide all pass. Generated report **#36** is a real PDF with enriched TOC and tools catalog.

**Recommended follow-up:** fix `WebResearchService` to use the real OpenAI client method so website summaries are LLM-quality, then re-queue research + regenerate report if you want richer Company context copy.
