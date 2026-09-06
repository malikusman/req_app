# Consultant Module Redesign — Working Doc & Handoff

> **Status:** Phase 0–2 complete, **Phase 3 complete** (consultant redesign ready for merge review)
> **Branch:** `consultant-redesign` (branched from `main` @ `01d5d3c`)
> **Last commit:** `e33e7ee` — "Consultant module Phase 0 (WIP): remove dead code, fix workspace bugs, rebuild company overview"
> **Last updated:** 2026-07-09
> **Author of this pass:** Claude Code (handing off to Cursor)

This doc is the single source of truth for the consultant-portal overhaul. Read it top to
bottom before continuing. It covers **what the module is meant to do**, **what's broken**,
**the phased plan**, **exactly what's done vs left**, **open product decisions**, and
**how to run/verify**.

---

## 1. Goal (what the consultant does)

External expert consultants are assigned to one or more companies and provide independent QA
on the AI-generated discovery reports before they reach the client. A consultant must be able to:

- See everything a company's employees shared (interviews / transcripts / intelligence).
- Ask follow-up questions to **specific employees** over WhatsApp.
- Comment on and set status per **report section** (reviewed / needs clarification).
- Collaborate with a **co-consultant** (chat + see their progress) when two are assigned.
- Contribute to / amend the report and submit a governed review for platform approval.

**The complaint driving this work:** the module is scattered, unprofessional, and has
duplicated/half-finished surfaces. This effort makes it coherent, professional, and complete.

---

## 2. Current architecture (as-is)

### Routes (`frontend/src/App.tsx`, under `/consultant/*`)
- `dashboard` → `ConsultantDashboard`
- `profile` → `ConsultantProfile`
- `followups` → **redirect** to `/consultant/inbox`
- `inbox` → `ConsultantFollowups` (tabs: Followups / Notifications)
- `companies/:companyId` → `ConsultantCompanyOverview`
- `companies/:companyId/reports/:reportId/review` → `ConsultantReportWorkspace` (the 6-step workspace)
- `companies/:companyId/conversations` → `ConsultantConversations`
- `companies/:companyId/conversations/:conversationId` → `ConsultantConversationDetail`
- `companies/:companyId/employees/:employeeId/followup` → `ConsultantEmployeeFollowup`

### Key files
- Pages: `frontend/src/portals/consultant/*.tsx`
- Report workspace: `frontend/src/portals/consultant/workspace/*.tsx`
  (`ConsultantReportWorkspace` orchestrates; `ConsultantAnnotationRail`, `ConsultantChatDrawer`,
  `ConsultantPdfDrawer`, `ConsultantTranscriptPanel`, `ConsultantSectionContent`,
  `ConsultantSharedFindingsPanel`, `ConsultantEmployeeProfileCard`, `EvidenceAskBubble`,
  `coConsultantActivity.ts`, `workspaceSteps.ts`)
- Nav: `frontend/src/portals/consultant/nav.ts` (+ dynamic company-scoped items in `ConsultantLayout`)
- API layer: `frontend/src/lib/api.ts` (consultant methods) — every call takes an explicit `token`
- Backend: `backend/app/controllers/api/v1/consultant/*`, routes in `backend/config/routes.rb`
  (`api/v1/consultant/**`), services in `backend/app/services/review_discussions/*` and
  `backend/app/services/consultants/*`, policies incl. `review_discussion_policy`.

### Backend capabilities that already exist (frontend under-uses some)
- Report review lifecycle: per-section state (`pending` / `approved` / `needs_info`),
  section comments, overall note, submit → platform approval.
- Review **discussions** anchored to a message / finding / section, targeted at a
  co-consultant **or** an employee (the employee case routes out via WhatsApp).
- Co-consultant chat + co-consultant activity/progress.
- Consultant↔employee WhatsApp follow-up threads (hidden from the company API).
- Notifications.
- **Assignment cap: max 2 consultants per company.**

> ⚠️ **Confirm on the backend (not yet re-verified this session):** whether a consultant can
> **amend/edit report content** or only comment/approve. The two deep-dive exploration agents
> for consultant FE/BE were interrupted at the session boundary — findings were folded in from
> direct file reads + screenshots, but the "can consultants edit report text?" question is still
> **open** and gates Phase 2 (see §6 Decisions).

---

## 3. Problems found (the analysis)

Grounded in reading every consultant file **and** screenshots of all 8 live consultant screens
(production). Screenshots saved in the session scratchpad `rev-shots/` (dashboard,
report-review, company-overview, conversations, conversation-detail, inbox,
employee-followup, profile).

**IA / navigation**
1. **Duplicate/dead doors:** an orphan `ConsultantChat` page + `/companies/:id/chat` route, and a
   `ConsultantReportReview` shim that just re-exported the workspace. (FIXED in Phase 0.)
2. **Company Overview was a near-empty hub** — only "Open report review" + one "Conversations"
   button, ~60% blank; employees, follow-ups, intelligence, chat not reachable from it. (REBUILT in Phase 0.)
3. Two entry points to the same chat (page vs drawer) confused the model. (Consolidated on the drawer.)

**Report workspace bugs**
4. Right rail showed "Section review — no comments" on steps that have **no section**
   (Context/Evidence/Synthesis). (FIXED — rail only shows on the `sections` step.)
5. Stepper showed steps **pre-checked as done** at first load (done = "data exists"). (FIXED —
   done now means the consultant actually visited the exploratory step, or real completion for
   sections/collaborate/submit.)
6. **Co-consultant chat shown to solo consultants** (backend disables it, UI still offered it). (FIXED — gated on `hasCoConsultants`.)
7. **15s poll clobbered the in-progress "overall note"** textarea (re-seeded on every refresh). (FIXED — seed once via ref.)
8. Used raw `window.confirm` for submit. (FIXED — `ConfirmDialog`.)
9. Section status/comments rail was **desktop-only** (`hidden lg:block`) → mobile consultants
   couldn't set status or comment. (FIXED — rail stacks on mobile.)

**Visual consistency**
10. Hardcoded `emerald-*` colors instead of theme tokens. (FIXED in workspace; a few remain elsewhere — see Phase 0b.)
11. Token-alias drift (`text-text-secondary`, `bg-surface-muted`, `rounded-card`) vs the
    Pulse semantic tokens (`text-muted-foreground`, `bg-muted`, `rounded-lg`). These **resolve
    to correct Pulse colors** (not a visual bug) but are inconsistent. (Light pass pending — Phase 0b.)
12. Large empty/dead space on several pages; thin/absent empty & error states. (Partly addressed; more in Phase 0e.)

---

## 4. The plan (phases)

**Phase 0 — Cleanup & correctness** *(current)* — no new backend, no product decisions needed.
Delete dead code, fix the workspace bugs, make the Company Overview a real hub, unify tokens,
mobile parity, better empty/error states. Goal: the existing feature set, but coherent and correct.

**Phase 1 — IA & information design** — make the consultant's job legible:
- Tighten the dashboard "action queue" (what needs me, ranked).
- Company Overview → add an **intelligence preview** (signals/patterns/recommendations) using
  the consultant intelligence endpoint, and surface employees as first-class (roster with
  per-employee follow-up entry point).
- Consistent page shell/header across all consultant pages (workspace currently uses a bespoke header).

**Phase 2 — Capability completion** *(needs decisions in §6)*:
- Consultant **amend/contribute to report** (inline edits/suggestions) — **iff** backend supports it.
- Wire **review discussions reply** (currently read-mostly) and employee-ask from findings/sections.
- Co-consultant collaboration depth (mentions, read state).

**Phase 3 — Polish & motion** — micro-interactions, loading/skeleton consistency, contrast &
a11y audit, reduced-motion, final screenshots, and a proper `<title>`.

---

## 5. Status — done vs left

### ✅ Done in Phase 0
- **0a Dead code removed:**
  - Deleted `ConsultantChat.tsx` + its route + import.
  - Deleted `ConsultantReportReview.tsx` shim; review route now renders `ConsultantReportWorkspace` directly.
  - Removed 5 unused API methods from `lib/api.ts`: `consultantMe`, `consultantCompanies`,
    `consultantReport`, `consultantReportReview`, `consultantMediaAttachments`.
- **0c Workspace bugs fixed** (`workspace/ConsultantReportWorkspace.tsx`, `workspace/ConsultantAnnotationRail.tsx`):
  step-aware rail (`showRail = activeStep === 'sections'`; grid widens to 2-col otherwise),
  honest `stepComplete` via a `visited` set, `hasCoConsultants` gating for all chat affordances,
  note seeded once via `noteSeeded` ref, `ConfirmDialog` for submit, `status-*` tokens instead of emerald.
- **0d Mobile parity:** section rail stacks under main on mobile (`border-t lg:border-l`).
- **0e (partial):** Company Overview rebuilt into a hub (report card + interview roster linking
  to transcripts + quick actions + collaboration state) using existing `consultantCompany` +
  `consultantConversations` APIs; added optional `action` slot to shared `ui/Card`.
- **0b Token unification complete:** replaced remaining consultant-portal token aliases with
  semantic Pulse tokens across dashboard, inbox, profile, co-consultant chat, and follow-up pages.
- **0e state pass complete:** added/normalized loading skeletons and empty/error states where
  consultant pages were thin.
- **Visual verification complete:** captured screenshots under `docs/consultant-screenshots/`:
  dashboard, company overview, inbox, conversations, workspace all six steps, submit dialog, and mobile sections rail.

### ✅ Done in Phase 1
- Dashboard action queue, employees roster on Company Overview, conversations polish, shell/breadcrumb audit.
- Screenshots: `docs/consultant-screenshots/*-phase1.png`.

### ✅ Done in Phase 2
- **2.1 Suggestions:** `ConsultantAnnotationRail` reframes `needs_info` comments as suggested changes;
  `updateReviewComment` / `deleteReviewComment` in `api.ts`; edit, resolve/reopen, delete on own comments.
- **2.2 Discussions:** `consultantDiscussions`, `resolveReviewDiscussion` in `api.ts`; threaded
  reply/resolve UI (`ReviewDiscussionThreadList`) on transcript, findings, and report sections.
- **2.3 Co-consultant:** `consultantReviewSync` lightweight poll (replaces full workspace reload);
  chat unread badge shows count of unseen messages.

### ✅ Done in Phase 3
- **Document titles:** `index.html` default `Req`; `usePageMeta` sets `Title · Req` per route (incl. employee follow-up).
- **Motion:** `AnimatedNumber` on dashboard KPIs and workspace context stats; page transitions + chat bubble entrance already via `PortalShell` / `ChatBubble` with `prefers-reduced-motion`.
- **Skeletons:** profile, co-consultant chat, workspace loading, dashboard KPI row (6 cards).
- **A11y:** `aria-label` / `aria-expanded` on evidence ask control and workspace chat; icon buttons decorated with `aria-hidden` on glyphs.

### ⛔ Left
- Merge `consultant-redesign` → `main` when product signs off.

---

## 6. Product decisions for Phase 2 *(confirmed 2026-07-09)*

1. **Amend model — Option A (suggestions):** section status `needs_info` + comments as change
   requests; comment edit/delete/resolve wired in the annotation rail. No direct report-body edits.
2. **Employee follow-up placement:** transcript composer **plus** anchored ask from findings and
   report sections (via `EvidenceAskBubble` + discussion threads).
3. **Co-consultant depth:** chat + activity digest + unread counts + `review_sync` polling (no
   @mentions in Phase 2).

---

## 7. How to run & verify

### Build / typecheck (works today)
```bash
docker compose run --rm --no-deps frontend sh -c "npm run build"   # tsc -b && vite build
docker compose run --rm --no-deps frontend sh -c "npm run lint"
```

### Local dev preview (working setup)
- Bring stack up and seed:
  `docker compose up -d`
  `docker compose run --rm rails bundle exec rails db:migrate db:seed`
- Dev at `http://localhost:5173`.
- Vite now supports a configurable proxy target (`VITE_PROXY_TARGET`) and `allowedHosts: true`
  for Dockerized screenshot/QA flows.
- Rails development host allowlist includes Docker preview hostnames (`frontend`, `rails`,
  `host.docker.internal`) so consultant login works during containerized browser checks.
- Screenshot harness: `scripts/manual_test/capture_consultant_screenshots.mjs` (plus containerized
  Playwright runner) with outputs in `docs/consultant-screenshots/`.

### Seeded consultant logins
- `consultant@reqapp.local` / `password123` — published profile, assigned to Acme + Beta (solo on each).
- `consultant2@reqapp.local` / `password123` — draft profile, **not** assigned (use to test the
  2-consultant / co-consultant chat path by assigning via the platform portal).

---

## 8. Production / deployment context (unrelated to this branch, but useful)
- Live: `https://req.pebbleintelligentsolutions.com` on a DigitalOcean droplet **142.93.240.146**
  (Ubuntu 24.04, 2 vCPU / 4 GB, NYC1), Docker Compose + Caddy on :80 behind Cloudflare (**Flexible** SSL).
- Deploy: push to `main` → GitHub Actions (`.github/workflows/deploy.yml`) SSHes in and runs
  `scripts/deploy/deploy.sh` (`git reset --hard origin/main` → compose build/up → `db:prepare`).
- **Therefore:** this `consultant-redesign` branch will NOT auto-deploy. Merge to `main` to ship.
  `main` currently = old consultant UI + the Pulse redesign (commit `01d5d3c`).

---

## 9. Suggested next actions for Cursor (in order)
1. Product review of `consultant-redesign` branch (screenshots in `docs/consultant-screenshots/`).
2. Merge to `main` when approved (auto-deploys to production).
