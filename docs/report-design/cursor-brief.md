# Brief for Cursor: Redesign the Req discovery report PDF (LANDSCAPE)

## How to use this brief
Attach these three files to the Cursor chat along with this brief:
- `req-report-template-landscape.html`  ← the visual + structural target (open it in a browser first)
- `build_report_landscape.py`           ← how the landscape layout + pages are composed
- `build_report.py`                     ← shared components + the procedural SVG art generators
Then paste the kickoff message (bottom of this file) and work section by section.

## ⚠️ The template is a REFERENCE, not a fixed spec
`req-report-template-landscape.html` shows Req's report **design system** applied to
dummy "Acme Corp" data. Match its *quality and style* — do NOT treat it as a rigid
page-by-page contract.

- **Add, remove, reorder, merge, or split sections** to fit each company's real snapshot.
  No `delta_from_previous`? Drop that page. 15 signals? Paginate them. Empty
  `supporting_media`? Skip it.
- The report must be **data-driven**: a page renders only when its snapshot data exists,
  and content flows naturally across pages.
- What stays constant is the **design language**: the type system, category color-coding,
  exhibit styling, and the cover / contents / divider / split / pull-quote patterns.

## Decided: orientation
**Landscape A4 (297 x 210mm).** This is McKinsey's real widescreen format and what we want.
In the CSS that means `--pw:297mm; --ph:210mm;` and `@page { size:A4 landscape; margin:0; }`.
The landscape file already sets these — port them as-is; do NOT rebuild portrait.

## Goal
Our generated PDF is bland and unstructured. Make it look like a McKinsey "State of
Organizations" report: two-panel cover with generated geometric art, editorial serif
headlines, category color coding, polished exhibits (gauge, lollipop ranking, confidence
donuts, 2x2 matrix, funnel), big stat callouts, hero-left section dividers, text+exhibit
splits, and a pull-quote page. **Presentation only — do not touch the snapshot math or data model.**

## Where this lives in our stack
- `Reports::GenerateReportService` -> `HtmlBuilder` renders ERB at `backend/app/views/reports/document`
- `PdfGenerator` sends that HTML to **Gotenberg** (Chromium) -> PDF
- On approval, `RegenerateWithReviewService` re-renders the same snapshot with a review
  appendix (consultant overall notes + section comments only — NOT live discussions or
  WhatsApp threads; keep that rule).

## Suggested implementation
1. **Shared kit, not one giant ERB:**
   - `reports/_styles.html.erb` — design tokens + print CSS (from the landscape file's <style>;
     it is portrait base CSS + a landscape OVERRIDE block — you can flatten them into one).
   - `reports/_cover_art.html.erb` — the SVG (port the generator, or precompute; see below).
   - one partial per section: `_executive_summary`, `_readiness`, `_participation`,
     `_delta`, `_signals`, `_patterns`, `_recommendations`, `_media`, `_review_appendix`.
   - `document.html.erb` conditionally composes partials based on which snapshot keys exist.
2. **Snapshot -> component mapping** (all shown in the template):
   - `company.name` -> cover meta panel + running footer
   - `readiness.score` -> gauge donut; `readiness.breakdown` -> horizontal bar exhibit (in a `.split`)
   - `participation.{invited,started,completed,completion_rate}` -> funnel + by-department table
   - `signals[]` (label, strength, departments, evidence) -> 3-col signal cards + lollipop ranking exhibit;
     strength drives width, category drives the color class
   - `patterns[]` (title, confidence) -> 3-col pattern cards with confidence donuts
   - `recommendations[]` (title, priority, catalog match, + optional impact/feasibility) ->
     3-col rec cards with priority pill + 2x2 impact/feasibility matrix
   - `delta_from_previous` -> three-column New / Changed / Resolved block
   - `supporting_media[]` -> 3-col media cards
3. **Category color-coding is the key move.** Add a helper mapping each signal/pattern
   category to one CSS class (`cat-process`, `cat-tooling`, `cat-people`, `cat-data`).
   Consistent color = meaning across cards, bars, donuts, and rules.

## Generated cover / divider art
Cover ("eye + sunburst + downward data streams") and the tall divider heroes are
**procedural SVG** (`build_report.py`: `cover_art()`, `build_report_landscape.py`: `hero_tall()`).
Two options:
- Port the generators to a Ruby helper that emits the same SVG, seeded by company id/name
  so each report's art varies slightly, **or**
- Precompute the SVG once and inline it as a partial (simplest; art is static).
Keep it inline SVG so Gotenberg needs no external asset.

## Fonts (important for Gotenberg reliability)
- Display serif **Playfair Display** + body **Inter** (free McKinsey lookalikes).
- **Self-host both as @font-face** (base64 inline or /assets). Do NOT rely on the Google
  Fonts CDN at render time — Gotenberg can snapshot the page before a network font loads,
  giving inconsistent PDFs. The template uses the CDN for preview only.

## Print / Gotenberg specifics (the "make it not look bland" details)
- `@page { size:A4 landscape; margin:0; }`; margins live in `.page` padding.
- Each logical page = a `.page` div with `page-break-after: always`.
- `break-inside: avoid` on every exhibit, stat, and card so nothing splits across pages.
- `-webkit-print-color-adjust: exact` (already set) or backgrounds/colors drop out.
- Footer: keep the in-page footer, OR use Gotenberg's footer.html with page-number tokens
  (`<span class="pageNumber">`). Pick one, be consistent.
- Charts are **inline SVG / CSS only** — no canvas, no JS-timed rendering.
- Keep the HTML fallback path working if Gotenberg fails.

## Acceptance
- Renders end-to-end from a real report_snapshot, pages appearing/disappearing by available data.
- Cover art, contents, a section divider, all exhibit types, and the pull-quote page render correctly.
- Consultant appendix renders on the approval regenerate path.
- Visual language matches req-report-template-landscape.html.
- Verify both seed companies: Acme (approved) and Beta (in-review).

## Kickoff message to paste into Cursor
> We're redesigning our generated discovery-report PDF to look like the attached
> `req-report-template-landscape.html` (a McKinsey-style reference with dummy data).
> Read `cursor-brief.md` fully first. Our pipeline is ERB (`backend/app/views/reports/document`)
> -> Gotenberg (Chromium) -> PDF. This is presentation only — do not change snapshot math.
>
> Start by proposing a plan: the partials you'll create, how `document.html.erb` will
> conditionally compose them from the snapshot, and the category->color helper. Don't write
> code yet — show me the plan and the file list first. Then implement `_styles` + the cover +
> contents, and render the Acme seed so I can review before we do the remaining sections.
