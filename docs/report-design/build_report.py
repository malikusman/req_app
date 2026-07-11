#!/usr/bin/env python3
"""Builds a full, richly-illustrated McKinsey-style discovery report (dummy data).
Art is generated procedurally so the visuals are dense and intentional, not sparse."""
import math, random

INK="#051C2C"; BLUE="#1F40FF"; BLUE2="#5A7BFF"; CYAN="#00A9F4"
TEAL="#14B8A6"; MAG="#E6338A"; PINK="#F5A9CE"; VIOLET="#8B5CF6"; WHITE="#FFFFFF"
PALETTE=[BLUE, CYAN, TEAL, MAG, VIOLET, BLUE2]

def polar(cx, cy, r, a):  # a in degrees
    rad=math.radians(a); return cx+r*math.cos(rad), cy+r*math.sin(rad)

def wedge(cx, cy, r0, r1, a0, a1, fill, op=1.0):
    x0,y0=polar(cx,cy,r1,a0); x1,y1=polar(cx,cy,r1,a1)
    xi0,yi0=polar(cx,cy,r0,a1); xi1,yi1=polar(cx,cy,r0,a0)
    large=1 if (a1-a0)%360>180 else 0
    return (f'<path d="M{x0:.1f} {y0:.1f} A{r1} {r1} 0 {large} 1 {x1:.1f} {y1:.1f} '
            f'L{xi0:.1f} {yi0:.1f} A{r0} {r0} 0 {large} 0 {xi1:.1f} {yi1:.1f} Z" '
            f'fill="{fill}" opacity="{op}"/>')

def concentric(cx, cy, rings):
    out=[]
    for r,stroke,fill,op in rings:
        if fill:
            out.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}" opacity="{op}"/>')
        else:
            out.append(f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{stroke}" stroke-width="2" opacity="{op}"/>')
    return "".join(out)

def dot_triangle(x, y, rows, sp, r, color, flip=False):
    out=[]
    for i in range(rows):
        n=i+1
        for j in range(n):
            dx=x+(i*sp if not flip else -i*sp)
            dy=y+(j-(n-1)/2)*sp
            out.append(f'<circle cx="{dx:.0f}" cy="{dy:.0f}" r="{r}" fill="{color}"/>')
    return "".join(out)

def checker(x, y, cols, rows, size, c1, c2):
    out=[]
    for r in range(rows):
        for c in range(cols):
            col=c1 if (r+c)%2==0 else c2
            if col:
                out.append(f'<rect x="{x+c*size}" y="{y+r*size}" width="{size-1}" height="{size-1}" fill="{col}"/>')
    return "".join(out)

def rays(cx, cy, n, r0, r1, a0, a1, color, dot_color, dr=3):
    out=[]
    for k in range(n):
        a=a0+(a1-a0)*k/(n-1)
        x0,y0=polar(cx,cy,r0,a); x1,y1=polar(cx,cy,r1,a)
        out.append(f'<line x1="{x0:.1f}" y1="{y0:.1f}" x2="{x1:.1f}" y2="{y1:.1f}" stroke="{color}" stroke-width="1" opacity=".55"/>')
        c=[MAG,CYAN,TEAL,VIOLET][k%4] if dot_color=="mix" else dot_color
        out.append(f'<circle cx="{x1:.1f}" cy="{y1:.1f}" r="{dr}" fill="{c}"/>')
    return "".join(out)

def scatter(x0,y0,x1,y1,n,seed):
    random.seed(seed); out=[]
    for _ in range(n):
        x=random.uniform(x0,x1); y=random.uniform(y0,y1)
        c=random.choice([WHITE,CYAN,MAG,TEAL,VIOLET])
        r=random.choice([1.5,2,2.5,3]); op=random.uniform(.35,.9)
        out.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="{c}" opacity="{op:.2f}"/>')
    return "".join(out)

def cover_art():
    """Dense symmetric composition: sunburst ring + concentric eye + dot triangles +
    checkerboard + radiating data streams + scatter. Reserves lower band for the title."""
    cx,cy=400,400; e=[]
    e.append(f'<rect width="800" height="1000" fill="{INK}"/>')
    # scatter behind
    e.append(scatter(60,60,740,340,70,7))
    # sunburst ring around eye (upper 3/4)
    seg=36
    for k in range(seg):
        a0=-200+ (k*(360/seg)); a1=a0+(360/seg)-2
        if -200<=a0<=20:  # top arc
            e.append(wedge(cx,cy,235,300,a0,a1,PALETTE[k%len(PALETTE)],op=.9))
    # eye lens
    e.append(f'<path d="M150 400 Q400 250 650 400 Q400 550 150 400 Z" fill="{BLUE}" opacity=".18"/>')
    e.append(f'<path d="M210 400 Q400 300 590 400 Q400 500 210 400 Z" fill="{CYAN}" opacity=".14"/>')
    # concentric eye
    e.append(concentric(cx,cy,[
        (150,None,None,0),(150,BLUE2,None,.6),(120,CYAN,None,.7),
        (95,BLUE,BLUE,.95),(62,CYAN,CYAN,1),(30,INK,INK,1),(14,CYAN,CYAN,1)]))
    e.append(f'<circle cx="{cx}" cy="{cy}" r="150" fill="none" stroke="{TEAL}" stroke-width="2" opacity=".5"/>')
    # dot triangle left, checker right (framing)
    e.append(dot_triangle(70,400,7,15,3,MAG))
    e.append(checker(600,330,6,10,15,BLUE,None))
    e.append(checker(600,330,6,10,15,None,CYAN))
    # top corner accents
    e.append(wedge(120,120,0,70,90,180,VIOLET,.85))
    e.append(wedge(680,120,0,70,0,90,TEAL,.85))
    e.append(f'<circle cx="120" cy="120" r="22" fill="none" stroke="{MAG}" stroke-width="6"/>')
    e.append(f'<circle cx="680" cy="120" r="22" fill="none" stroke="{CYAN}" stroke-width="6"/>')
    # radiating data streams fanning downward below the eye (signature bottom motif)
    e.append(rays(cx,565,19,60,215,38,142,WHITE,"mix",dr=4))
    e.append('<g opacity=".7">'+rays(cx,565,9,60,160,58,122,CYAN,TEAL,dr=3)+'</g>')
    return '<svg viewBox="0 0 800 1000" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg">'+"".join(e)+'</svg>'

def hero_art(accent, seed):
    """Section-divider hero: flowing waves + nodes in the category color."""
    e=[f'<rect width="800" height="440" fill="{INK}"/>']
    e.append(scatter(40,40,760,400,55,seed))
    for i in range(5):
        y=120+i*45; amp=40+i*8
        pts=" ".join(f"{x},{y+amp*math.sin(x/90+i):.0f}" for x in range(0,820,20))
        op=.25+i*.12
        e.append(f'<polyline points="{pts}" fill="none" stroke="{accent}" stroke-width="1.4" opacity="{op:.2f}"/>')
    random.seed(seed+1)
    for _ in range(9):
        x=random.uniform(80,720); y=random.uniform(90,360)
        c=random.choice([CYAN,accent,WHITE]); r=random.choice([4,5,6])
        e.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="{r}" fill="{c}"/>')
    e.append(concentric(660,220,[(70,accent,None,.5),(45,CYAN,None,.6),(20,accent,accent,.9)]))
    return '<svg viewBox="0 0 800 440" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg">'+"".join(e)+'</svg>'

# ---------- DUMMY DATA ----------
signals=[
 ("process","Process · Finance","Manual reconciliation in spreadsheets",0.82,
  "Month-end close depends on hand-built spreadsheets passed between three analysts, creating rework, version conflicts, and multi-day delays.",
  "“I rebuild the same sheet every month from scratch.” — Finance analyst"),
 ("tooling","Tooling · Operations","Tool dependency on a single admin",0.68,
  "Only one person can configure the scheduling tool, so the whole ops calendar stalls whenever they are unavailable.",
  "“If Sam's out, scheduling just waits.” — Operations lead"),
 ("people","People · Finance","Approval bottlenecks",0.61,
  "Routine, low-value approvals route through a single director and sit for days, slowing the entire request queue.",
  "“Small approvals sit for a week.” — Team member"),
 ("process","Process · Operations","Duplicate data entry across systems",0.58,
  "The same order details are re-keyed into three systems, introducing errors and consuming hours of avoidable effort each week.",
  "“I type the same order three times.” — Ops coordinator"),
 ("data","Data · Cross-team","Inconsistent metric definitions",0.55,
  "Finance and Operations report the same KPI with different definitions, so dashboards disagree and trust in the numbers erodes.",
  "“Our dashboards never quite agree.” — Ops analyst"),
 ("people","People · Cross-team","Undocumented tribal knowledge",0.49,
  "Critical steps live only in a few people's heads, making onboarding slow and creating risk when they leave.",
  "“New joiners take months to get productive.” — Manager"),
]
patterns=[
 ("Manual work compounds at month-end",0.74,"process",
  "Reconciliation, duplicate entry, and slow approvals stack up during the close, turning routine work into a recurring crunch across Finance and Operations."),
 ("Single points of failure in tooling and knowledge",0.66,"tooling",
  "Tool configuration and critical know-how concentrate in a handful of people, leaving the organization exposed whenever they are unavailable."),
 ("Fragmented data erodes trust in reporting",0.58,"data",
  "Divergent metric definitions and re-keyed data mean teams cannot agree on a single source of truth, weakening decision-making."),
]
recs=[
 ("high","Automate month-end reconciliation","Replace hand-built close spreadsheets with a templated, validated workflow.","Finance Close Automation",78,72),
 ("high","Cross-train ops tooling ownership","Document and share scheduling-tool configuration beyond a single admin.","Ops Resilience Playbook",70,80),
 ("med","Consolidate duplicate data entry","Integrate the three order systems so details are entered once.","Systems Integration Assessment",65,45),
 ("med","Delegate routine approvals","Auto-route approvals below a set threshold to team leads.","Approval Policy Redesign",55,85),
 ("med","Standardize KPI definitions","Agree one shared definition per metric across teams.","Metric Governance Kit",60,70),
 ("low","Capture tribal knowledge","Build a living knowledge base for critical, undocumented steps.","Knowledge Base Rollout",45,55),
]
media=[
 ("Voice","12 voice notes","Employees described close-cycle frustration in their own words; sentiment analysis flagged 'rework' and 'waiting' as dominant themes."),
 ("Image","5 screenshots","Uploaded spreadsheet screenshots confirmed the manual reconciliation signal and revealed three parallel versions of the same workbook."),
 ("Document","2 process docs","An outdated SOP and an onboarding checklist corroborated the undocumented-knowledge signal."),
]
depts=[("Finance",2,2,2),("Operations",2,2,1),("Sales",0,0,0)]

def cat_class(c): return {"process":"cat-process","tooling":"cat-tooling","people":"cat-people","data":"cat-data"}[c]

def signal_cards():
    out=[]
    for c,meta,title,strength,body,ev in signals:
        out.append(f'''<div class="signal-card {cat_class(c)}">
          <div class="meta">{meta}</div><div class="st">{title}</div>
          <div class="strength"><i style="width:{strength*100:.0f}%"></i></div>
          <div class="meta">Strength {strength:.2f}</div>
          <p>{body}</p><div class="evidence">{ev}</div></div>''')
    return "".join(out)

def signal_ranking():
    rows=sorted(signals,key=lambda s:-s[3]); out=[]
    for c,meta,title,s,_,_ in rows:
        cls={"process":"","tooling":"cat-tooling","people":"cat-people","data":"cat-data"}[c]
        out.append(f'''<div class="lolli"><span class="lab">{title}</span>
          <span class="track"><span class="line {cls}" style="width:{s*100:.0f}%"></span>
          <span class="dot {cls}" style="left:{s*100:.0f}%"></span></span>
          <span class="val">{s:.2f}</span></div>''')
    return "".join(out)

def donut(pct,color):
    return (f'<svg width="64" height="64" viewBox="0 0 42 42"><circle cx="21" cy="21" r="15.9" fill="none" stroke="#EFF3F7" stroke-width="5"/>'
            f'<circle cx="21" cy="21" r="15.9" fill="none" stroke="{color}" stroke-width="5" '
            f'stroke-dasharray="{pct} {100-pct}" stroke-dashoffset="25" transform="rotate(-90 21 21)" stroke-linecap="round"/>'
            f'<text x="21" y="24" text-anchor="middle" font-size="9" font-weight="700" fill="{INK}" font-family="Inter">{pct}</text></svg>')

def pattern_cards():
    cmap={"process":BLUE,"tooling":CYAN,"data":TEAL}; out=[]
    for title,conf,c,body in patterns:
        out.append(f'''<div class="pattern-card">{donut(int(conf*100),cmap[c])}
          <div><div class="st">{title}</div><div class="meta">Confidence {conf:.2f}</div><p>{body}</p></div></div>''')
    return "".join(out)

def rec_cards():
    lab={"high":"High priority","med":"Medium priority","low":"Low priority"}; out=[]
    for pr,title,body,match,imp,feas in recs:
        out.append(f'''<div class="rec-card"><span class="pill {pr}">{lab[pr]}</span>
          <h4>{title}</h4><p>{body}</p><div class="match">Catalog match: {match}</div></div>''')
    return "".join(out)

def priority_matrix():
    # 2x2: x=feasibility, y=impact. Plot recs.
    pts=[]
    cmap={"high":MAG,"med":CYAN,"low":"#8896A2"}
    for pr,title,_,_,imp,feas in recs:
        x=40+feas/100*320; y=300-imp/100*260
        pts.append(f'<circle cx="{x:.0f}" cy="{y:.0f}" r="7" fill="{cmap[pr]}"/>')
        pts.append(f'<text x="{x+11:.0f}" y="{y+3:.0f}" font-size="8" fill="{INK}" font-family="Inter">{title.split()[0]} {title.split()[1]}</text>')
    return ('<svg viewBox="0 0 420 330" xmlns="http://www.w3.org/2000/svg" width="100%">'
            f'<line x1="40" y1="300" x2="380" y2="300" stroke="{INK}" stroke-width="1"/>'
            f'<line x1="40" y1="20" x2="40" y2="300" stroke="{INK}" stroke-width="1"/>'
            f'<line x1="210" y1="20" x2="210" y2="300" stroke="#D6DEE6" stroke-dasharray="3 3"/>'
            f'<line x1="40" y1="160" x2="380" y2="160" stroke="#D6DEE6" stroke-dasharray="3 3"/>'
            '<text x="210" y="322" text-anchor="middle" font-size="8" fill="#5A6B78" font-family="Inter">Feasibility →</text>'
            '<text x="18" y="160" text-anchor="middle" font-size="8" fill="#5A6B78" font-family="Inter" transform="rotate(-90 18 160)">Impact →</text>'
            +"".join(pts)+'</svg>')

def dept_rows():
    return "".join(f'<tr><td>{d}</td><td>{i}</td><td>{s}</td><td>{c}</td></tr>' for d,i,s,c in depts)

# ---------- CSS ----------
CSS = """
:root{
 --ink:#051C2C;--blue:#1F40FF;--blue2:#5A7BFF;--cyan:#00A9F4;--teal:#14B8A6;--magenta:#E6338A;
 --paper:#FFFFFF;--paper-soft:#F5F7FA;--hair:#D6DEE6;--muted:#5A6B78;
 --cat-process:var(--blue);--cat-tooling:var(--cyan);--cat-people:var(--magenta);--cat-data:var(--teal);
 --serif:"Playfair Display",Georgia,serif;--sans:"Inter","Helvetica Neue",Arial,sans-serif;
 --pw:210mm;--ph:297mm;--pad:18mm;}
@page{size:A4 portrait;margin:0;}
*{box-sizing:border-box;-webkit-print-color-adjust:exact;print-color-adjust:exact;}
html,body{margin:0;padding:0;background:#e9edf1;color:var(--ink);font-family:var(--sans);}
.refbar{background:#111;color:#fff;font-family:var(--sans);font-size:12px;padding:10px 16px;text-align:center;line-height:1.4;}
.refbar b{color:#FFD34E;}
@media print{.refbar{display:none;}}
.page{position:relative;width:var(--pw);min-height:var(--ph);padding:var(--pad);margin:0 auto 10mm;background:var(--paper);overflow:hidden;page-break-after:always;break-after:page;}
.page:last-child{page-break-after:auto;}
.page.dark{background:var(--ink);color:#fff;}
.page.bleed{padding:0;}
.exhibit,.stat,.signal-card,.pattern-card,.rec-card,.highlight-box,figure,.lolli{break-inside:avoid;page-break-inside:avoid;}
.footer{position:absolute;left:var(--pad);right:var(--pad);bottom:10mm;display:flex;justify-content:space-between;align-items:center;font-size:8pt;letter-spacing:.02em;color:var(--muted);border-top:1px solid var(--hair);padding-top:4mm;}
.footer .brand{font-weight:600;color:var(--ink);}
.dark .footer{color:rgba(255,255,255,.6);border-color:rgba(255,255,255,.18);}
.dark .footer .brand{color:#fff;}
h1,h2,h3,h4{font-family:var(--serif);font-weight:700;line-height:1.05;margin:0;}
.eyebrow{font-family:var(--sans);font-weight:600;font-size:8.5pt;letter-spacing:.14em;text-transform:uppercase;color:var(--muted);}
p{font-size:9.5pt;line-height:1.5;margin:0 0 3mm;color:#20303c;}
.lead{font-size:11pt;line-height:1.55;color:var(--ink);}
strong{font-weight:600;}
.serif-accent{color:var(--blue);}
.cols-2{column-count:2;column-gap:10mm;}
.cols-2 p:first-child{margin-top:0;}
.dropcap::first-letter{font-family:var(--serif);font-weight:800;float:left;font-size:34pt;line-height:.8;padding:2pt 4pt 0 0;color:var(--ink);}
/* cover */
.cover{position:relative;height:var(--ph);background:var(--ink);color:#fff;}
.cover svg{position:absolute;inset:0;width:100%;height:100%;}
.cover .layer{position:absolute;inset:0;padding:18mm;display:flex;flex-direction:column;justify-content:space-between;}
.cover .logo{font-family:var(--serif);font-size:16pt;font-weight:700;}
.cover .logo span{display:block;font-size:9pt;font-family:var(--sans);font-weight:500;color:rgba(255,255,255,.65);letter-spacing:.02em;margin-top:1mm;}
.cover .title-block{background:linear-gradient(to top,rgba(5,28,44,.96) 60%,transparent);padding-top:30mm;margin:-18mm;padding:30mm 18mm 18mm;}
.cover .tag{display:inline-block;font-family:var(--sans);font-weight:600;font-size:8.5pt;letter-spacing:.12em;text-transform:uppercase;color:#fff;background:var(--blue);padding:2mm 4mm;border-radius:2px;}
.cover h1{font-size:52pt;line-height:.98;margin-top:6mm;}
.cover .sub{font-size:14pt;color:rgba(255,255,255,.8);font-family:var(--sans);font-weight:500;margin-top:4mm;}
/* contents */
.toc{display:grid;grid-template-columns:1fr 1fr;gap:0 14mm;margin-top:8mm;}
.toc h2{font-size:34pt;grid-column:1/-1;margin-bottom:6mm;}
.toc-item{display:grid;grid-template-columns:auto 1fr;gap:5mm;align-items:baseline;padding:4mm 0;border-top:2px solid var(--ink);}
.toc-item .n{font-family:var(--serif);font-weight:700;font-size:14pt;}
.toc-item .t{font-family:var(--sans);font-weight:600;font-size:10.5pt;}
.toc-item .d{grid-column:2;font-size:8.5pt;color:var(--muted);margin-top:1mm;}
.toc-item.rule-blue{border-top-color:var(--blue);}.toc-item.rule-teal{border-top-color:var(--teal);}.toc-item.rule-magenta{border-top-color:var(--magenta);}
/* divider */
.divider{display:grid;grid-template-rows:1fr auto;height:var(--ph);}
.divider .hero{position:relative;overflow:hidden;}
.divider .hero .cat{position:absolute;top:0;left:0;padding:3mm 6mm;font-family:var(--sans);font-weight:600;font-size:8.5pt;letter-spacing:.12em;text-transform:uppercase;color:#fff;z-index:2;}
.divider .hero svg{position:absolute;inset:0;width:100%;height:100%;}
.divider .body{padding:12mm 18mm 16mm;}
.divider h1{font-size:38pt;}
.divider .lead{margin-top:5mm;max-width:150mm;}
.highlight-box{margin-top:8mm;display:grid;grid-template-columns:1fr 1fr;gap:6mm 10mm;}
.highlight{border-left:3px solid var(--blue);padding-left:5mm;}
.highlight p{font-size:9pt;margin:0;}
/* stats */
.stat-row{display:grid;grid-template-columns:repeat(4,1fr);gap:10mm;margin:6mm 0;}
.stat .num{font-family:var(--serif);font-weight:800;font-size:40pt;line-height:1;color:var(--blue);}
.stat .num.cat-people{color:var(--magenta);}.stat .num.cat-data{color:var(--teal);}
.stat .lab{font-size:8.5pt;color:var(--muted);margin-top:2mm;line-height:1.35;}
/* exhibits */
.exhibit{border:1px solid var(--hair);padding:8mm;margin:6mm 0;}
.exhibit .exlabel{font-size:8pt;color:var(--muted);border-left:3px solid var(--blue);padding-left:3mm;}
.exhibit h3{font-family:var(--sans);font-weight:600;font-size:11pt;line-height:1.3;margin:2mm 0 5mm;}
.exhibit .caption{font-size:8.5pt;color:var(--muted);margin-top:5mm;}
.exhibit .mark{font-weight:600;font-size:8.5pt;margin-top:3mm;}
.bars{display:flex;flex-direction:column;gap:3mm;}
.bar-row{display:grid;grid-template-columns:48mm 1fr auto;gap:4mm;align-items:center;font-size:8.5pt;}
.bar-track{height:6mm;background:var(--paper-soft);position:relative;}
.bar-fill{height:100%;background:var(--blue);}.bar-fill.cat-tooling{background:var(--cyan);}.bar-fill.cat-people{background:var(--magenta);}.bar-fill.cat-data{background:var(--teal);}
.bar-val{font-weight:600;}
.gauge{display:flex;gap:8mm;align-items:center;}
.funnel{display:grid;grid-template-columns:repeat(4,1fr);gap:4mm;text-align:center;}
.funnel .step{background:var(--paper-soft);padding:5mm 3mm;border-top:3px solid var(--blue);}
.funnel .step .v{font-family:var(--serif);font-weight:800;font-size:20pt;color:var(--ink);}
.funnel .step .l{font-size:8pt;color:var(--muted);margin-top:1mm;}
/* lollipop */
.lolli{display:grid;grid-template-columns:60mm 1fr auto;gap:4mm;align-items:center;font-size:8.5pt;margin:2mm 0;}
.lolli .track{position:relative;height:10px;}
.lolli .line{position:absolute;top:4px;left:0;height:2px;background:var(--blue);}
.lolli .line.cat-tooling{background:var(--cyan);}.lolli .line.cat-people{background:var(--magenta);}.lolli .line.cat-data{background:var(--teal);}
.lolli .dot{position:absolute;top:0;width:10px;height:10px;border-radius:50%;background:var(--blue);transform:translateX(-50%);}
.lolli .dot.cat-tooling{background:var(--cyan);}.lolli .dot.cat-people{background:var(--magenta);}.lolli .dot.cat-data{background:var(--teal);}
.lolli .val{font-weight:600;}
/* cards */
.card-grid{display:grid;grid-template-columns:1fr 1fr;gap:6mm;margin-top:5mm;}
.signal-card{border-top:3px solid var(--cat-process);padding-top:4mm;}
.signal-card.cat-tooling{border-top-color:var(--cat-tooling);}.signal-card.cat-people{border-top-color:var(--cat-people);}.signal-card.cat-data{border-top-color:var(--cat-data);}
.signal-card .st{font-family:var(--sans);font-weight:700;font-size:10.5pt;margin-bottom:2mm;}
.signal-card .meta{font-size:8pt;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;}
.signal-card p{font-size:8.8pt;margin:2mm 0;}
.strength{height:4mm;background:var(--paper-soft);margin:3mm 0 2mm;}
.strength>i{display:block;height:100%;background:var(--cat-process);}
.signal-card.cat-tooling .strength>i{background:var(--cat-tooling);}.signal-card.cat-people .strength>i{background:var(--cat-people);}.signal-card.cat-data .strength>i{background:var(--cat-data);}
.evidence{font-size:8pt;font-style:italic;color:var(--muted);border-left:2px solid var(--hair);padding-left:3mm;}
.pattern-card{display:grid;grid-template-columns:auto 1fr;gap:5mm;align-items:start;border-top:1px solid var(--hair);padding:5mm 0;}
.pattern-card .st{font-family:var(--sans);font-weight:700;font-size:11pt;}
.pattern-card .meta{font-size:8pt;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;margin:1mm 0 2mm;}
.pattern-card p{font-size:8.8pt;margin:0;}
.rec-card{border:1px solid var(--hair);padding:5mm;}
.rec-card .pill{display:inline-block;font-size:7.5pt;font-weight:700;letter-spacing:.06em;text-transform:uppercase;padding:1mm 3mm;border-radius:20px;color:#fff;}
.pill.high{background:var(--magenta);}.pill.med{background:var(--cyan);}.pill.low{background:var(--muted);}
.rec-card h4{font-family:var(--sans);font-weight:700;font-size:10.5pt;margin:3mm 0 2mm;}
.rec-card p{font-size:8.8pt;margin:0;}
.rec-card .match{font-size:8pt;color:var(--blue);font-weight:600;margin-top:3mm;}
/* pull quote */
.pullquote{display:flex;align-items:center;}
.pullquote blockquote{font-family:var(--serif);font-weight:600;font-size:30pt;line-height:1.12;margin:0;}
.pullquote .accent{color:var(--cyan);}
.pullquote cite{display:block;font-family:var(--sans);font-style:normal;font-weight:600;font-size:9pt;letter-spacing:.1em;text-transform:uppercase;color:rgba(255,255,255,.7);margin-top:8mm;}
/* delta + table */
.delta{display:grid;grid-template-columns:1fr 1fr 1fr;gap:5mm;margin-top:5mm;}
.delta .col h4{font-family:var(--sans);font-weight:700;font-size:9.5pt;padding-bottom:2mm;border-bottom:2px solid var(--ink);}
.delta .col.add h4{border-color:var(--teal);}.delta .col.chg h4{border-color:var(--cyan);}.delta .col.rem h4{border-color:var(--muted);}
.delta li{font-size:8.8pt;margin:2mm 0;list-style:none;}
.delta ul{padding:0;margin:3mm 0 0;}
table.data{width:100%;border-collapse:collapse;font-size:9pt;margin-top:3mm;}
table.data th{text-align:left;font-family:var(--sans);font-weight:600;font-size:8pt;text-transform:uppercase;letter-spacing:.06em;color:var(--muted);border-bottom:2px solid var(--ink);padding:2mm;}
table.data td{padding:2mm;border-bottom:1px solid var(--hair);}
.media-card{border-top:3px solid var(--teal);padding-top:4mm;}
.media-card .k{font-family:var(--sans);font-weight:700;font-size:10pt;}
.media-card .c{font-size:8pt;color:var(--muted);text-transform:uppercase;letter-spacing:.06em;margin:1mm 0;}
.media-card p{font-size:8.8pt;}
.method{font-size:9pt;line-height:1.6;}
.method dt{font-family:var(--sans);font-weight:700;margin-top:3mm;}
"""

def footer(n): return f'<div class="footer"><span class="brand">Req · Acme Corp Discovery Report</span><span>{n:02d}</span></div>'

HTML=f"""<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Req — Discovery Report (reference template)</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,400;0,600;0,700;0,800;1,600&family=Inter:wght@400;500;600;700&display=swap" rel="stylesheet">
<style>{CSS}</style></head><body>

<div class="refbar">📐 <b>REFERENCE TEMPLATE — not a fixed spec.</b> This shows Req's report design system with dummy Acme Corp data.
Add, remove, or reorder sections to fit each company's actual snapshot. Fonts &amp; colors are tokens; swap freely. (This bar does not print.)</div>

<!-- COVER -->
<section class="page bleed cover">
  {cover_art()}
  <div class="layer">
    <div class="logo">Req<span>Workflow Discovery</span></div>
    <div class="title-block">
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
  <div class="toc"><h2>Contents</h2>
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
  </div>{footer(2)}
</section>

<!-- EXEC SUMMARY -->
<section class="page">
  <div class="eyebrow">01 — Executive summary</div>
  <h1 style="font-size:34pt;margin:4mm 0 6mm;">The story <span class="serif-accent">in one read</span></h1>
  <div class="cols-2">
    <p class="dropcap">With three of four invited employees completing a discovery interview, Acme Corp reached a readiness score of 75 — high enough to surface a clear, actionable picture of how work really happens across Finance and Operations.</p>
    <p>The strongest recurring theme is manual, spreadsheet-bound process work in Finance, echoed by tool-dependency and duplicate-entry signals in Operations. These are not isolated complaints; they cluster into three cross-team patterns that point to concrete, catalog-matched fixes.</p>
    <p>Two patterns — manual work compounding at month-end, and single points of failure in tooling and knowledge — account for most of the friction employees described. A third, fragmented data, quietly undermines trust in reporting.</p>
    <p>This report is the versioned source of truth for those findings. Every figure below is drawn from the discovery snapshot and has passed expert review before delivery.</p>
  </div>
  <div class="stat-row" style="margin-top:10mm;">
    <div class="stat"><div class="num">75</div><div class="lab">Readiness score, out of 100</div></div>
    <div class="stat"><div class="num cat-data">3/4</div><div class="lab">Employees completed the interview</div></div>
    <div class="stat"><div class="num cat-people">3</div><div class="lab">Cross-team patterns identified</div></div>
    <div class="stat"><div class="num">6</div><div class="lab">Recommendations, catalog-matched</div></div>
  </div>{footer(3)}
</section>

<!-- READINESS + PARTICIPATION -->
<section class="page">
  <div class="eyebrow">02 — Readiness</div>
  <h1 style="font-size:30pt;margin:4mm 0 5mm;">A readiness score of <span class="serif-accent">75</span></h1>
  <div class="exhibit"><div class="exlabel">Exhibit 1 · Readiness breakdown</div>
    <h3>Readiness is weighted across employees, departments, patterns, and multimodal evidence.</h3>
    <div class="gauge">{donut(75,BLUE)}
      <div class="bars" style="flex:1;">
        <div class="bar-row"><span>Employee coverage</span><span class="bar-track"><span class="bar-fill" style="width:80%"></span></span><span class="bar-val">80</span></div>
        <div class="bar-row"><span>Department spread</span><span class="bar-track"><span class="bar-fill cat-tooling" style="width:70%"></span></span><span class="bar-val">70</span></div>
        <div class="bar-row"><span>Pattern confidence</span><span class="bar-track"><span class="bar-fill cat-people" style="width:72%"></span></span><span class="bar-val">72</span></div>
        <div class="bar-row"><span>Multimodal evidence</span><span class="bar-track"><span class="bar-fill cat-data" style="width:65%"></span></span><span class="bar-val">65</span></div>
      </div></div>
    <div class="caption">Source: Req discovery snapshot v1 · Acme Corp · February 2026</div><div class="mark">Req</div></div>
  <div class="eyebrow" style="margin-top:6mm;">03 — Participation</div>
  <div class="exhibit"><div class="exlabel">Exhibit 2 · Interview participation</div>
    <h3>Three of four invited employees completed the full discovery interview.</h3>
    <div class="funnel"><div class="step"><div class="v">4</div><div class="l">Invited</div></div>
      <div class="step"><div class="v">4</div><div class="l">Started</div></div>
      <div class="step"><div class="v">3</div><div class="l">Completed</div></div>
      <div class="step"><div class="v">75%</div><div class="l">Completion rate</div></div></div>
    <table class="data"><thead><tr><th>Department</th><th>Invited</th><th>Started</th><th>Completed</th></tr></thead>
      <tbody>{dept_rows()}</tbody></table>
    <div class="caption">Source: Req discovery snapshot v1 · Acme Corp</div><div class="mark">Req</div></div>{footer(4)}
</section>

<!-- SIGNALS DIVIDER -->
<section class="page bleed divider">
  <div class="hero"><div class="cat" style="background:var(--magenta);">Signals &amp; Patterns</div>{hero_art(MAG,11)}</div>
  <div class="body"><div class="eyebrow">05 &amp; 06 — Signals and patterns</div>
    <h1 style="margin-top:4mm;">What the interviews revealed</h1>
    <p class="lead">Signals are recurring pain points drawn directly from employee interviews. Patterns are the themes that connect them across departments. Together they explain the readiness score and drive every recommendation.</p>
    <div class="highlight-box">
      <div class="highlight"><p><strong>6 signals</strong> surfaced, led by manual reconciliation in Finance at 0.82 strength.</p></div>
      <div class="highlight"><p><strong>3 patterns</strong> connect these signals across Finance and Operations, all matched to catalog solutions.</p></div>
    </div></div>
</section>

<!-- SIGNALS -->
<section class="page">
  <div class="eyebrow">05 — Signals</div>
  <h1 style="font-size:30pt;margin:4mm 0 3mm;">Recurring pain points</h1>
  <div class="exhibit"><div class="exlabel">Exhibit 3 · Signals ranked by strength</div>
    <h3>Colour encodes category: process, tooling, people, data.</h3>{signal_ranking()}
    <div class="caption">Source: Req discovery snapshot v1 · Acme Corp</div><div class="mark">Req</div></div>
  <div class="card-grid">{signal_cards()}</div>{footer(6)}
</section>

<!-- PULL QUOTE -->
<section class="page dark pullquote">
  <blockquote>The strongest signal isn't a tool problem — it's <span class="accent">manual work</span> that quietly repeats across every close cycle.
    <cite>Key finding · Acme Corp discovery</cite></blockquote>{footer(7)}
</section>

<!-- PATTERNS -->
<section class="page">
  <div class="eyebrow">06 — Patterns</div>
  <h1 style="font-size:30pt;margin:4mm 0 4mm;">Cross-team themes</h1>
  <p class="lead" style="max-width:150mm;">Each pattern connects several signals across departments. Confidence reflects how consistently the theme appeared across interviews and evidence.</p>
  {pattern_cards()}{footer(8)}
</section>

<!-- RECOMMENDATIONS -->
<section class="page">
  <div class="eyebrow">07 — Recommendations</div>
  <h1 style="font-size:30pt;margin:4mm 0 4mm;">Suggested actions</h1>
  <div class="exhibit"><div class="exlabel">Exhibit 4 · Impact vs feasibility</div>
    <h3>Where each recommendation sits. Prioritize high-impact, high-feasibility moves first.</h3>{priority_matrix()}
    <div class="caption">Source: Req discovery snapshot v1 · Acme Corp</div><div class="mark">Req</div></div>
  <div class="card-grid">{rec_cards()}</div>{footer(9)}
</section>

<!-- DELTA -->
<section class="page">
  <div class="eyebrow">04 — What changed since v0</div>
  <h1 style="font-size:30pt;margin:4mm 0 4mm;">Delta from the previous version</h1>
  <p class="lead" style="max-width:150mm;">This version expanded discovery with a second completed cohort. Two findings are new, several strengthened, and one earlier signal has resolved.</p>
  <div class="delta">
    <div class="col add"><h4>New</h4><ul><li>Signal: inconsistent metric definitions</li><li>Signal: undocumented tribal knowledge</li><li>Pattern: fragmented data erodes trust</li></ul></div>
    <div class="col chg"><h4>Changed</h4><ul><li>Manual reconciliation 0.70 → 0.82</li><li>Completion rate 50% → 75%</li><li>Readiness 61 → 75</li></ul></div>
    <div class="col rem"><h4>Resolved</h4><ul><li>Onboarding delay signal cleared</li></ul></div>
  </div>{footer(10)}
</section>

<!-- MEDIA + METHOD -->
<section class="page">
  <div class="eyebrow">08 — Supporting media</div>
  <h1 style="font-size:30pt;margin:4mm 0 4mm;">Evidence base</h1>
  <div class="card-grid">
    {"".join(f'<div class="media-card"><div class="c">{k}</div><div class="k">{n}</div><p>{d}</p></div>' for k,n,d in media)}
  </div>
  <div class="eyebrow" style="margin-top:10mm;">Methodology</div>
  <div class="method" style="margin-top:3mm;">
    <p>Findings draw on structured interviews conducted over WhatsApp and web chat between June 2025 and February 2026. Four employees across Finance and Operations participated; three completed the full discovery flow.</p>
    <dl><dt>Readiness weighting</dt><dd style="font-size:9pt;color:var(--muted);">Employee coverage (30%), department spread (25%), pattern confidence (25%), multimodal evidence (20%).</dd>
    <dt>Review</dt><dd style="font-size:9pt;color:var(--muted);">Reviewed by one external expert and approved by the Req platform team before delivery. Reviewer notes appear in the appendix on approved reports.</dd></dl>
  </div>{footer(11)}
</section>

</body></html>"""

with open("/home/claude/req-report-template.html","w") as f:
    f.write(HTML)
print("HTML pages:", HTML.count('class="page'))
print("bytes:", len(HTML))
