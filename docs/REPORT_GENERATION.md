# Report generation — how it actually works

*Code read of `backend/app/services/reports/`, `backend/app/services/report_reviews/`,
`backend/app/services/discovery/build_package_service.rb`,
`backend/app/services/intelligence/`, `backend/app/views/reports/`, and the four
report controllers. 6 September 2026, branch `discovery-consultant-rebuild`.*

---

## 0. Yes, there are two — but not the two you may be thinking of

The word "report" covers two genuinely different artifacts in this codebase, plus
one *proposal* that has not been built. Keeping them apart is the whole point of
this document.

| | **Discovery Package** | **Company Report** |
|---|---|---|
| Model | `DiscoveryPackage` | `Report` |
| Scope | **one employee, one interview** | **the whole company** |
| Audience | the consultant, internally | the client (company owner/ops) |
| Format | database rows, rendered in the consultant portal | **PDF** (A4 landscape, ≤22pp) via Gotenberg |
| Built by | `Discovery::BuildPackageService` → the Python agent | `Reports::GenerateReportService` → 6 collaborating services |
| Trigger | interview finishes (automatic) | a company user clicks Generate (manual, gated) |
| Versioning | `version` per conversation; addendum supersedes | `version` per company; each generate mints v+1 |
| Approval gate | none — it's internal | consultant review **and** platform approval |
| Number of them | one per employee interview | one per company per version |

The Company Report now ships as **two renderings of one reviewed analysis** —
a 4-page A4-portrait *executive brief* and the A4-landscape *full report*. That
is not a third report: both project the same `report_snapshot` and the same
consultant overlay, so they cannot disagree about a number. See
[§10](#10-variants-one-snapshot-two-projections).

---

## 1. The overall shape

```
  EMPLOYEE                    AGENT (Python)              RAILS
  ────────                    ──────────────              ─────
  WhatsApp / web interview ──► LangGraph turn loop ──► messages + conversation_insights
         │                                                    │
         │ dossier_complete                                   │
         ▼                                                    ▼
  Discovery::FinalizeConversationService ─────────┬──────────────────────┐
                                                   │                      │
                        BuildDiscoveryPackageJob   │   AggregateIntelligenceJob
                                   │                                      │
                                   ▼                                      ▼
                    ┏━━━━━━━━━━━━━━━━━━━━━━━┓          company_signals / patterns /
                    ┃  REPORT 1             ┃          recommendations / agentic_ideas
                    ┃  DiscoveryPackage     ┃                            │
                    ┃  (per employee)       ┃                            │
                    ┗━━━━━━━━━━━┳━━━━━━━━━━━┛                            │
                                │                                        │
                    consultant reads it, amends it,                      │
                    states a need → agent drafts a                       │
                    follow-up question → employee answers                │
                                │                                        │
                                └──► new messages ──► re-aggregate ──────┤
                                                                         │
                                        company user clicks Generate     │
                                                    │                    │
                                                    ▼                    ▼
                                        ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
                                        ┃  REPORT 2                         ┃
                                        ┃  Report → report_snapshot → PDF   ┃
                                        ┗━━━━━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━┛
                                                        │
                              consultant review ──► platform approval ──► client
```

The critical structural fact: **Report 1 is an input to Report 2 only indirectly.**
The package itself is never copied into the PDF. What flows through is the
*evidence* — the interview messages, and any answers the consultant's follow-up
questions produced — which the intelligence layer re-aggregates into signals and
patterns, which the snapshot builder then reads. There is no
`discovery_packages → report_snapshot` code path at all.

---

## 2. Report 1 — the Discovery Package

### Entry point

`Discovery::FinalizeConversationService#call`
([finalize_conversation_service.rb:50](backend/app/services/discovery/finalize_conversation_service.rb#L50))
fires `BuildDiscoveryPackageJob.perform_later(conversation.id)`.

Async on purpose — building it makes an LLM call, and the employee's closing
message must not hang on it.

### Flow

```
BuildDiscoveryPackageJob
  └─ Discovery::BuildPackageService.call(conversation:)
       ├─ current_package                      # the version being superseded
       ├─ create_package!(previous)            # status: "generating", version+1
       ├─ fetch_payload
       │    └─ Langgraph::Client#build_discovery_package!
       │         POST /v1/discovery/package  →  agent/app/package.py
       │         inputs: conversation.blackboard, profile, company_name,
       │                 language, last 20 conversation_insights summaries
       ├─ apply!(package, payload)
       │    ├─ recommendation / recommendation_rationale / confidence
       │    ├─ create_items!(kind: "issue")        → discovery_package_items
       │    ├─ create_items!(kind: "solution")     → linked to the issue by title
       │    └─ create_followups!                   → discovery_followup_questions
       ├─ carry_forward_consultant_edits!(previous, package)
       └─ previous.update!(status: "superseded")
```

Files: [build_package_service.rb](backend/app/services/discovery/build_package_service.rb),
[discovery_package.rb](backend/app/models/discovery_package.rb),
`agent/app/package.py`, [langgraph/client.rb](backend/app/services/langgraph/client.rb).

### Content

| Field / table | What it holds |
|---|---|
| `recommendation` | one-line "here's what I'd do" |
| `recommendation_rationale` | why |
| `confidence` | agent's own confidence |
| `generated_by` | `"llm"` or `"deterministic"` (the no-model fallback) |
| `discovery_package_items` kind `issue` | problems found, with `impact` |
| `discovery_package_items` kind `solution` | each `linked_item` → the issue it addresses |
| `discovery_followup_questions` | questions the agent *intends* to ask next, `queue_position` 1 goes out first |
| `agent_payload` | the raw agent response, kept for audit |

### Who can add to it

- **The agent** — everything above, `origin: "agent"`.
- **The consultant** — adds their own issues/solutions with `origin: "consultant"`,
  and rejects agent items (`status: "rejected"`). Both survive regeneration:
  `carry_forward_consultant_edits!` copies consultant-authored items forward and
  re-applies rejections by matching body text.
- **The employee, indirectly** — an addendum reopen mints a new version, which is
  exactly why the carry-forward exists.

Nobody else. There is no platform-user or company-user write path into a package.

---

## 3. Report 2 — the Company Report

### Entry point

`POST /api/v1/company/reports` →
[Api::V1::Company::ReportsController#create](backend/app/controllers/api/v1/company/reports_controller.rb#L35).

Two things happen before anything is generated:

1. **Readiness gate.** `current_company.report_readiness_score < 100` returns 422
   unless `allow_early_report` is set in company settings. Readiness is computed
   by [ReportReadinessCalculator](backend/app/services/report_readiness_calculator.rb) —
   a weighted blend of employees interviewed, departments represented, confirmed
   patterns, and multimodal contributions (or a docs-first variant when no
   interviews exist yet).
2. **Row created** with `version = max + 1`, `status: "queued"`,
   `previous_report` linked, and `visibility` set to `internal_only` unless the
   company has `skip_platform_review`.

Then `GenerateReportJob.perform_later(report.id)`.

### The generation pipeline

```
GenerateReportJob
  └─ Reports::GenerateReportService.call(report:)          [92 lines]
       │
       ├─ report.update!(status: "generating")
       │
       ├─ ① Reports::DeltaCalculator.call(company:, previous_report:)
       │      diffs current signal/pattern/recommendation IDs against the
       │      PREVIOUS report's stored snapshot → new_*, strengthened_signals,
       │      a human summary line. Returns "Initial discovery report" for v1.
       │
       ├─ ② Reports::SnapshotBuilder.call(company:, delta:)   ◄── the heart of it
       │      │
       │      ├─ Intelligence::SnapshotBuilder  → participation, department_coverage
       │      ├─ base_snapshot                  → ~25 deterministic keys (§4)
       │      │    ├─ signals_json              ← company_signals, strength desc
       │      │    ├─ patterns_json             ← patterns, confidence desc
       │      │    ├─ implications_json         ← deterministic "so what" per pattern
       │      │    ├─ key_metrics_json          ← Reports::MetricExtractor (no LLM)
       │      │    ├─ recommendations_json      ← + impact_score & feasibility_score
       │      │    ├─ client_stack_json         ← company_systems, grounded-filtered
       │      │    ├─ tools_catalog_json        ← catalog matches + consultant endorsements
       │      │    ├─ agentic_ideas_json        ← agentic_ideas, published
       │      │    ├─ supporting_media/documents/knowledge_base
       │      │    └─ agent_activity_json       ← which specialist agents ran
       │      │
       │      ├─ apply_narrative!               → Reports::NarrativeWriter (LLM)
       │      │    grounded ONLY on the snapshot; fails safe to nil
       │      │
       │      └─ roadmap ||= deterministic_roadmap   (Now/Next/Later from priority)
       │
       ├─ ③ Reports::HtmlBuilder.call(snapshot:, report_version:)
       │      renders views/reports/document.html.erb through a bare
       │      ActionController::Base subclass (RenderController) so ReportsHelper loads
       │
       ├─ ④ Reports::PdfGenerator.call(html:)
       │      POST multipart → Gotenberg /forms/chromium/convert/html
       │      paperWidth 11.69 × paperHeight 8.27 (A4 LANDSCAPE), zero margins
       │      on failure: raises, UNLESS MocksAllowed → returns the HTML verbatim
       │
       ├─ ⑤ Storage::MinioClient#upload → reports/<company_id>/v<n>/report.pdf
       │
       ├─ ⑥ report.update!(status: "ready", storage_key:, content_type:,
       │                   report_snapshot: snapshot, generated_at:)
       │
       ├─ ⑦ carry_forward_overrides!(previous)
       │      copies the previous version's PUBLISHED ReportSectionOverrides
       │
       └─ ⑧ THE GATE — three-way branch:
              skip_platform_review?     → shared_with_company + platform_approved
                                          + notify_report_ready
              active consultants?       → ReportReviews::BootstrapService
                                          (internal_only, awaiting_consultants)
              neither                   → internal_only + reviews_complete
                                          + notify_platform_report_awaiting_approval
```

Any exception → `status: "failed"`, `error_message` recorded, re-raised.

**A ready report is never automatically shipped to the client.** That is the single
most important line in `GenerateReportService`.

---

## 4. What is actually in the report

`report_snapshot` is the persisted JSON contract. Everything downstream — PDF,
API detail view, delta-vs-next-version — reads from it.

### Snapshot keys → source

| Key | Where it comes from | LLM? |
|---|---|---|
| `generated_at`, `report_kind`, `docs_first_phase` | computed | no |
| `company` | `companies` + `company_profile` (placeholder domains scrubbed) | no |
| `readiness` | `report_readiness_score` + breakdown | no |
| `participation`, `department_coverage` | `Intelligence::SnapshotBuilder` | no |
| `situation` | leads with `metric_lead_sentence` when a real metric exists | no |
| `signals` | `company_signals` — label, strength, departments, evidence_count, department_count. **No raw excerpts.** | no |
| `patterns` | `patterns` — title, description, confidence, linked signal labels | no |
| `implications` | template sentence per pattern | no |
| `key_metrics` | `Reports::MetricExtractor` over document chunks + inbound messages | **no — deliberately** |
| `recommendations` | `recommendations.published.visible_to_company` + computed `impact_score` / `feasibility_score` | no |
| `delta_from_previous` | `DeltaCalculator` | no |
| `executive_summary` | deterministic prose, **overwritten by the LLM narrative when grounded** | maybe |
| `narrative` | `NarrativeWriter` — governing_thought, supporting_points, stakes, implications, roadmap | **yes** |
| `roadmap` | LLM, else `deterministic_roadmap` from priority tiers | maybe |
| `sections` | `ReportSections::DEFINITIONS` (the 7 reviewable keys) | no |
| `evidence_base` | four counts: interviews, documents, media, departments | no |
| `web_research` | public research on the company's own site (max 3 entries) | upstream |
| `client_stack` | `company_systems`, with inferred entries dropped unless the name appears in real evidence | no |
| `tools_catalog` | `CompanyCatalogMatch` + `CatalogEndorsement` (consultant-written) | no |
| `agentic_ideas` | `agentic_ideas.published` | upstream |
| `agent_activity` | `messages.agent_id` counts → which specialists ran | no |

**Note the ratio.** Almost the entire report is deterministic and evidence-derived.
The LLM writes prose *over* it and can only ever replace prose — never numbers,
never a signal, never a recommendation.

### PDF section order

From [document.html.erb](backend/app/views/reports/document.html.erb), in render order:

Cover · Contents · Executive summary · **Expert assessment** · Company context ·
Delta *(only when there are no recommendations)* · Divider · Signals · Patterns ·
Implications · Recommendations · Roadmap · Opportunities · Capabilities ·
Divider · Readiness · Participation · Methodology · Appendix divider · Review appendix.

Consultant-authored sections are injected after whichever section they are
anchored to, so they interleave with the above rather than being appended.

The order follows the pyramid: the answer, the expert's verdict, the findings,
the actions — *then* the method. Readiness (our internal go/no-go gate) and
Participation (our delivery KPI) used to be pages 4 and 6, ahead of the
findings; they now sit in the back matter with Methodology, where a reader who
wants to audit the work will look for them.

Every built-in section is wrapped in the same three-way lambda:

```erb
<% unless report_section_hidden?(snapshot, key) %>
  <%= ai_or_edit.call(key, condition, -> { render "reports/#{key}", ... }) %>
<% end %>
<%= custom_after.call(key) %>
```

That is: *hidden* → nothing; *edited* → the consultant's text **replaces** the AI
section (not a note beside it); otherwise the AI render. Then any consultant-added
custom section anchored after this one.

### The hallucination guardrail

[NarrativeWriter#normalize](backend/app/services/reports/narrative_writer.rb#L79) is
worth reading in full. Two defences:

1. **The model never sees raw scores.** `band()` converts strength/confidence to
   `"high" | "medium" | "low"` before the context is built, so the model cannot
   parrot "a signal strength of 0.74" into client prose.
2. **Every generated sentence is number-checked.** `Llm::GroundedNumbers.grounded?`
   scans for currency, percentages, decimals, thousands and ranges, and drops any
   sentence carrying a figure not traceable to what the writer was given
   (`key_metrics` + signal labels + pattern descriptions + recommendation text +
   deterministic implications + the situation context). A blocked governing
   thought falls back to the deterministic prose rather than shipping a fabricated
   statistic.

And a third, structural: `NarrativeWriter#call` returns `nil` on *any* exception.
No model, no key, model down → the report still generates, from real prose.

---

## 5. Who contributes to the report, and how

Six distinct contributors, in the order they touch it.

### 5.1 The employee — evidence

Never writes to the report. Their interview answers become `messages`, which
`Intelligence::SignalExtractor` mines into `company_signals`, and which
`Reports::MetricExtractor` scans directly for quantified facts (`source: "Interview"`).
Up to three of their raw excerpts appear verbatim per signal card, and one gets a
full page as the pull quote.

### 5.2 Documents and media — evidence

`Multimodal::ParseDocumentService` and `IndexMediaService` each call
`AggregateIntelligenceJob` on completion. Documents also surface directly in the
snapshot (`supporting_documents`, `knowledge_base`) and are the richest source for
`MetricExtractor` — a KPI table row `Label | target | actual` is the single
highest-value metric shape it recognises.

### 5.3 The intelligence layer — the findings

[Intelligence::AggregateCompanyIntelligence](backend/app/services/intelligence/aggregate_company_intelligence.rb)
is the only thing that writes findings. Triggered from five places:
interview completion, document parse, media index, document purge, and analysis runs.

```
SignalExtractor      → SignalUpsertService        → company_signals
PatternDetector      → PatternUpsertService       → patterns
RecommendationSynthesizer → RecommendationUpsertService → recommendations
CompanyStackInferrer                              → company_systems
Catalog::CompanyFitService                        → company_catalog_matches
AgenticIdeaWriter (LLM) ‖ AgenticIdeaSynthesizer  → agentic_ideas
```

Then it refreshes `intelligence_snapshot`, `intelligence_updated_at`, and readiness.
`intelligence_updated_at > report.generated_at` is what makes the company portal
show **"report stale"**.

### 5.4 The company user — trigger and feedback

- Clicks Generate (the only manual trigger).
- Marks a recommendation `not_relevant` / `already_doing` — `visible_to_company`
  filters those out, so company feedback *removes* content from the next version.
- Creates and revokes share links (`Reports::ShareLinkService`).

### 5.5 The consultant — the editorial layer

This is the richest contribution path, and all of it is an **overlay**. The stored
`report_snapshot` is never mutated. Four mechanisms:

| Mechanism | Table | Where it lands in the PDF |
|---|---|---|
| Section override `hide` | `report_section_overrides` | section disappears |
| Section override `edit` | `report_section_overrides` | **replaces** the AI section body |
| Section override `add` | `report_section_overrides` | new custom section after `anchor_section` |
| Section state | `report_review_section_states` | approved states → appendix dispositions |
| Comment | `report_review_comments` | unresolved ones → appendix notes |
| Overall note | `report_reviews.overall_note` | appendix |
| Structured finding | `report_review_findings` | appendix, when `publishable` |
| Catalog endorsement | `catalog_endorsements` | tools catalog section |
| Opportunity sizing | `report_reviews.opportunity_*` | **page 1 of the brief, and the Expert assessment page** |
| Next-version refresh | `Reports::ConsultantRefreshService` | mints v+1 when new evidence lands |

Plus, upstream of the report entirely: consultant-authored discovery package items
and consultant follow-up questions, whose answers become new evidence.

`ReportSectionOverride::BUILT_IN_SECTIONS` lists the 14 editable sections and
carries a comment to keep it in sync with `document.html.erb` — worth remembering
when adding a section.

An edit to `executive_summary` is special-cased in
[SectionOverridesApplier](backend/app/services/reports/section_overrides_applier.rb#L31):
it propagates into the base `executive_summary` field too, because that also feeds
the cover subtitle and contents teaser. Without it the cover would quote the AI
while page 3 quoted the expert.

### 5.6 The platform operator — the ship decision

Approves. Cannot write content. Three hard blocks in
[Platform::ReportsController#approve](backend/app/controllers/api/v1/platform/reports_controller.rb):
consultant reviews incomplete; any review in `needs_info`; or the artifact isn't a
real `application/pdf` (Gotenberg fell back to HTML). Only then does visibility flip
to `shared_with_company` and the client get notified.

---

## 6. The review workflow, end to end

```
report ready
   │
   ├─ ReportReviews::BootstrapService
   │     one ReportReview per active consultant assignment
   │     + one report_review_section_state per ReportSections::KEYS (7)
   │     + notify each consultant
   │     report → awaiting_consultants / internal_only
   │
   ├─ consultant works in the review workspace
   │     marks each of the 7 sections approved | needs_info
   │     writes comments, findings, overall note
   │     writes section overrides (hide / edit / add)
   │     previews live: RegenerateWithReviewService.render_html
   │       → their pending edits applied, nothing stored
   │
   ├─ ReportReviews::SubmitService — refuses to submit unless:
   │     • all 7 sections are approved or needs_info
   │     • overall_note present
   │     • every needs_info section has an explanatory comment
   │     • a publishable "executive_conclusion" finding exists
   │   status ← needs_info if any section is; else approved
   │
   ├─ check_all_submitted! — when every active consultant has submitted:
   │     report → reviews_complete, notify platform
   │
   └─ platform approve
         Reports::RegenerateWithReviewService.call(report:)
           ├─ ReviewNotesCollector#overlay   → notes, dispositions, findings
           ├─ SectionOverridesApplier        → snapshot COPY with overrides
           ├─ HtmlBuilder                    → same template, now with appendix
           └─ PdfGenerator → MinIO (same storage_key, overwritten)
         report → shared_with_company / platform_approved
         notify_report_ready
```

`review_workflow_status` values: `not_required`, `awaiting_consultants`,
`in_review`, `reviews_complete`, `platform_approved`.

### The two render paths

Worth being explicit about, because it's the most confusing part of the code:

| | `GenerateReportService` | `RegenerateWithReviewService` |
|---|---|---|
| When | first generation of a version | at platform approval, and for live preview |
| Builds a snapshot? | **yes** — and persists it | **no** — reads `report.report_snapshot` |
| Delta / narrative / LLM? | yes | **no** |
| Overrides applied? | no | yes, to a deep copy |
| Review appendix? | no | yes |
| Writes to MinIO? | yes | yes (`call`), no (`render_html`) |

So the PDF a client downloads is produced by the *second* service, over a snapshot
produced by the first. `render_html` is the shared preview used by both the
consultant workspace and the platform approve screen — the reviewer sees exactly
what the client will get.

---

## 7. Complete file map

**Entry points**
- [company/reports_controller.rb](backend/app/controllers/api/v1/company/reports_controller.rb) — create (gated), index, show, download, share, revoke_share
- [consultant/reports_controller.rb](backend/app/controllers/api/v1/consultant/reports_controller.rb) — show, download, preview
- [platform/reports_controller.rb](backend/app/controllers/api/v1/platform/reports_controller.rb) — index, pending, download, preview, **approve**
- [public/reports_controller.rb](backend/app/controllers/api/v1/public/reports_controller.rb) — share-token access
- [generate_report_job.rb](backend/app/jobs/generate_report_job.rb)

**Generation**
- [generate_report_service.rb](backend/app/services/reports/generate_report_service.rb) — orchestrator, 92 lines
- [snapshot_builder.rb](backend/app/services/reports/snapshot_builder.rb) — **670 lines, the bulk of the logic**
- [narrative_writer.rb](backend/app/services/reports/narrative_writer.rb) — the only LLM call
- [metric_extractor.rb](backend/app/services/reports/metric_extractor.rb) — deterministic number mining
- [delta_calculator.rb](backend/app/services/reports/delta_calculator.rb)
- [html_builder.rb](backend/app/services/reports/html_builder.rb)
- [pdf_generator.rb](backend/app/services/reports/pdf_generator.rb) — Gotenberg
- [share_link_service.rb](backend/app/services/reports/share_link_service.rb)

**Review overlay**
- [regenerate_with_review_service.rb](backend/app/services/reports/regenerate_with_review_service.rb)
- [review_notes_collector.rb](backend/app/services/reports/review_notes_collector.rb)
- [section_overrides_applier.rb](backend/app/services/reports/section_overrides_applier.rb)
- [report_reviews/bootstrap_service.rb](backend/app/services/report_reviews/bootstrap_service.rb)
- [report_reviews/submit_service.rb](backend/app/services/report_reviews/submit_service.rb)

**Upstream (produces what the report reads)**
- [intelligence/aggregate_company_intelligence.rb](backend/app/services/intelligence/aggregate_company_intelligence.rb) and the 13 services beside it
- [report_readiness_calculator.rb](backend/app/services/report_readiness_calculator.rb)

**Models** — `report.rb`, `report_review.rb`, `report_review_finding.rb`,
`report_review_comment.rb`, `report_review_section_state.rb`,
`report_section_override.rb`, `report_share_access.rb`, `discovery_package.rb`

**Views** — `views/reports/document.html.erb` + 24 partials,
`app/helpers/reports_helper.rb`, `app/constants/report_sections.rb`

---

## 8. Design decisions worth preserving

1. **The snapshot is immutable once written.** Every consultant edit is an overlay
   applied at render time. This is what keeps AI-generated and expert-authored
   content separable and auditable.
2. **Deterministic first, LLM second.** Every LLM path has a real, honest fallback.
   `NarrativeWriter` → deterministic prose. `AgenticIdeaWriter` → `AgenticIdeaSynthesizer`.
   Roadmap → `deterministic_roadmap`. No model, no key, model down: the report
   still generates.
3. **Numbers never come from a model.** `MetricExtractor` is regex over real
   evidence with a `source` on every metric. The model is fed bands, not floats,
   and its output is number-checked.
4. **Nothing ships unreviewed.** The gate in `GenerateReportService` is the load-bearing
   line; `approve` adds three more blocks on top.
5. **Expert work survives regeneration.** `carry_forward_overrides!` (Report) and
   `carry_forward_consultant_edits!` (Package) exist for the same reason and are
   deliberately written as parallels — the code comments cross-reference each other.
6. **Fabricated content is filtered at the source.** `grounded_system?` drops
   inferred systems whose names don't appear in real evidence — a hallucinated
   "Apache Kafka" in the client stack erodes credibility faster than a missing entry.

---

## 9. Known gaps

- **`ReportSections::KEYS` is 7; `BUILT_IN_SECTIONS` is 15.** Consultants can
  override 15 sections but only formally review 7. Not a bug, but the asymmetry
  is easy to trip over: a section can be edited without ever being approved.
- **The scenario runners have no shared-department fixture.** Department
  attribution is covered by a dedicated spec, but `rake scenario:nimbus` still
  asserts `Patterns detected` against whatever its fixture happens to produce.
- **The reader is company-only.** Consultants and platform operators still
  preview in an iframe drawer. They are reviewing rather than reading, so the
  page-at-a-time reader matters less there, but the code is reusable if it does.

### Closed since the first read of this document

- ~~The opportunity value never reaches the report.~~ `Reports::ExpertLayer`
  now carries it into both renderings; it is the largest thing on page 1 of the
  brief.
- ~~One artifact, three readers.~~ Two variants ship from one snapshot.
- ~~The report opens by justifying our process.~~ Readiness and Participation
  moved to the back matter.
- ~~Verbatim interview excerpts, media cards and the document index ship to the
  client.~~ Cut at the snapshot, not just the view.
- ~~Signals carry no department, so the cross-department pattern rule can never
  fire.~~ Fixed — see `docs/SIGNAL_DEPARTMENT_ATTRIBUTION.md` and
  [§13](#13-department-attribution).
- ~~The company portal presents the deliverable as a table row read in a modal
  iframe.~~ The latest report is the page, and reading happens in a real reader
  route — [§14](#14-the-reader).
- ~~Share links are not per-variant.~~ `report_shares` scopes a link to one
  rendering; `reports.share_token` still resolves for links already issued.

---

## 10. Variants — one snapshot, two projections

The tempting version of a short report is a second generator. That is the version
that eventually embarrasses us: two documents, two LLM passes, two sets of
numbers, and one day the brief says 40% while the full report says 55%.

So a variant is **a section allowlist, a page template and a paper size** —
never a second analysis.

```
                    report_snapshot  +  consultant overlay  +  expert layer
                                  (generated once, reviewed once)
                                             │
                        ┌────────────────────┴────────────────────┐
                        ▼                                          ▼
             variant: exec_brief                        variant: full
             reports/brief/document                     reports/document
             A4 portrait · 4pp                          A4 landscape · ~24pp
             answer · value · actions · who             every section + appendix
```

| | `full` | `exec_brief` |
|---|---|---|
| Template | `reports/document` | `reports/brief/document` |
| Paper | `VariantSpec::LANDSCAPE` | `VariantSpec::PORTRAIT` |
| Sections | all | `expert_verdict key_metrics signals patterns recommendations roadmap validation` |
| Storage key | `reports/<co>/v<n>/report.pdf` | `reports/<co>/v<n>/exec_brief.pdf` |
| Also on `reports.storage_key` | yes | no |

Files: [variant_spec.rb](backend/app/services/reports/variant_spec.rb),
[artifact_writer.rb](backend/app/services/reports/artifact_writer.rb),
[report_artifact.rb](backend/app/models/report_artifact.rb),
[brief/document.html.erb](backend/app/views/reports/brief/document.html.erb),
[brief/_styles.html.erb](backend/app/views/reports/brief/_styles.html.erb).

Both `GenerateReportService` and `RegenerateWithReviewService` loop
`VariantSpec::VARIANTS` and hand each rendering to `ArtifactWriter`, which is the
single place that renders → PDFs → uploads → records. The full report stays on
`reports.storage_key` as well as its artifact row, because every existing
download path, share link and approval check reads that column.

`?variant=exec_brief` selects a rendering on the company download, the consultant
preview and the platform preview. No variant means the full report, so every
pre-existing caller behaves exactly as before.

---

## 11. The consultant layer

Three things changed here, all in service of "the consultant's judgement is the
product".

**A section library instead of an empty box.** "Add a section" already worked —
`ReportSectionOverride` action `add`, 15 anchor points. What was missing was
structure. [`ReportSectionTemplates`](backend/app/constants/report_section_templates.rb)
holds the nine sections a real strategy deliverable carries and that an
evidence-driven generator structurally *cannot* produce, because they need
judgement rather than data:

`expert_conclusion` · `assumptions_limitations` · `risks` · `quick_wins` ·
`benchmarks` · `options_considered` · `implementation` · `governance` ·
`next_steps`

Each carries a `purpose` (rendered on the page, so the section explains itself)
and a `scaffold` — a skeleton that poses the questions the section must answer,
so a consultant fills in judgement rather than staring at a cursor. Served at
`GET /api/v1/consultant/section_templates`.

**Consultant pages that look like the product we sell.** They used to render as
`white-space: pre-wrap` plain text on an otherwise blank page — the expert's
contribution looked *worse* than the machine's. `_consultant_section.html.erb`
gives them an accent rail, a credentialed byline, a signature block, and
`report_rich_text`, which renders the scaffolds' light markup (`##` headings,
`-` bullets, `**bold**`, `*italic*`) as real typography. It escapes before
introducing markup, so consultant input can never inject HTML.

**The expert's verdict and their number, on their own page.**
[`Reports::ExpertLayer`](backend/app/services/reports/expert_layer.rb) gathers
the submitted reviews' `opportunity_amount` / `_unit` / `_basis`, the publishable
`executive_conclusion` finding, and every validator's credential. It is folded
into the render-time snapshot copy by `SectionOverridesApplier` — never into the
stored snapshot, for the same reason overrides aren't: reviews are submitted
*after* generation, and the stored snapshot must stay the untouched machine
analysis. Where several consultants each sized the opportunity, the report leads
with the best-evidenced figure and states how many corroborated it, rather than
averaging numbers that were reasoned differently.

**Refresh and reshare.** Evidence does not stop arriving when a report is
reviewed. [`Reports::ConsultantRefreshService`](backend/app/services/reports/consultant_refresh_service.rb)
lets the consultant mint the next version themselves
(`POST /api/v1/consultant/reports/:id/refresh`). Deliberately a new **version**
rather than a re-render: `DeltaCalculator` then states what changed since the
version the client already has, the approved version stays on the record, and
`carry_forward_overrides!` copies their published edits onto the new one so
re-review starts from their work. It refuses when nothing has changed, rather
than burning a version number.

---

## 12. Pagination — why pages had holes in the middle

The symptom: a section would start at the top of a page, then a large blank gap,
then the footer.

The cause was structural, not cosmetic. `.page` was `min-height: 210mm` with
`.footer` at `position: absolute; bottom: 10mm`. A section whose content overran
one sheet grew the div past 210mm, Chromium split it across two sheets, and the
absolutely-positioned footer landed at the bottom of the **second** one — leaving
the hole in between. The signals page was the worst case: it rendered every
signal twice (once as a lollipop chart, again as a card with up to three
excerpts).

Three changes, all in [_styles.html.erb](backend/app/views/reports/_styles.html.erb)
and the partials:

1. **The page is a flex column and the footer sits in flow** with
   `margin-top: auto`, so it is always at the bottom of the page it belongs to.
2. **Long lists are chunked** by `report_paginate(list, per_page)` so a page
   stops overflowing in the first place — signals 6, patterns 3, implications 3,
   recommendations 3, opportunities 3, appendix findings 4, comment groups 6.
   Those numbers are *measured*, not guessed.
3. **Exhibit SVGs get an explicit height** (68mm). They are emitted with
   `viewBox` + `width="100%"` and no height, so the department heatmap rendered
   111mm tall and pushed its page over. `max-height` does **not** clamp a
   viewBox-sized SVG in Chromium's print path — an explicit `height` with
   `width: auto` is required.

`overflow: hidden` was also removed from `.page`: silently clipping a section is
worse than a visible break, and with chunking there should be nothing to clip.

### How to check it stays fixed

Count `.page` sections in the HTML and compare against the real PDF page count.
Equal means no section overflows:

```ruby
report = Report.find(id)
%w[full exec_brief].each do |variant|
  spec = Reports::VariantSpec.for(variant)
  html = Reports::RegenerateWithReviewService.render_html(report: report, variant: variant)
  sections = html.scan(/<section[^>]*class="[^"]*\bpage\b/).size
  pdf = Reports::PdfGenerator.call(html: html, paper: spec[:paper])
  pages = pdf.to_s.scan(%r{/Count\s+(\d+)}).flatten.map(&:to_i).max
  puts "#{variant}: sections=#{sections} pdf=#{pages} #{sections == pages ? 'CLEAN' : 'OVERFLOW'}"
end
```

To find *which* section overflows, render each one alone against the same `<head>`
and check for a page count above 1.

---

## 13. Department attribution

Each signal carries the departments of the evidence that produced it —
`document.department` for matched documents, the interviewee's department for
each kept `source_excerpt`, the exhibit owner's department for matched media.
Corroborating derived text and topic-only inference attribute nothing, because
neither is traceable to one team.

`SignalUpsertService` replaces the stored set on a full-company run (it has seen
all the evidence, so a department whose evidence has gone should drop) and merges
on a department-scoped run (it sees only a slice). `AggregateCompanyIntelligence`'s
`department:` scalar is now advisory.

`PatternDetector` gained two things to make this usable: a lower floor for the
cross-department rule (default 0.2, because that rule reports its own signal's
strength as its confidence rather than asserting a fixed high one), and a cap
(default 3, ranked by spread then strength, because once attribution works
*most* signals span two teams and an uncapped rule emits one near-identical
pattern per signal type).

**Those numbers are a company setting, not a constant.** How readily a pattern
should form is a product-judgement call about false positives on small samples,
so `merged_settings["pattern_thresholds"]` overrides `min_strength`,
`anchor_strength`, `cross_department_min_strength` and `max_cross_department`,
the same way `report_thresholds` overrides readiness. The constants in
`PatternDetector` are the shipped defaults.

`PatternUpsertService` also gained `reconcile_stale`, which it never had — a
pattern detected once lived forever at its historical peak confidence, because
confidence was `[stored, fresh].max` and status was forced to `confirmed` on
every pass. It now takes the fresh value and records material moves in
`patterns.confidence_history` (mirroring `company_signals.strength_history`), so
a pattern that has weakened can still be seen to have been stronger.

Full analysis, the measured before/after, and the reasoning for each judgement
call: `docs/SIGNAL_DEPARTMENT_ATTRIBUTION.md`.

---

## 14. The reader

`GET /api/v1/company/reports/:id/read?variant=` serves the report's **HTML**,
and `/company/reports/:id/read` in the portal is a real reader route:
page-at-a-time navigation, a section jump rail, fit-page / fit-width, and
arrow-key paging.

**Why HTML and not the PDF.** We already render HTML, so this is a viewer rather
than a converter — and the section rail is only possible because the reader can
read the document's own structure. It parses `section.page` elements out of the
loaded frame and labels each jump target from the markup:

- `.eyebrow` is the section name (`Signals`, `Recommendations`), so it is the label;
- except on `.expert-page`, where every eyebrow reads "Expert consultant" and
  four distinct consultant sections would collapse into one target — there the
  `<h1>` is the real section name;
- `<h1>` elsewhere is an *action title* (a McKinsey-style assertion like "Core
  system dependency is the deepest recurring friction, cited across 9 pieces of
  evidence"), which is right for the page and unreadable in a nav rail;
- consecutive pages sharing a label (`Signals`, `Signals · continued`) collapse
  to one target.

On a 29-page report that yields 21 jump targets that read like a table of contents.

**Why the HTML is stored, not re-rendered.** `ArtifactWriter` uploads the exact
markup behind each shipped PDF to `<key>.reader.html` and records it as
`report_artifacts.reader_storage_key`. Re-rendering live would drift the moment
a consultant touched a section override after approval, and could show the client
an edit that was never approved. Storing it is also why the reader shows what the
downloaded PDF shows.

If the reader HTML is missing (a report generated before this existed), the
endpoint 404s with a message pointing at the PDF rather than failing opaquely,
and a failure to store it never fails the report generation — a degraded reader
beats a broken deliverable.

The frame is `sandbox="allow-same-origin"`: the markup is ours, but it carries
consultant-authored text, so it gets no script execution.

### Tested in a real browser

The reader's correctness is browser behaviour, not a pure function — it drives a
same-origin iframe, scales it to fit, and tracks which page is in view. A request
spec can prove the endpoint serves the right HTML; it cannot prove any of that
works. So there is a Playwright suite (`frontend/e2e/report-reader.spec.ts`, 16
tests) covering the jump rail's labels and collapsing, click-to-jump, active
section marking, prev/next, boundary disabling, arrow keys, manual-scroll
tracking, both fit modes, variant switching (including that the brief comes back
portrait), direct-link entry and Escape.

```
docker compose up
docker compose exec rails bundle exec rake e2e:seed_report_reader
cd frontend && npm run e2e
```

The seed task provisions a company whose evidence is strong enough for the real
pipeline to produce a recommendation and a cross-department pattern, plus a
library-authored consultant section and a submitted review with a sized
opportunity — so the reader is tested against a report shaped like a real one.

It earned its place immediately, catching three bugs no unit test would have:

- **`body { overflow: hidden }` in the reader CSS disabled scrolling.** It looked
  right — the reader owns navigation, so why show a scrollbar — but it broke
  `scrollIntoView`, so every jump and every arrow key silently did nothing.
- **The IntersectionObserver used `root: doc.documentElement`.** That measures
  against the whole scrolled document, so every page counted as intersecting at
  all times, no threshold was ever crossed, and the indicator froze on page 1.
  Completely hidden by the buttons, which set the page themselves.
- **The expert layer never reached the portal.** The hero renders
  `snapshot.expert.opportunity`, but the expert layer is applied at render time
  and lives only on the render-time copy — it reached the PDF and no API
  response, so the one number an owner most wants could never appear in the
  portal. `Api::V1::Company::ReportsController#report_json` now merges it into
  the response (never into the stored column).
