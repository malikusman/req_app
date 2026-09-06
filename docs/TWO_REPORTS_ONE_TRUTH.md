# Two Reports, One Truth

Product analysis of Worktruth report generation, and a proposal for a short executive brief rendered from the same reviewed snapshot as the full report.

*22 August 2026 · read of `backend/app/services/reports/` + `backend/app/views/reports/`*

The discovery report is the product. Today it ships as one 22-page landscape PDF written for a consultant's reading room — and a CEO told us so. The fix is **not a second report**. It's a second projection of the same reviewed analysis, so the two can never disagree.

## What ships today

One `Report` row, one `storage_key`, one PDF. A4 landscape, up to 22 pages, 18 sections.

The generation path is sound and worth stating plainly, because the proposal leans on it: `SnapshotBuilder` assembles a deterministic, evidence-derived snapshot; `NarrativeWriter` layers grounded LLM prose over it and fails safe to the deterministic text; `HtmlBuilder` renders ERB partials; Gotenberg turns that into a PDF. Reviewer edits are a separate overlay applied at render time — the stored snapshot is never mutated.

That architecture is the reason a CEO brief is cheap to build. Everything below is about *what we choose to render*, not about analysing anything twice.

**Current report · A4 landscape, up to 22 pages, in order:** Cover · Contents · Executive summary · Readiness · Company context · Participation · Delta · Divider · Signals · Pull quote · Patterns ×2 · Recommendations ×2 · Roadmap · Opportunities · Tools catalog · Supporting media · Methodology · Appendix divider · Review notes.

### What's genuinely good, and must survive

Four things here are hard to build and easy to break. Any variant work has to preserve them.

- **The hallucination guardrail actually works.** `NarrativeWriter#text_numbers_grounded?` scans LLM prose for currency, percentages, decimals, and ranges, and drops any sentence carrying a figure that isn't traceable to extracted `key_metrics`. A brief that leads with a number needs exactly this.
- **Answer-first structure is already there.** `governing_thought`, `supporting_points`, `stakes`, and per-section action titles exist and are grounded. This is the raw material of an executive brief — it does not need to be written again.
- **Deterministic fallback everywhere.** No model, no key, no problem: the report still generates from real prose. Never regress this.
- **The section-override layer.** Reviewers already hide, replace, and insert sections per `section_key`, applied at render time. This is the exact hook a variant needs.

## Five product problems

The CEO feedback is a symptom of the first one. The others are worth fixing in the same pass.

**01 — One artifact is serving three different readers.** The same PDF goes to the owner who decides, the ops lead who has to act, and — via share link — whoever they forward it to. Those readers want different documents. A 22-page landscape deliverable is built for a laptop or a projector; an owner reads on a phone between meetings and forwards what convinces them. Landscape is the wrong shape for that reader, before a single word is cut. *(Structural — `reports` has one `storage_key`, one `content_type`.)*

**02 — The report opens by justifying our process.** After the summary come Readiness, Company context, and Participation — a score out of 100, firmographics, and an interview funnel. Readiness is our internal go/no-go gate; generation is literally blocked until it hits 100. "12 of 15 employees completed the interview" is our delivery KPI presented as client insight. Meanwhile `key_metrics` — the real cited business numbers like days-to-pay against target — sit below the fold on page three. *(Sections 4–6 of `document.html.erb`; gate in `Company::ReportsController#create`.)*

**03 — "The conversations" is a specific, locatable thing.** The feedback maps to real markup, which makes it easy to act on. Each signal card renders up to three raw interview excerpts; a full page is given to a pull quote; participation is an interview funnel; supporting media lists per-employee evidence cards. That's roughly four pages of primary conversation material. It should not be deleted — it's the credibility layer that makes the findings defensible — but it has no place in a three-minute read. *(`_signals.html.erb` excerpt loop, `_pull_quote`, `_participation`, `_supporting_media`.)*

**04 — Internal review machinery ships to the client.** The appendix is a divider page plus a page of reviewer names, credentials, section dispositions, and structured findings. The trust signal is real and worth keeping — independent expert validation is a differentiator. Two pages of it in a client deliverable is the wrong dose. Compressed to three lines it says the same thing. *(`_review_appendix.html.erb` via `ReviewNotesCollector#overlay`.)*

**05 — The company portal treats the deliverable as a table row.** The report is the entire product value, and the Reports page renders it as row one of a `DataTable` with Version / Status / Generated / What changed. Reading happens in a modal `iframe` at 75vh — a landscape A4 page scaled into a short box, which is close to unreadable. Nothing on the page tells you what the report *found* before you open it. *(`frontend/src/portals/company/CompanyReports.tsx`.)*

## The number that never arrives

Worth its own section, because it's the cheapest high-value fix in this document.

> **Dead end.** An expert types the opportunity value. The report never sees it.
>
> Reviewers enter `opportunity_amount`, `opportunity_unit`, and `opportunity_basis` in the workspace — an expert-validated figure like *AED 450,000/year* with a written basis. It reaches the company dashboard as a stat. It never enters the snapshot, so it appears in no PDF, on no page, in no share link.
>
> `Reviewer workspace → ReportReview row → Company dashboard → ✕ never in the report`
>
> This is the single number an owner most wants, validated by the exact person whose credibility we sell, and it is missing from the deliverable. It should be the largest thing on page one of the brief.

Verified across `backend/app/services/reports/` and `app/views/reports/`: no reference to any `opportunity_*` field. The only consumer is `Dashboard::CompanySummary#opportunity_estimate_json`.

## One snapshot, two projections

The architectural decision that makes everything else safe.

The tempting version of this feature is a second generator that writes a shorter report. That's the version that eventually embarrasses us: two documents, two LLM passes, two sets of numbers, and one day the brief says 40% and the full report says 55%. A CEO forwards the brief; an ops lead quotes the report; the discrepancy surfaces in the room.

So: **one reviewed snapshot, two renderings.** A variant is a section allowlist, a page template, and a paper size — never a second analysis. If a number differs between the two documents, that's a bug with a single cause, not a reconciliation problem.

```
                              ┌──────────────────────────────┐
                              │      Single source of truth   │
                              │ report_snapshot + reviewer     │
                              │ overlay — generated once,      │
                              │ reviewed once, approved once   │
                              └───────────────┬────────────────┘
                                               │
                        ┌──────────────────────┴──────────────────────┐
                        ▼                                              ▼
        ┌───────────────────────────────┐          ┌───────────────────────────────┐
        │ Variant · exec_brief            │          │ Variant · full                  │
        │ Executive brief                 │          │ Full report                     │
        │ A4 portrait · ≤4pp              │          │ A4 landscape · ≤22pp            │
        │ Answer, cost, actions, who      │          │ Unchanged. Every section, all   │
        │ validated it. No excerpts,      │          │ evidence, expert appendix.      │
        │ no methodology, no appendix.    │          │                                  │
        └───────────────────────────────┘          └───────────────────────────────┘
```

**What this needs in the data model.** Today `Report` holds one `storage_key` and one `content_type`. Two options, and I'd take the second:

- *Add `exec_storage_key` columns.* Two hours of work, and it hard-codes "exactly two variants" into the schema. Every future variant repeats the migration.
- *A `report_artifacts` table* — `report_id`, `variant`, `storage_key`, `content_type`, `page_count`, `generated_at`. One `Report` stays one reviewed analysis with N renderings. Download, preview, and share all take a variant parameter. Share links become per-variant, which is a feature in itself: "send the board the brief, not the evidence."

Both `GenerateReportService` and `RegenerateWithReviewService` then loop over variants where they currently upload one file. `PdfGenerator` already takes `paperWidth`/`paperHeight` as parameters, so portrait is an argument, not a rewrite.

**What the reviewer approves.** Unchanged, and this is the point. The reviewer approves the snapshot and their overrides — which they already do per `section_key`. The brief inherits every decision automatically: a hidden section stays hidden, a replaced section's expert text flows through, an unresolved `needs_info` still blocks approval.

One addition is non-negotiable though: the reviewer must be able to *see* the brief before submitting. Four pages is where a weak governing thought does maximum damage — there's no surrounding detail to soften it.

## The executive brief, page by page

Portrait, four pages maximum, content-driven — a thin evidence base yields two pages rather than four padded ones.

**Page 1 — The answer, and what it's worth.** The `governing_thought` as the headline: it is already answer-first, already carries a grounded number, already survives the hallucination filter. Below it, the three `supporting_points` and the `stakes` line. Then the figure that page 1 exists for — the expert-validated opportunity amount and unit, set large, with its basis in one line and the reviewer's name and credential beneath it. No cover page, no table of contents. The document starts by answering.

**Page 2 — Where it hurts.** The top three or four signals as a ranked list: label, strength as a band, departments touched, evidence count. **No excerpts.** Beside it the department heatmap, which is already a single compact SVG and answers "which team" faster than any paragraph. It self-suppresses below two departments, so this page shrinks honestly when the data is thin.

**Page 3 — What to do about it.** The top three recommendations by `impact_score` — title, one line, impact and feasibility as bands, catalog match by name only. Then the Now / Next / Later roadmap, which already exists and is already sequenced. This is the page an owner acts from.

**Page 4 — How we know, and who checked.** The trust page, compressed. One line of method: N interviews across N departments, N documents analysed. Three lines of validation: reviewer name, credential, and that they endorsed the findings. Then the explicit next step, and a pointer that the full report with all evidence is available. This is the whole of Methodology plus the whole of the review appendix, at a dose that persuades rather than pads.

## Section allocation

Every existing section, and where it lands. The "why" column is the part worth arguing about.

| Section | Brief | Full | Reasoning |
|---|---|---|---|
| Governing thought | ✓ | ✓ | The answer. Leads both documents. |
| Opportunity value | ✓ *new* | ✓ *new* | Expert-validated. Currently in neither. |
| Key metrics | ✓ | ✓ | Real cited numbers. Promote above readiness. |
| Signals — ranked | top 4 | all | Ranking is the insight; the long tail is reference. |
| Signal excerpts | — | ✓ | This is "the conversations". Credibility, not brief. |
| Department heatmap | ✓ | ✓ | Answers "which team" at a glance. |
| Recommendations | top 3 | all | An owner acts on three, not nine. |
| Roadmap | ✓ | ✓ | Sequence is decision-grade. Already built. |
| Reviewer validation | 3 lines | full | Trust signal at the right dose. |
| Methodology | 1 line | full page | Owners want that we checked, not how. |
| Readiness score | — | ✓ | Our internal gate, not client insight. |
| Participation funnel | — | ✓ | Our delivery KPI. |
| Company context | — | ✓ | They know their own firmographics. |
| Pull quote | — | ✓ | A full page for one sentence. |
| Supporting media | — | ✓ | Evidence index. |
| Tools catalog | — | ✓ | Procurement detail, post-decision. |
| Agentic opportunities | — | ✓ | Our pitch. Keep it out of their brief. |
| Delta vs previous | — | ✓ | Only meaningful from v2 on. |
| Review appendix | — | ✓ | Internal machinery. Compress on the brief. |
| Cover + contents | — | ✓ | Four pages need no table of contents. |

Eleven sections drop out of the brief and four get compressed. That's how 22 pages becomes four without writing a new sentence of analysis.

## UI/UX — three surfaces change

The brief is worth little if the portal still presents it as a filename.

**1 · Company portal, Reports page.** The latest report becomes the page, not the first row of a table. The governing thought is rendered as real selectable text, so the page answers the question before anything is downloaded. The opportunity figure sits beside it. Then two clearly distinct downloads with honest page counts, because "which one do I want" should never require opening both.

Layout sketch — a hero card, not a table row:

```
┌─────────────────────────────────────────────────────────────┐
│  [Expert validated]                          [v3 · 18 Aug]  │
│                                                                │
│  "Invoice matching runs 11–14 days against an 8-day target,  │
│   and three of four delays start in the same manual PO       │
│   reconciliation step."                                       │
│                                                                │
│  Validated by Dr. Amara Okafor · 14 yrs supply-chain ops      │
│  ─────────────────────────────────────────────────────────   │
│  AED 450,000 / year identified opportunity                    │
│                                                                │
│  [ Executive brief · 4 pp ]  [ Full report · 21 pp ]          │
│  [ Read in browser ]         [ Share… ]                        │
├─────────────────────────────────────────────────────────────┤
│  v2 · 12 Jul 2026 · Two new signals in Finance   Brief · Full │
│  v1 · 03 Jun 2026 · Initial discovery report      Full only   │
└─────────────────────────────────────────────────────────────┘
```

Three specifics that matter more than the layout:

- **Kill the modal iframe for reading.** A landscape A4 page inside a 75vh modal is unreadable. "Read in browser" should be a real route with a page-at-a-time reader and a section jump list — we already render the HTML, so this is a viewer, not a converter.
- **Share becomes per-variant.** "Share the brief" and "share everything" are genuinely different acts. The public share route takes a variant; the copied link is labelled with what it opens.
- **Page counts are stated, not discovered.** Store `page_count` on the artifact at generation. "4 pp" on the button is the whole reason the brief gets clicked.

**2 · Reviewer workspace, PDF drawer.** A segmented toggle in the existing drawer. Same `RegenerateWithReviewService.render_html` call, variant parameter added — the reviewer sees exactly what the owner will see, with their pending edits already applied. Mark the sections that feed the brief with a quiet indicator in the section rail, and relabel the opportunity input from a bare field to *"Appears on page 1 of the executive brief"* — the same data, with the stakes visible.

**3 · Platform approve screen.** Approval ships both artifacts, so both must be previewable at the gate. Same toggle, placed before the approve button. One approval, two documents, one reviewed truth behind them.

## Build sequence

Four phases, each independently shippable. The first is a fraction of the others and delivers the most.

**Phase 0 — Put the opportunity value in the report.** Read the submitted review's opportunity fields into the snapshot, render them on the executive summary page of the report we already ship. No variants, no migration, no new template. Ships on its own and immediately improves the current PDF. *Touches `snapshot_builder.rb`, `_executive_summary.html.erb`. Smallest change in this document; largest single gain.*

**Phase 1 — Variant plumbing.** `report_artifacts` table, a `VariantSpec` holding the section allowlist and paper size, both generate services looping over variants, and download / preview / share taking a variant parameter. No new visual design yet — render the existing full report as the `full` variant and prove nothing regressed. *Migration + `generate_report_service.rb`, `regenerate_with_review_service.rb`, `pdf_generator.rb`, three controllers.*

**Phase 2 — The brief itself.** Four portrait partials and a portrait stylesheet. The type scale is the real work here — the landscape sheet is built for 297mm and its sizes will not survive rotation. Plus the reviewer and platform preview toggles, so nobody approves a document they haven't seen. *New `views/reports/brief/`, portrait `_styles`, reviewer drawer toggle.*

**Phase 3 — Company portal redesign.** Hero card, per-variant downloads with page counts, per-variant share, and a real in-browser reader replacing the modal iframe. Frontend-heavy, no backend dependency beyond Phase 1's artifact fields. *`CompanyReports.tsx` rewrite plus a new reader route.*

## Four decisions

Everything above is buildable as described. These are the calls that are the user's, not mine.

**Separate file, or the first four pages of one file?** A brief that's a prefix of the full report is cheaper — one PDF, one storage key, no variant plumbing at all. **I'd still take the separate file.** The brief's whole job is to be forwarded, and a forwarded PDF must not carry 17 pages of evidence behind it. It also needs portrait, which a prefix can't be.

**Who chooses which variants get generated?** **Nobody — generate both, always.** Adding a variant picker to the generate flow means a company gets the wrong document because of a setting nobody understood. Both are cheap to render from one snapshot; let the reader choose at download.

**Should readiness and participation stay in the full report at all?** Kept them here, but they're arguably both internal metrics wearing client clothing — a gate score and a delivery KPI. Cutting them from the full report too would be a sharper document, and it's a bigger call than the brief.

**The brand mismatch — deliberate or drift?** The app is Pulse: green `#0E9F6E`, Sora and Manrope. The report PDF is a different identity entirely — blue `#1F40FF` with magenta and cyan accents, Playfair Display and Inter. A client uses a green product and receives a blue-and-magenta document. If that's a deliberate consulting-deliverable register, fine — but the new brief will be built in whichever system is named, and building it in the wrong one is expensive to undo.

---

*Read of `backend/app/services/reports/`, `backend/app/views/reports/`, `backend/app/helpers/reports_helper.rb`, `frontend/src/portals/company/CompanyReports.tsx`, and the reviewer workspace. Page counts derived from `.page` blocks in the rendering partials; the reference template in `docs/report-design/renders/` is 11 pages against the live report's 22.*
