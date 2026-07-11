#!/usr/bin/env python3
"""Landscape (widescreen) variant of the Req report — McKinsey's actual format.
Reuses art generators, dummy data, and components from build_report.py; only the
page geometry and layout grids change."""
import math, random, io, contextlib

# import the portrait module quietly (its module code writes the portrait file — harmless)
with contextlib.redirect_stdout(io.StringIO()):
    import build_report as b

INK=b.INK; BLUE=b.BLUE; CYAN=b.CYAN; TEAL=b.TEAL; MAG=b.MAG; VIOLET=b.VIOLET; WHITE=b.WHITE

def hero_tall(accent, seed):
    """Tall vertical hero for a landscape section-divider left panel (440x900)."""
    e=[f'<rect width="440" height="900" fill="{INK}"/>']
    e.append(b.scatter(30,30,410,860,55,seed))
    for i in range(5):
        x=70+i*70; amp=32+i*6
        pts=" ".join(f"{x+amp*math.sin(y/95+i):.0f},{y}" for y in range(0,920,20))
        op=.22+i*.12
        e.append(f'<polyline points="{pts}" fill="none" stroke="{accent}" stroke-width="1.4" opacity="{op:.2f}"/>')
    random.seed(seed+3)
    for _ in range(10):
        x=random.uniform(60,380); y=random.uniform(80,820)
        c=random.choice([CYAN,accent,WHITE]); r=random.choice([4,5,6])
        e.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="{c}"/>')
    e.append(b.concentric(230,300,[(78,accent,None,.5),(50,CYAN,None,.6),(22,accent,accent,.9)]))
    e.append(b.concentric(200,640,[(46,CYAN,None,.5),(20,MAG,MAG,.85)]))
    return '<svg viewBox="0 0 440 900" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg">'+"".join(e)+'</svg>'

# ---- landscape CSS overrides (appended AFTER portrait CSS, so later rules win) ----
OVERRIDE = """
/* ===== LANDSCAPE OVERRIDES (297x210) ===== */
:root{ --pw:297mm; --ph:210mm; --pad:15mm; }
@page{ size:A4 landscape; margin:0; }

.cols-3{ column-count:3; column-gap:9mm; }
.cols-3 p:first-child{ margin-top:0; }
.card-grid-3{ display:grid; grid-template-columns:repeat(3,1fr); gap:6mm; margin-top:5mm; }
.split{ display:grid; grid-template-columns:0.92fr 1.28fr; gap:12mm; align-items:start; margin-top:4mm; }
.split .exhibit{ margin-top:0; }

/* Cover: art left, dark meta right (McKinsey's real cover) */
.cover{ display:grid; grid-template-columns:1.15fr 1fr; grid-template-rows:none; height:var(--ph); background:var(--ink); }
.cover .art-panel{ position:relative; overflow:hidden; }
.cover .art-panel svg{ position:absolute; inset:0; width:100%; height:100%; }
.cover .meta-panel{ padding:16mm; display:flex; flex-direction:column; justify-content:space-between; color:#fff; }
.cover .logo{ color:#fff; }
.cover .logo span{ color:rgba(255,255,255,.65); }
.cover h1{ font-size:44pt; line-height:.98; margin-top:6mm; }
.cover .sub{ color:rgba(255,255,255,.8); }

/* Contents: big title left, two TOC columns right */
.contents-land{ display:grid; grid-template-columns:0.7fr 1.5fr; gap:0 14mm; align-items:start; margin-top:6mm; }
.contents-land h2{ font-size:42pt; }
.contents-land .cols{ display:grid; grid-template-columns:1fr 1fr; gap:0 12mm; }

/* Divider: tall hero left, text right, vertically centred */
.divider{ display:grid; grid-template-columns:120mm 1fr; grid-template-rows:none; height:var(--ph); }
.divider .hero{ height:var(--ph); }
.divider .hero svg{ position:absolute; inset:0; width:100%; height:100%; }
.divider .body{ padding:16mm; align-self:center; }
.divider h1{ font-size:34pt; }
.divider .highlight-box{ grid-template-columns:1fr 1fr; }

/* Exec summary stat row a touch smaller to fit width */
.stat .num{ font-size:36pt; }

/* Patterns as three columns in landscape */
.patterns-3{ display:grid; grid-template-columns:repeat(3,1fr); gap:8mm; margin-top:6mm; }
.patterns-3 .pattern-card{ display:block; border-top:3px solid var(--hair); padding-top:5mm; }
.patterns-3 .pattern-card svg{ margin-bottom:3mm; }
"""

APPENDIX_CSS = """
/* ===== REVIEWER-NOTES APPENDIX ===== */
.status{ display:inline-block; font-size:7.5pt; font-weight:700; letter-spacing:.06em; text-transform:uppercase; padding:1mm 3mm; border-radius:20px; color:#fff; white-space:nowrap; }
.status.reviewed{ background:var(--teal); }
.status.clarify{ background:#E8862A; }
.reviewer-note{ border-left:3px solid var(--blue); padding-left:5mm; }
.reviewer-note .who{ font-family:var(--sans); font-weight:700; font-size:10.5pt; }
.reviewer-note .role{ font-size:8pt; color:var(--muted); text-transform:uppercase; letter-spacing:.06em; margin:1mm 0 3mm; }
.reviewer-note p{ font-size:9pt; }
.review-list{ margin-top:4mm; }
.review-row{ display:grid; grid-template-columns:46mm 34mm 1fr; gap:6mm; align-items:start; padding:3mm 0; border-top:1px solid var(--hair); font-size:8.8pt; break-inside:avoid; }
.review-row.head{ border-top:none; color:var(--muted); font-size:7.5pt; text-transform:uppercase; letter-spacing:.06em; }
.review-row .sec{ font-family:var(--sans); font-weight:600; }
.review-row .cmt{ color:#20303c; }
"""

reviewers = [
 ("Dr. Elena Ruiz", "External expert · Operations",
  "A strong, well-evidenced discovery overall. The manual-work findings are convincing and well supported by the voice notes. Before I'd rank the metric-definition signal above the approval bottleneck, I'd like clarification on how its strength was scored."),
 ("Marcus Blake", "Co-reviewer · Finance transformation",
  "Agree with the recommendations and their priority order — month-end automation is the clear first move. Minor: the Sales non-participation should be flagged more prominently in the readiness narrative."),
]
section_reviews = [
 ("Executive summary","reviewed","Clear and accurate. No changes."),
 ("Readiness","clarify","Clarify the weighting rationale for department spread, given Sales did not participate this round."),
 ("Participation","reviewed","Matches the underlying interview records."),
 ("Delta","reviewed","Delta summary is fair and complete."),
 ("Signals","clarify","Metric-definition signal strength (0.55) may be understated relative to the volume of supporting evidence."),
 ("Patterns","reviewed","Cross-team framing is well justified."),
 ("Recommendations","reviewed","Priority order endorsed; catalog matches are appropriate."),
]

def reviewer_notes():
    return "".join(f'<div class="reviewer-note"><div class="who">{w}</div><div class="role">{r}</div><p>{n}</p></div>'
                    for w,r,n in reviewers)

def section_review_rows():
    lab={"reviewed":"Reviewed","clarify":"Needs clarification"}
    rows=[f'<div class="review-row"><span class="sec">{s}</span><span class="status {st}">{lab[st]}</span><span class="cmt">{c}</span></div>'
          for s,st,c in section_reviews]
    return "".join(rows)

def footer(n): return b.footer(n)

HTML = f"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Req — Discovery Report (landscape reference)</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,600;0,700;0,800;1,600&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>{b.CSS}{OVERRIDE}{APPENDIX_CSS}</style></head><body>

<div class="refbar">📐 <b>REFERENCE TEMPLATE — landscape / widescreen variant.</b> Same design system as the portrait file, laid out in McKinsey's real 16:9-style format.
Add, remove, or reorder sections to fit each company's snapshot. (This bar does not print.)</div>

<!-- COVER (art left, title right) -->
<section class="page bleed cover">
  <div class="art-panel">{b.cover_art()}</div>
  <div class="meta-panel">
    <div class="logo">Req<span>Workflow Discovery</span></div>
    <div>
      <span class="tag">Discovery Report</span>
      <h1>Acme Corp</h1>
      <div class="sub">How work really happens across Finance &amp; Operations</div>
      <div class="sub" style="font-size:11pt;margin-top:8mm;">Version 1 · February 2026 · Platform-approved</div>
    </div>
  </div>
</section>

<!-- CONTENTS -->
<section class="page">
  <div class="eyebrow">Report contents</div>
  <div class="contents-land">
    <h2>Contents</h2>
    <div class="cols">
      <div>
        <div class="toc-item rule-blue"><span class="n">01</span><span class="t">Executive summary</span><span class="d">The headline story in one read</span></div>
        <div class="toc-item rule-blue"><span class="n">02</span><span class="t">Readiness</span><span class="d">Score and its weighted breakdown</span></div>
        <div class="toc-item rule-teal"><span class="n">03</span><span class="t">Participation</span><span class="d">Invited, started, completed, by department</span></div>
        <div class="toc-item rule-teal"><span class="n">04</span><span class="t">What changed</span><span class="d">Delta versus the previous version</span></div>
      </div>
      <div>
        <div class="toc-item rule-magenta"><span class="n">05</span><span class="t">Signals</span><span class="d">Recurring pain points with evidence</span></div>
        <div class="toc-item rule-magenta"><span class="n">06</span><span class="t">Patterns</span><span class="d">Cross-team themes and confidence</span></div>
        <div class="toc-item rule-blue"><span class="n">07</span><span class="t">Recommendations</span><span class="d">Prioritized actions, catalog-matched</span></div>
        <div class="toc-item rule-teal"><span class="n">08</span><span class="t">Supporting media &amp; method</span><span class="d">Evidence base and how we measured</span></div>
      </div>
    </div>
  </div>{footer(2)}
</section>

<!-- EXEC SUMMARY -->
<section class="page">
  <div class="eyebrow">01 — Executive summary</div>
  <h1 style="font-size:32pt;margin:4mm 0 6mm;">The story <span class="serif-accent">in one read</span></h1>
  <div class="cols-3">
    <p class="dropcap">With three of four invited employees completing a discovery interview, Acme Corp reached a readiness score of 75 — high enough to surface a clear, actionable picture of how work really happens across Finance and Operations.</p>
    <p>The strongest recurring theme is manual, spreadsheet-bound process work in Finance, echoed by tool-dependency and duplicate-entry signals in Operations. These cluster into three cross-team patterns with concrete, catalog-matched fixes.</p>
    <p>This report is the versioned source of truth for those findings. Every figure below is drawn from the discovery snapshot and has passed expert review before delivery.</p>
  </div>
  <div class="stat-row" style="margin-top:10mm;">
    <div class="stat"><div class="num">75</div><div class="lab">Readiness score, out of 100</div></div>
    <div class="stat"><div class="num cat-data">3/4</div><div class="lab">Employees completed the interview</div></div>
    <div class="stat"><div class="num cat-people">3</div><div class="lab">Cross-team patterns identified</div></div>
    <div class="stat"><div class="num">6</div><div class="lab">Recommendations, catalog-matched</div></div>
  </div>{footer(3)}
</section>

<!-- READINESS (split: text | exhibit) -->
<section class="page">
  <div class="eyebrow">02 — Readiness</div>
  <h1 style="font-size:28pt;margin:4mm 0 3mm;">A readiness score of <span class="serif-accent">75</span></h1>
  <div class="split">
    <div class="cols-1">
      <p class="lead">Readiness gates report generation. It is a weighted score across employee coverage, department spread, pattern confidence, and multimodal evidence.</p>
      <p>Acme Corp scores well on employee coverage and pattern confidence; department spread is the main drag, since Sales did not participate this round. Closing that gap is the fastest route to a higher score next version.</p>
    </div>
    <div class="exhibit"><div class="exlabel">Exhibit 1 · Readiness breakdown</div>
      <h3>Weighted across employees, departments, patterns, and multimodal evidence.</h3>
      <div class="gauge">{b.donut(75,BLUE)}
        <div class="bars" style="flex:1;">
          <div class="bar-row"><span>Employee coverage</span><span class="bar-track"><span class="bar-fill" style="width:80%"></span></span><span class="bar-val">80</span></div>
          <div class="bar-row"><span>Department spread</span><span class="bar-track"><span class="bar-fill cat-tooling" style="width:70%"></span></span><span class="bar-val">70</span></div>
          <div class="bar-row"><span>Pattern confidence</span><span class="bar-track"><span class="bar-fill cat-people" style="width:72%"></span></span><span class="bar-val">72</span></div>
          <div class="bar-row"><span>Multimodal evidence</span><span class="bar-track"><span class="bar-fill cat-data" style="width:65%"></span></span><span class="bar-val">65</span></div>
        </div></div>
      <div class="caption">Source: Req discovery snapshot v1 · Acme Corp</div><div class="mark">Req</div></div>
  </div>{footer(4)}
</section>

<!-- PARTICIPATION (split) -->
<section class="page">
  <div class="eyebrow">03 — Participation</div>
  <h1 style="font-size:28pt;margin:4mm 0 3mm;">Who took part</h1>
  <div class="split">
    <div>
      <p class="lead">Three of four invited employees completed the full discovery interview, a 75% completion rate.</p>
      <p>Finance participated fully; Operations completed one of two. Sales was invited in a later wave and has not yet started — reflected in the department-spread component of the readiness score.</p>
    </div>
    <div class="exhibit"><div class="exlabel">Exhibit 2 · Interview participation</div>
      <h3>Completion by stage and department.</h3>
      <div class="funnel"><div class="step"><div class="v">4</div><div class="l">Invited</div></div>
        <div class="step"><div class="v">4</div><div class="l">Started</div></div>
        <div class="step"><div class="v">3</div><div class="l">Completed</div></div>
        <div class="step"><div class="v">75%</div><div class="l">Completion</div></div></div>
      <table class="data"><thead><tr><th>Department</th><th>Invited</th><th>Started</th><th>Completed</th></tr></thead>
        <tbody>{b.dept_rows()}</tbody></table>
      <div class="caption">Source: Req discovery snapshot v1 · Acme Corp</div><div class="mark">Req</div></div>
  </div>{footer(5)}
</section>

<!-- SIGNALS DIVIDER (tall hero left) -->
<section class="page bleed divider">
  <div class="hero"><div class="cat" style="background:var(--magenta);">Signals &amp; Patterns</div>{hero_tall(MAG,11)}</div>
  <div class="body"><div class="eyebrow">05 &amp; 06 — Signals and patterns</div>
    <h1 style="margin-top:4mm;">What the interviews revealed</h1>
    <p class="lead">Signals are recurring pain points drawn directly from employee interviews. Patterns are the themes that connect them across departments. Together they explain the readiness score and drive every recommendation.</p>
    <div class="highlight-box">
      <div class="highlight"><p><strong>6 signals</strong> surfaced, led by manual reconciliation in Finance at 0.82 strength.</p></div>
      <div class="highlight"><p><strong>3 patterns</strong> connect these signals across teams, all matched to catalog solutions.</p></div>
    </div></div>
</section>

<!-- SIGNALS (wide lollipop + 3-col cards) -->
<section class="page">
  <div class="eyebrow">05 — Signals</div>
  <h1 style="font-size:28pt;margin:4mm 0 3mm;">Recurring pain points</h1>
  <div class="exhibit"><div class="exlabel">Exhibit 3 · Signals ranked by strength</div>
    <h3>Colour encodes category: process, tooling, people, data.</h3>{b.signal_ranking()}
    <div class="caption">Source: Req discovery snapshot v1 · Acme Corp</div><div class="mark">Req</div></div>
  <div class="card-grid-3">{b.signal_cards()}</div>{footer(6)}
</section>

<!-- PULL QUOTE -->
<section class="page dark pullquote">
  <blockquote style="font-size:34pt;max-width:230mm;">The strongest signal isn't a tool problem — it's <span class="accent">manual work</span> that quietly repeats across every close cycle.
    <cite>Key finding · Acme Corp discovery</cite></blockquote>{footer(7)}
</section>

<!-- PATTERNS (3 columns) -->
<section class="page">
  <div class="eyebrow">06 — Patterns</div>
  <h1 style="font-size:28pt;margin:4mm 0 3mm;">Cross-team themes</h1>
  <p class="lead" style="max-width:200mm;">Each pattern connects several signals across departments. Confidence reflects how consistently the theme appeared across interviews and evidence.</p>
  <div class="patterns-3">{b.pattern_cards()}</div>{footer(8)}
</section>

<!-- RECOMMENDATIONS (3-col cards) -->
<section class="page">
  <div class="eyebrow">07 — Recommendations</div>
  <h1 style="font-size:28pt;margin:4mm 0 4mm;">Suggested actions</h1>
  <div class="card-grid-3">{b.rec_cards()}</div>{footer(9)}
</section>

<!-- MATRIX + DELTA (split) -->
<section class="page">
  <div class="eyebrow">07 — Prioritization · 04 — What changed</div>
  <h1 style="font-size:26pt;margin:4mm 0 4mm;">Where to start, and what moved</h1>
  <div class="split">
    <div class="exhibit"><div class="exlabel">Exhibit 4 · Impact vs feasibility</div>
      <h3>Prioritize high-impact, high-feasibility moves first.</h3>{b.priority_matrix()}
      <div class="caption">Source: Req discovery snapshot v1 · Acme Corp</div><div class="mark">Req</div></div>
    <div>
      <div class="eyebrow">04 — Delta from v0</div>
      <div class="delta" style="margin-top:4mm;">
        <div class="col add"><h4>New</h4><ul><li>Signal: inconsistent metric definitions</li><li>Signal: undocumented tribal knowledge</li><li>Pattern: fragmented data erodes trust</li></ul></div>
        <div class="col chg"><h4>Changed</h4><ul><li>Manual reconciliation 0.70 → 0.82</li><li>Completion 50% → 75%</li><li>Readiness 61 → 75</li></ul></div>
        <div class="col rem"><h4>Resolved</h4><ul><li>Onboarding delay signal cleared</li></ul></div>
      </div>
      <p style="font-size:8.5pt;color:var(--muted);margin-top:5mm;">This version expanded discovery with a second completed cohort: two new findings, several strengthened, one resolved.</p>
    </div>
  </div>{footer(10)}
</section>

<!-- MEDIA + METHOD -->
<section class="page">
  <div class="eyebrow">08 — Supporting media &amp; methodology</div>
  <h1 style="font-size:28pt;margin:4mm 0 4mm;">Evidence base</h1>
  <div class="card-grid-3">
    {"".join(f'<div class="media-card"><div class="c">{k}</div><div class="k">{n}</div><p>{d}</p></div>' for k,n,d in b.media)}
  </div>
  <div class="split" style="margin-top:8mm;">
    <div>
      <div class="eyebrow">Methodology</div>
      <p class="method" style="margin-top:3mm;">Findings draw on structured interviews conducted over WhatsApp and web chat between June 2025 and February 2026. Four employees across Finance and Operations participated; three completed the full discovery flow.</p>
    </div>
    <div class="method" style="align-self:center;">
      <dl><dt>Readiness weighting</dt><dd style="font-size:9pt;color:var(--muted);">Employee coverage (30%), department spread (25%), pattern confidence (25%), multimodal evidence (20%).</dd>
      <dt>Review</dt><dd style="font-size:9pt;color:var(--muted);">Reviewed by one external expert and approved by the Req platform team before delivery. Reviewer notes appear in the appendix on approved reports.</dd></dl>
    </div>
  </div>{footer(11)}
</section>

<!-- APPENDIX DIVIDER: reviewer notes (approval regenerate path only) -->
<section class="page bleed divider">
  <div class="hero"><div class="cat" style="background:var(--blue);">Appendix</div>{hero_tall(BLUE,23)}</div>
  <div class="body">
    <div class="eyebrow">Appendix — included on platform-approved reports only</div>
    <h1 style="margin-top:4mm;">Reviewer notes</h1>
    <p class="lead">Overall notes and section-level comments from expert review, gathered at platform approval. Live discussions and interview follow-up threads are collaboration tooling and are intentionally excluded from this deliverable.</p>
    <div class="highlight-box">
      <div class="highlight"><p><strong>2 reviewers</strong> completed review before approval.</p></div>
      <div class="highlight"><p><strong>5 of 7</strong> sections marked reviewed; 2 flagged for clarification.</p></div>
    </div>
  </div>
</section>

<!-- APPENDIX CONTENT: overall notes + section-by-section review -->
<section class="page">
  <div class="eyebrow">Appendix · Reviewer notes</div>
  <h1 style="font-size:26pt;margin:4mm 0 5mm;">Overall notes</h1>
  <div class="split" style="grid-template-columns:1fr 1fr;">{reviewer_notes()}</div>
  <div class="eyebrow" style="margin-top:9mm;">Section-by-section review</div>
  <div class="review-list">
    <div class="review-row head"><span class="sec">Section</span><span>Status</span><span>Comment</span></div>
    {section_review_rows()}
  </div>
  {footer(12)}
</section>

</body></html>"""

with open("/home/claude/req-report-template-landscape.html","w") as f:
    f.write(HTML)
open("/home/claude/hero_tall.svg","w").write(hero_tall(MAG,11))
print("landscape pages:", HTML.count('class="page'), "bytes:", len(HTML))
