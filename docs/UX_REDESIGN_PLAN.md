# Portal UX redesign — guided, not cluttered

**Branch:** `polishing-ux`. **Problem (from client feedback):** the portals are
cumbersome; users don't know what action to take next; there's no guidance.
**Goal:** simple, slick, elegant, professional dashboards that *guide* a
time-poor CEO / consultant / admin to the next best action — mobile-friendly, in
the existing Pulse design system.

North-star mockup (client home, real Pulse + real GulfLink data): published as an
artifact — "Guided Client Dashboard".

---

## The one idea

Every portal home today is a **data dump**: equal-weight cards showing *state*.
Redesign them into **guided workspaces** that show *the next action*. The spine,
applied to all three portals:

1. **One primary action** — an elevated, state-aware "do this next" hero. (Hick's Law.)
2. **Status paired with a verb** — no dead numbers; every metric links to its next move.
3. **Progress you can feel** — a journey stepper + the readiness gauge, so people see how close the payoff is. (Goal-gradient, Zeigarnik.)
4. **Their words, not the system's** — "What we found / Your team / Your report", not "Signals / Patterns / Recommendations / Outreaches".
5. **Progressive disclosure** — home shows status + the one thing; detail is one click away. (Miller 7±2.)
6. **A nav that shows state** — grouped sections + live badges (the `Sidebar` already supports `section`/`badge`; unused everywhere).
7. **Calm hierarchy + real mobile** — generous space, one accent, semantic amber only for "needs you", single-column with a thumb-reachable action bar.

**Almost no new backend.** The audit found the guidance data is already fetched;
it's just displayed flat. New endpoints are optional polish (see each section).

---

## Shared foundation (do first — everything else builds on it)

- **`Sidebar` groups + badges.** Turn on `section` grouping and per-item `badge`
  (already supported, `components/layout/Sidebar.tsx`). Every portal's `nav.ts`
  gains sections and badge counts.
- **New shared primitives** in `components/ui/`:
  - `NextStepHero` — the elevated primary-action card (title, why, primary CTA,
    optional readiness ring). Generalise the local `ActionTile`.
  - `PriorityList` / `AttentionItem` — the ranked "also waiting for you" / "needs you" rows.
  - `JourneySteps` — horizontal stepper with done / now / optional states.
  - `OutcomeTile` — number + label + action link (replaces the jargon KPI row).
  - A small `nextBestAction(payload)` selector (pure function) per portal that
    ranks tasks from the existing payload and returns the hero + priority list.
- **Reuse, don't rebuild:** `ReadinessGauge` (built, unused!), `StatCard`,
  `StrengthBar`, `ParticipationSummary`, `Timeline`, `EmptyState`, `Badge`.
- Keep everything on Pulse tokens; add a `.dark` block later (currently light-only).

---

## Client portal (priority 1 — the loudest complaint)

**Home redesign** (`CompanyDashboard.tsx`) → the mockup:
- `NextStepHero` chosen by `nextBestAction(companyDashboard payload)`. Ranking, e.g.:
  report-ready → *Review report* · consultant questions → *Answer N* · stalled
  employees → *Nudge* · profile incomplete → *Add profile* · no docs/team → *Set up*.
- `JourneySteps`: Profile (optional) · Documents · Team invited · Interviews · Report.
- `ReadinessGauge` shown as the hero ring (it's computed today and thrown away).
- 3 `OutcomeTile`s (People engaged / Frictions surfaced / Cross-team themes) — retire the 4 jargon KPIs and the 8-tile grid.
- Two focused panels: **Top of what we found** (top-3 pain points, plain language)
  + **Your consultant** (Nadia card, "N questions need you", primary CTA).
- Slim recent-activity timeline.
- **Nav** → grouped: *Home* · Set up (Profile 0%, Documents, Your team) · Insights
  (Conversations, What we found, Reports v21) · Working with you (Consultant questions ·2, Your consultant) · Settings. Relabel "Intelligence"→"What we found", "Outreaches"→"Consultant questions".
- **Data:** all present in `CompanyDashboardPayload` (readiness score+breakdown,
  questionnaire %, employees_summary, intel_counts, latest_report, unanswered
  questions). Collapse the 4 parallel fetches into fewer / handle partial failure
  so guidance never silently zeroes out.
- **Onboarding**: keep the wizard, but tie completion to value ("unlocks sharper
  insights") and surface the % in the hero, not just inside the page.

## Consultant portal (priority 2 — the nav is broken)

- **Nav lists assigned companies** (the #1 complaint; today it's a static
  Dashboard / Profile / Inbox). New sections: *Needs you* (badge = pending
  reviews + questions) · *Your companies* (each assigned company with a status
  dot + `my_review_status`) · Profile. Data already in `consultantDashboard`
  (`companies[]`, `attention_items[]`) — just thread it into `nav.ts` via a
  layout-level fetch.
- **Home** = a persistent "Needs you" queue (reviews to do, questions to answer),
  then the companies grid. Give the mixed action-queue real group headers.
- **Company overview**: lead with the one action ("Review report v3"); demote the 6 tabs.
- **Workspace** (`ConsultantReportWorkspace`): clarify the edit model (status/comments
  vs hide/note/add overrides live in two places today); make section-status +
  comment controls **work below `lg`** (currently desktop-only, yet required to submit).

## Platform admin (priority 3 — telemetry → work queue)

- Landing leads with a **triage queue**: registrations to approve, trials
  expiring, catalog candidates to review — each an action row. Keep the health
  strip below.
- **Nav badges** on Registrations / Candidates (counts already available).
- Plain admin language; move infra internals (env var names, "LangGraph agent")
  out of user-facing copy.

---

## Sequencing

1. **Shared foundation** — `Sidebar` sections/badges + the 5 new primitives + `nextBestAction` scaffolding.
2. **Client home + nav** (the north-star mockup) — highest visible impact.
3. **Consultant nav + "Needs you" home** — fixes the confirmed nav complaint.
4. **Consultant workspace** clarity + mobile section controls.
5. **Platform triage home + badges.**
6. **Polish pass**: empty states that teach, motion restraint, dark theme, a11y focus states.

Each step is shippable and independently reviewable in the running app.
