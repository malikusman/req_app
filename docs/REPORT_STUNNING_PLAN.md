# Making the Discovery Report Stunning — Plan

> **Branch:** `report-and-dashboard-fixes`.
> **Goal:** Turn the generated discovery PDF from "polished template on broken data" into a credible, McKinsey/BCG-grade deliverable for SME leadership — using our real evidence plus grounded LLM content, and consulting-grade visuals.
> **Grounded in:** (1) the root-cause analysis of the current PDF, and (2) online research on top-tier consulting reports + safe LLM report generation.

## Principles (from research)

- **Answer-first (Pyramid Principle).** Lead with the conclusion; every section headline is an **action title** — an assertion with a number and a "so what," not a topic label. Reading the titles alone should tell the story.
- **MECE + one message per section.** Detail lives in an **appendix**, not the narrative.
- **Chart follows analytical logic, not aesthetics.** Waterfall for deltas, 2×2 for positioning, sorted bars for comparison, heatmap for concentration, roadmap for sequence, process/value-stream map for bottlenecks.
- **Visual restraint.** One accent colour + neutrals; red reserved for negatives/risk; asymmetric ⅔ exhibit / ⅓ interpretation; minimal decoration; footnoted sources.
- **Safe LLM.** Grounded summarization/extraction (<2% hallucination) via a structured output schema with required `confidence` + `sources`; empty sources → drop the claim; layered guardrails; fail-safe to deterministic prose.

Order matters: **fix the data first** — stunning exhibits on wrong numbers still lie.

---

## Step 1 — Data integrity (prerequisite)

| # | Defect | Root cause | Fix |
|---|--------|-----------|-----|
| 1a | Duplicated case-variant departments ("Finance, finance") | case-sensitive `.uniq` at merge sites | canonicalize+dedupe by `downcase`, keep a titleized display form — `signal_upsert_service.rb`, `pattern_upsert_service.rb`, heatmap helper |
| 1b | Everything reads Medium/Low; nothing High | strength = hits ÷ whole corpus, floored 0.35 | replace with a saturating absolute-evidence curve so strong signals reach High — `signal_extractor.rb` |
| 1c | "MEDIUM (0.45) · 163 evidence" contradiction; pattern "284 evidence" | evidence_count = raw hits (ratio numerator); messages double-counted; patterns re-sum inflated per-signal counts | make evidence_count a capped, de-duplicated count of distinct evidence; patterns sum distinct evidence |
| 1d | Contradictory pull-quote ("there are no manual steps") | excerpt selection = regex-match + recency, no relevance/negation handling; pull-quote = `.first` | rank excerpts by relevance, drop negations/self-intros; pull-quote picks best |
| 1e | Raw enums: "MEDIA_ATTACHMENT", "10m_50m" | helper reads `source` not `attachment_type`, no uniq; no reverse revenue map | humanize + uniq media labels; add `report_revenue_band_label` |
| 1f | All recommendations "MEDIUM PRIORITY" | high gate needs strength ≥ 0.8 (unreachable) | lower/high + add low branch (resolves once 1b lands) |
| 1g | Fit % 6–8% shown to client | additive score printed raw as %; dept dupes inflate tag denominator | dedupe tags in matcher; normalize fit to a real band (fixed largely by 1a) |
| 1h | `" . ."` artifacts in reasons | `report_clean_reason` leaves orphan period | collapse orphan `. .` |

**Acceptance:** a discovery report shows deduped departments, at least one High-strength signal, evidence counts consistent with strength, human media labels, a relevant pull-quote, differentiated recommendation priorities, and no raw enums.

## Step 2 — Report Analyst agent (grounded LLM content)

Upgrade `Reports::NarrativeWriter` into a grounded **Report Analyst** pipeline (structured JSON, `confidence`+`sources` per claim, empty-sources → drop, fail-safe to deterministic):

1. **Metric extraction** — pull `{metric, value, unit, source_id}` from the real evidence (e.g. "~2 hrs/day pasting CargoWise CSVs", "11–14 days to pay vs target 8", "demurrage holds > 48 h"). Cited, never invented. Surfaces the quantification a CEO expects.
2. **Action titles** — per-section assertion + one-line "so what" from grounded data, replacing topic labels.
3. **Opportunity sizing/scoring** — impact × feasibility × confidence per opportunity from evidence weight + stack fit (grounds the 2×2 and ranking; also fixes the mixed-boilerplate opportunities by making the writer authoritative and reconciling stale generated ideas).

**Acceptance:** exec summary + each major section carry a quantified action title tied to a real source; opportunities are all-tailored; every LLM claim traces to evidence or is dropped; deterministic fallback intact.

## Step 3 — Exhibits + layout

- **New: bottleneck / value-stream map** — invoice → approval → SAP with the real cycle-time annotation ("11–14 days, target 8"). The signature ops-diagnostic exhibit.
- **New: waterfall / "where the hours go"** — from extracted metrics (time or cost-of-inaction bridge).
- **Fix: heatmap** — real per-cell intensity (kill the uniform-colour + duplicate-row bugs).
- **Restraint pass** — one accent + neutrals, red only for risk; asymmetric ⅔/⅓ layouts; footnoted sources.
- **Structure → MECE** — merge Patterns+Implications; move Methodology, Supporting media, and full catalog to an **appendix**; trim from 14 sections.
- **Print CSS** — fix blank pages / split exhibits (`.page` fixed print height, zero print margin, group header with content, add `.media-card` to break-avoid), the floating drop-cap (drop-cap out of multicol), mid-word breaks (`hyphens`/`overflow-wrap`), cover subtitle word-boundary.

**Acceptance:** no blank/half pages, no split exhibits, no floating glyphs; a bottleneck map + waterfall render from real data; ≤ ~10 body sections with detail in an appendix.

---

## Sequence & testing
1 → 2 → 3, each independently shippable, verified with `rspec` (0 failures) and a **local Gemma** end-to-end render. Fail-safe paths keep the report generating without a model.
