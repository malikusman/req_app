# Report Quality Overhaul — Session Log

> **Branch:** `report-quality-overhaul` (cut from `origin/phase-one-launch`)
> **Scope:** Make report generation the crux of the product — genuinely consulting-grade content, an honest docs-only vs interview story, LLM-written narrative + agentic ideas, a real reviewer review/edit loop with live preview, an in-app viewer for the company, and light-touch agent attribution. Plus adjacent platform fixes (catalog products, audit log, Operations consolidation).
> **Verification baseline at end of session:** backend `bundle exec rspec` = **312 examples, 0 failures**; frontend `npm run build` clean; report validated end-to-end against a **local Gemma** model (`google/gemma-4-12b-qat` via LM Studio) and against OpenAI.
> **Totals:** 16 commits, 66 files changed (+2,826 / −375), 4 migrations.

This document explains **what** we changed and **how**, in the order it happened, so anyone (human or Cursor) can pick up the thread.

---

## 0. How to read this

The session ran in two arcs:

1. **Phases 1–4 + catalog rework** — the initial report-quality pass (credibility, the LLM writer, reviewer editorial control), a course-correction on the "owned products" feature, and platform-admin fixes.
2. **Workstreams WS1–WS6** — a deeper, targeted pass on report generation after a fresh current-state analysis: content honesty, LLM agentic ideas, live WYSIWYG preview, company viewer, gate hardening, and agent attribution.

Two cross-cutting principles held throughout:

- **Never fabricate business data.** Every LLM step is grounded strictly in the company's real evidence, fails safe to a deterministic fallback, and only calls the model when a client is genuinely configured (a real key **or** a local endpoint with a dummy key). A production instance without a key never invents content.
- **The stored snapshot is immutable.** Reviewer edits and previews composite onto a *copy* of `report.report_snapshot` at render time, so the AI-generated body and expert edits stay separable and auditable.

---

## 1. Commit-by-commit summary

| # | Commit | Title |
|---|--------|-------|
| 1 | `d5baa3b` | Report Phase 1: credibility and correctness fixes |
| 2 | `c1cad99` | Report Phase 2: LLM analyst/writer step (grounded, with fallback) |
| 3 | `6e3f8fa` | Report Phase 3: reviewer editorial control over the deliverable |
| 4 | `af4128c` | Report Phase 4: owned solutions, fit scoring, and department heatmap |
| 5 | `2246309` | Fix OpenAI base URL when passed as an empty string |
| 6 | `9253eab` | Keep report narrative deterministic in the test suite |
| 7 | `52389ad` | Add report-quality E2E harness + local-Gemma observations |
| 8 | `a80da0a` | Revert company-facing owned-solutions slice |
| 9 | `c94f5c2` | Platform product catalog: first-party flag + reviewer add-from-catalog |
| 10 | `5c72d5c` | Fix audit log filter + consolidate platform ops into Operations |
| 11 | `0856bc4` | Report WS3: content honesty, section clarity, deterministic roadmap |
| 12 | `d79e70f` | Report WS4: LLM-generated agentic AI ideas (tailored) with rule-based fallback |
| 13 | `e22cca4` | Report WS1: live WYSIWYG preview with pending reviewer edits |
| 14 | `ac9b159` | Report WS2: in-app report viewer for the company + freshness states |
| 15 | `e9804bd` | Report WS5: harden reviewer submit gate + one-click edit preview |
| 16 | `2e1d876` | Report WS6: show the discovery agents (light-touch attribution) |

---

## 2. The report pipeline (mental model)

Understanding the flow makes the rest legible:

```
Intelligence (signals / patterns / recommendations / agentic ideas / catalog matches)
      │
      ▼
Reports::SnapshotBuilder  ──► builds a plain Ruby Hash "snapshot"
      │     • deterministic sections (readiness, participation, signals, patterns, …)
      │     • NarrativeWriter (LLM) overrides exec summary + implications + roadmap
      │     • agent_activity, owned/first-party catalog, agentic ideas
      ▼
Reports::HtmlBuilder  ──► renders app/views/reports/document.html.erb (+ partials)
      │
      ▼
Reports::PdfGenerator ──► Gotenberg (HTML → PDF)  ──► MinIO
```

- **Generation** runs in `Reports::GenerateReportService` (a Sidekiq job). The full snapshot is stored on `report.report_snapshot`.
- **Reviewer edits** (`ReportSectionOverride`) and reviewer notes/findings are applied at **regenerate / preview** time via `Reports::SectionOverridesApplier` + `Reports::ReviewNotesCollector` — never mutating the stored snapshot.
- **Platform approval** triggers `Reports::RegenerateWithReviewService`, which re-renders the stored snapshot **with** the reviewer overlay and re-uploads the artifact.

Key files:
- `backend/app/services/reports/{snapshot_builder,html_builder,pdf_generator,generate_report_service,regenerate_with_review_service,section_overrides_applier,review_notes_collector,delta_calculator}.rb`
- `backend/app/views/reports/*.html.erb`
- `backend/app/helpers/reports_helper.rb`

---

## 3. Phase 1 — Credibility & correctness (`d5baa3b`)

**Problem:** The report looked premium but had trust-destroying content bugs.

**What we did:**
- **Grounded the impact/feasibility 2×2 matrix in real data.** It previously computed axis positions from the loop index (`impact = 80 - (i%3)*5`) — a fabricated exhibit. `snapshot_builder.rb#recommendations_json` now computes a real `impact_score` (evidence weight from linked signals) and `feasibility_score` (effort + whether it extends an existing system); `reports_helper#report_priority_matrix_svg` plots those, and falls back to a priority-ordered list when the scores are absent (never invents positions).
- **Killed data-hygiene leaks:** humanize/hide the `other` industry enum, drop placeholder websites (`example.com`), dedupe `region`+`country`, strip internal debug strings (`tag_match:…`) from catalog reasons.
- **Honored `report_kind`** (Baseline vs Discovery) on the cover tag, page `<title>`, and footer (was hardcoded "Discovery").
- **Plain-language strength/confidence bands** (High/Medium/Low) with the raw decimal as secondary.
- **Real evidence quotes** on signal cards instead of implying inflated counts.
- **Fixed the pattern category** derivation (was a byte-hash of the title that mislabeled "Approval bottleneck" as "Data") to use signal type/keywords.
- **Surfaced real reviewer credentials** in the validation appendix (was a hardcoded "Expert reviewer").
- **Honest readiness bars** — show `3/3` raw/target instead of everything reading 100%.

---

## 4. Phase 2 — LLM analyst / writer step (`c1cad99`)

**Problem:** The entire report narrative was deterministic string-concatenation ("Mad-Libs") — no analyst voice.

**What we did:**
- Added `Reports::NarrativeWriter` + `Openai::Client#report_narrative`: a grounded LLM pass that produces a **pyramid-principle executive summary** (governing thought → supporting points → stakes), quantified-but-hedged **implications**, and a phased **Now/Next/Later roadmap**.
- **Strict grounding:** the prompt forbids inventing facts/numbers/ROI and requires the pyramid structure. Context is a compact JSON of the real snapshot evidence (no PII).
- **Fail-safe:** any error/blank/disabled → `nil` → the honest deterministic prose stays. Only calls the model when `Openai::Client#configured?`.
- **Local-model support:** works with Gemma/LM Studio/Ollama via `OPENAI_BASE_URL` + a dummy `OPENAI_API_KEY`. Flags: `AI_REPORT_NARRATIVE` (default on), `REPORT_MODEL` (defaults to `OPENAI_MODEL`).
- Wired into `SnapshotBuilder#apply_narrative!`: the LLM output overrides the executive summary + implication statements; the new `_roadmap` partial renders from it.

---

## 5. Phase 3 — Reviewer editorial control (`6e3f8fa`)

**Problem:** Reviewers could only append an appendix — they had no control over the report body.

**What we did:**
- New model **`ReportSectionOverride`** (`hide` / `edit` / `add`), with a reviewer CRUD endpoint.
- `Reports::SectionOverridesApplier` applies overrides to a **copy** of the stored snapshot at regenerate time; `document.html.erb` honors hide/edit/add and the TOC drops hidden sections.
- Reviewer workspace "Report sections" step gained a **Section editor** panel (hide toggles, add editorial note, add a whole custom section anchored after any built-in section, with reviewer attribution).
- Migration `20260802130000_create_report_section_overrides.rb`.

---

## 6. Phase 4 → course-correction: owned products became platform products

This is the most important design change in the session.

### 6a. Phase 4 as first built (`af4128c`) — later reverted
Originally implemented a **company-facing** "Owned solutions" page (the *company* registers what they own), a description-aware fit service, a report section, and reviewer endorsement. Also added the **department × friction heatmap** exhibit (kept).

### 6b. The correction (`a80da0a` revert, `c94f5c2` rebuild)
Stakeholder clarified the real requirement: **the platform** uploads *their* products (a mix of first-party built products + curated third-party tools); the system assesses fit per company during analysis/report; **reviewers** can add products to a company's list; the **company admin does not** manage this.

So we:
- **Reverted** the company-facing slice (page/nav/route, company + reviewer `owned_solutions` controllers, `OwnedSolutionFitService`, `_owned_capabilities` partial, and the `company_systems` owned-solution columns via `20260802150000`). Kept the heatmap and pre-existing build fixes.
- **Rebuilt on the existing Solution Catalog** (`SolutionCatalogEntry`), which already supported rich descriptions + per-company fit (`CompanyFitService` → `CompanyCatalogMatch`) + reviewer endorsement:
  - Added a **`first_party`** flag (platform marks their own products; reports badge them "Worktruth product"). Platform Solutions form gained a toggle. Migration `20260802160000`.
  - Added **reviewer "add product from catalog"**: `catalog/available` (browse catalog, first-party first, excludes already-matched) + `catalog/add` (create a `CompanyCatalogMatch`, attributed via `added_by_reviewer_id`). Reviewer catalog page gained an "Add a product" panel; the report tags reviewer-added items "Added by reviewer".

**Net:** the three report sections that recommend things are now distinct (see §11): Recommendations (actions), Opportunities (agentic AI we'd build), Capabilities (existing products that fit).

---

## 7. Infrastructure fixes discovered while testing

### 7a. `2246309` — OpenAI base URL empty-string bug (important)
`docker-compose` passes `OPENAI_BASE_URL: ${OPENAI_BASE_URL:-}` (an **empty string** when unset), and `ENV.fetch("OPENAI_BASE_URL", DEFAULT)` treats present-but-blank as a real value → a `""` base URL → `"not an HTTP URI"` on every live call. This had been **silently breaking all live OpenAI calls in Docker** (the narrative and other LLM steps quietly fell back). Fix: `chat_base_url`/`embedding_base_url` now treat a blank env as unset and use the OpenAI default. Local-model profiles that set a real URL are unaffected.

### 7b. `9253eab` — deterministic tests
With the base-URL fix, the narrative writer started making live `chat/completions` calls in specs whenever `OPENAI_API_KEY` is present (dev containers), which WebMock blocks with a non-`StandardError` that escapes the writer's rescue. `spec/support/report_narrative.rb` now disables `AI_REPORT_NARRATIVE` (and later `AI_AGENTIC_IDEAS`) by default in the suite; the writer specs opt back in and stub the client.

### 7c. `52389ad` — E2E harness
`docs/manual-test/report-quality-e2e.rb` — a self-checking runner that drives the full report pipeline against a local OpenAI-compatible model and verifies all phases + the deterministic fallback. Recorded a 23/23 pass against `google/gemma-4-12b-qat`.

### 7d. `5c72d5c` — audit log + Operations consolidation
- **Audit log fix:** the controller filtered on `params[:action]` — a **reserved Rails routing key** that is always the controller action name (`"index"`), so every query degraded to `where(action: "index")` and returned nothing. Now reads `request.query_parameters[:action]`. Verified: 18 rows return unfiltered, filtering works. (The write path and ~14 write-sites were already correct; the page was just always empty.)
- **Operations consolidation:** System, Monitoring, Trials, and Audit log merged into one **Operations** sidebar item with tabs; old routes redirect to `/platform/operations?tab=…`.

---

## 8. WS3 — Content honesty, section clarity, roadmap fallback (`0856bc4`)

After a fresh current-state analysis, we fixed where the report told the story dishonestly.

- **Mode-aware evidence language.** Baseline (docs-only) reports no longer claim "documents, interviews, and media" on signal/pattern cards or name-drop "specialist interview agents" in methodology — that wording is gated on discovery mode.
- **Participation funnel** is hidden on a pure document baseline (shows only when an interview actually completed, or a hybrid engagement is live).
- **Section numbering:** stripped the inconsistent hardcoded in-body eyebrow numbers (two "08"s collided); the TOC keeps dynamic numbering.
- **The three "solution" sections got explicit roles** (see §11) with framer lines that stop the "same product listed twice" confusion.
- **Roadmap always renders now:** LLM-written when available, else a deterministic Now/Next/Later derived from recommendation priority (`snapshot_builder#deterministic_roadmap`). The snapshot exposes a top-level `roadmap` key consumed by the partial, TOC, and document gate.

---

## 9. WS4 — LLM-generated agentic AI ideas (`d79e70f`)

**Problem:** The "Agentic AI we'd build for you" section was 100% templated Mad-Libs ("An agentic workflow that monitors 'X' and assists teams…"), `estimated_cost` always nil, "confidence" just re-labeled signal strength.

**What we did:**
- `Intelligence::AgenticIdeaWriter` + `Openai::Client#agentic_ideas`: an LLM pass that proposes **specific, company-grounded** agentic-AI concepts from the real signals/patterns/stack — named, buildable, linked to the signals they target, with qualitative value (no invented ROI) and honest confidence.
- **Fail-safe:** only calls the model when configured; on any error/disabled/empty it falls back to the deterministic `AgenticIdeaSynthesizer`. Gated by `AI_AGENTIC_IDEAS`.
- Ideas persist as **drafts** via the existing upsert (never clobbering human-edited rows) and publish through the existing review flow.
- **Verified live on Gemma:** produced tailored ideas — e.g. *"Approval Velocity Agent"* (nudges stakeholders on SLAs), *"Spreadsheet-to-System Sync Agent"* — that reference the company's actual stack.

---

## 10. WS1 — Live WYSIWYG preview (`e22cca4`)

**Problem (the biggest UX hole):** reviewers authored section edits **blind** — the "preview" only showed the already-generated stored PDF, and the platform approver approved edits sight-unseen.

**What we did:**
- Extracted `Reports::RegenerateWithReviewService.render_html` — composites the stored snapshot + `SectionOverridesApplier` + review overlay into HTML **without storing anything**.
- New reviewer + platform `preview` endpoints return that live HTML.
- Reviewer report drawer gained a **"With your edits" / "Stored PDF"** toggle, refetched each open so it reflects the latest overrides.
- Platform approval panel gained a **"With reviewer edits" / "Current artifact"** toggle so approval is no longer sight-unseen.
- Verified: the preview applies a pending add/hide while leaving the stored snapshot untouched.

---

## 11. The three "solution" sections — now distinct

A recurring reader-confusion problem: three visually identical grids all "recommended things." They now have unmistakable roles:

| Section | Role (heading + framer) | Data source |
|---------|--------------------------|-------------|
| **Recommendations** | *"What to do"* — prioritized actions; names a matched tool, full product view follows in Capabilities | `Recommendation` records (catalog-matched) |
| **Opportunities** | *"Agentic AI we'd build for you"* — tailored concepts we'd design/build | `AgenticIdea` (now LLM-generated) |
| **Capabilities & evidence** | *"Products that already fit"* — our first-party products + partner tools, reviewer-endorsable | `CompanyCatalogMatch` (+ endorsements, supporting docs) |

First-party matches badge as **"Worktruth product"**; reviewer-added matches badge **"Added by reviewer"**.

---

## 12. WS2 — Company in-app viewer + freshness (`ac9b159`)

The company (the customer) was the only role without an in-portal viewer — they could only download the PDF.
- **"View"** opens the report inline in a modal iframe (company download now supports `inline` disposition).
- Surfaced the freshness signals the API already returned but the page discarded: a **"report is generating"** banner and a **"your intelligence changed since the latest report"** staleness banner.
- Removed the dead hardcoded "Availability = Shared" column; renamed "Delta" → "What changed".

---

## 13. WS5 — Reviewer submit gate + edit preview (`e9804bd`)

- **Disable "Submit review"** until the reviewer's own requirements are met (all sections reviewed + overall conclusion saved), with a hint — the gate was previously soft (always enabled).
- Added a **"Preview with edits"** button in the section editor that opens the live draft preview, tightening the edit → see loop.
- *Deferred (lower value now that live preview exists):* full section reorder; unifying catalog/agentic endorsement into the workspace.

---

## 14. WS6 — Show the discovery agents (`2e1d876`)

**Problem:** the multi-agent discovery system contributed nothing visible to the report, and methodology slightly misrepresented how findings are made.

**What we did (light-touch, honest):**
- `snapshot_builder#agent_activity_json` aggregates which specialist agents actually ran, from `messages.agent_id` (`domain_<dept>` / `process` / `technical` / `strategic` / `compliance`) with turn counts — read-only over existing data, no new plumbing.
- Rendered in Methodology for discovery reports: *"Discovery agents engaged: Domain specialist (finance) 4 turns; Process specialist 4 turns; …"*. Shows nothing when there's no agent activity (honest), and only on discovery reports.
- Verified on `scenario-corp` (real multi-agent discovery).

*Deferred:* heavy per-finding agent attribution (would require threading agent provenance from the blackboard → signals → snapshot).

---

## 15. Testing & local-model notes

- **Suite:** `docker exec req_app-rails-1 bundle exec rspec` — 312 examples, 0 failures at session end. Frontend `npm run build` clean.
- **New specs:** `narrative_writer_spec`, `agentic_idea_writer_spec`, `section_overrides_applier_spec`, `owned_solution_fit_service_spec` (from the reverted slice), reviewer `catalog_add_spec`, plus the report service specs.
- **Local Gemma testing** (`.env` Profile B): `OPENAI_BASE_URL=http://host.docker.internal:1234/v1`, `OPENAI_API_KEY=lm-studio` (any non-empty value enables `configured?`), `OPENAI_MODEL=google/gemma-4-12b-qat`, `OPENAI_JSON_MODE=false`, `OPENAI_MAX_TOKENS=2500`, and add `OPENAI_READ_TIMEOUT=300` (Gemma narrative ≈ 90s, agentic ideas ≈ 175s — fine for a background job). After switching profiles, restart `rails` + `sidekiq` (Sidekiq caches env/code).
- **Flags:** `AI_REPORT_NARRATIVE`, `AI_AGENTIC_IDEAS` (both default on; set `false` to force deterministic), `REPORT_MODEL` (defaults to `OPENAI_MODEL`).
- **E2E harness:** `docs/manual-test/report-quality-e2e.rb` (copy to `backend/tmp/` and `rails runner /app/tmp/…`).

---

## 16. Env vars introduced / relied on

| Var | Purpose | Default |
|-----|---------|---------|
| `AI_REPORT_NARRATIVE` | Toggle the LLM executive summary / roadmap | `true` |
| `AI_AGENTIC_IDEAS` | Toggle LLM agentic-idea generation | `true` |
| `REPORT_MODEL` | Model for report narrative + agentic ideas | `OPENAI_MODEL` |
| `OPENAI_BASE_URL` | OpenAI-compatible endpoint (blank = OpenAI default, post-fix) | OpenAI |
| `OPENAI_READ_TIMEOUT` | HTTP read timeout (raise for slow local models) | `120` |

---

## 17. What's deliberately deferred

- **Section reorder** for built-in sections (custom-section placement works via anchors).
- **Unifying catalog + agentic endorsement into the reviewer workspace** (still lives on separate reviewer pages).
- **Full version-compare** for the company (they now get the "what changed" summary + in-app viewer; not a side-by-side diff).
- **Heavy per-finding agent attribution** (WS6 is the light-touch version).

---

*Session captured for handoff. Branch `report-quality-overhaul`; latest commit at time of writing `2e1d876`.*
