# Report-quality session — handoff

**Branch:** `report-and-dashboard-fixes` (pushed). **Goal:** make the generated
discovery PDF credible / McKinsey-grade. All work verified against a real
GulfLink testbed rendered via local Gemma. Full plan: `docs/REPORT_STUNNING_PLAN.md`.

## What we did (commits, newest last)
- `ff8360a` **Step 1 — data integrity.** Replaced the strength formula (hits÷corpus, floored 0.35 → nothing reached "High") with a saturating curve `1-e^(-w/6)`; stopped double-counting evidence (distinct docs + interview msgs + media); negation/relevance-ranked pull-quotes (kills "there are no manual steps" as supporting evidence); case-insensitive department dedupe at every merge site; differentiated recommendation priorities; humanized enums (`MEDIA_ATTACHMENT`, `10m_50m → $10M–$50M`).
- `431f781` **Step 2 — grounded metrics + de-jargon.** New `Reports::MetricExtractor` (deterministic, cited, zero LLM) pulls real business numbers from evidence ("11–14 days vs 8-day target", "1 in 5 fail three-way match"). Snapshot `key_metrics`; "By the numbers" band; deterministic exec lead opens on a metric. NarrativeWriter now gets metrics as the only quotable numbers and strength/confidence as **bands not floats** — kills the "signal strength 0.74" leak.
- `fbe117a` **Step 3a.** Client stack grounded against real evidence text (drops hallucinated Kafka/Elasticsearch/"Analytics platforms"); single-hue heatmap; cover subtitle = governing thought, word-boundary truncation.
- `8af4b8b` **Step 3b.** Print `.page` blank-page fix (10mm margin overflowed the sheet → blank after every page); impact/feasibility 2×2 now spreads (feasibility derived from friction type — spreadsheet=easy, ERP/TMS integration=hard).
- `194336e` Action-title section headers (grounded, deterministic): "Core system dependency is the deepest recurring friction, cited across 9 pieces of evidence".
- `215f535` Corrected pagination (kept `margin:0`, removed fixed height that silently clipped content); tightened exec metric band.
- `47ff876` Removed raw internal scores from signal/pattern cards ("HIGH STRENGTH (0.78)" → "HIGH STRENGTH").

Key files: `backend/app/services/reports/metric_extractor.rb` (new), `snapshot_builder.rb`, `narrative_writer.rb`, `openai/client.rb#report_narrative`, `intelligence/signal_extractor.rb`, `helpers/reports_helper.rb`, `views/reports/_*.html.erb`. 193 service specs green (incl. 4 new MetricExtractor specs).

## Testbed (important)
GulfLink demo data was hollow — **38/40 documents `failed` (`processing_error="purged"`), and all conversation messages were outbound (0 interview answers)**. The old PDF looked "full" only because the buggy math faked evidence. We rebuilt a real testbed (3 ready `.txt` logistics docs + 8 grounded inbound interview answers) so fixes could be verified. Run: `rails scenario:gulflink`; render checks via local Gemma (LM Studio, `google/gemma-4-12b-qat`). Note the narrative writer **fails safe to deterministic prose** when the model errors — that's expected; the metrics band is deterministic and always grounded.

## What to look into next
1. **Page consolidation (deferred — it's a real redesign, not a quick edit).** Report is ~21 pages of thin content. Whitespace is spread across several 3-item-grid sections + two decorative full pages (section divider, dark pull-quote). Per-section capping made it *worse*. Proper fix: merge Signals+Patterns+Implications, shrink/drop the divider + pull-quote pages, move Supporting documents + Methodology into one compact appendix. Plan the section flow before implementing.
2. **Document ingestion is broken locally.** Binary parsing (PDF/DOCX/XLSX/PNG) routes through the LLM and fails with LM Studio ("No models loaded"); only `.txt` survives via a text fallback. This is the upstream reason reports look thin — worth fixing so real uploads produce evidence.
3. **No interview answers captured.** The discovery flow stored only outbound questions for GulfLink. Confirm inbound employee answers actually persist as `Message(direction: "inbound")` in real runs — the signal/metric pipeline depends on them.
4. **System inference hallucinates** (emitted Kafka/Elasticsearch/Tableau not in the docs). We filter them at report time, but fixing the inference service itself would be cleaner.
5. Minor: readiness-breakdown bars render near-empty; roadmap "Later" often empty; a couple of extracted-metric labels are lightly mangled ("< of open demurrage lines").

## Not touched
Dashboard redesign (separate plan on `dashboard-redesign` branch, `docs/DASHBOARD_REDESIGN_PLAN.md`) — analysis only, not implemented.
