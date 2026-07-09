# Reviewer Module Redesign — Working Doc & Handoff

> **Status:** Phase 0 complete, Phase 1 complete, **Phase 2 complete** (ready for Phase 3 polish)
> **Branch:** `reviewer-redesign` (branched from `main` @ `01d5d3c`)
> **Last commit:** `e33e7ee` — "Reviewer module Phase 0 (WIP): remove dead code, fix workspace bugs, rebuild company overview"
> **Last updated:** 2026-07-09
> **Author of this pass:** Claude Code (handing off to Cursor)

This doc is the single source of truth for the reviewer-portal overhaul. Read it top to
bottom before continuing. It covers **what the module is meant to do**, **what's broken**,
**the phased plan**, **exactly what's done vs left**, **open product decisions**, and
**how to run/verify**.

---

## 1. Goal (what the reviewer does)

External expert reviewers are assigned to one or more companies and provide independent QA
on the AI-generated discovery reports before they reach the client. A reviewer must be able to:

- See everything a company's employees shared (interviews / transcripts / intelligence).
- Ask follow-up questions to **specific employees** over WhatsApp.
- Comment on and set status per **report section** (reviewed / needs clarification).
- Collaborate with a **co-reviewer** (chat + see their progress) when two are assigned.
- Contribute to / amend the report and submit a governed review for platform approval.

**The complaint driving this work:** the module is scattered, unprofessional, and has
duplicated/half-finished surfaces. This effort makes it coherent, professional, and complete.

---

## 2. Current architecture (as-is)

### Routes (`frontend/src/App.tsx`, under `/reviewer/*`)
- `dashboard` → `ReviewerDashboard`
- `profile` → `ReviewerProfile`
- `followups` → **redirect** to `/reviewer/inbox`
- `inbox` → `ReviewerFollowups` (tabs: Followups / Notifications)
- `companies/:companyId` → `ReviewerCompanyOverview`
- `companies/:companyId/reports/:reportId/review` → `ReviewerReportWorkspace` (the 6-step workspace)
- `companies/:companyId/conversations` → `ReviewerConversations`
- `companies/:companyId/conversations/:conversationId` → `ReviewerConversationDetail`
- `companies/:companyId/employees/:employeeId/followup` → `ReviewerEmployeeFollowup`

### Key files
- Pages: `frontend/src/portals/reviewer/*.tsx`
- Report workspace: `frontend/src/portals/reviewer/workspace/*.tsx`
  (`ReviewerReportWorkspace` orchestrates; `ReviewerAnnotationRail`, `ReviewerChatDrawer`,
  `ReviewerPdfDrawer`, `ReviewerTranscriptPanel`, `ReviewerSectionContent`,
  `ReviewerSharedFindingsPanel`, `ReviewerEmployeeProfileCard`, `EvidenceAskBubble`,
  `coReviewerActivity.ts`, `workspaceSteps.ts`)
- Nav: `frontend/src/portals/reviewer/nav.ts` (+ dynamic company-scoped items in `ReviewerLayout`)
- API layer: `frontend/src/lib/api.ts` (reviewer methods) — every call takes an explicit `token`
- Backend: `backend/app/controllers/api/v1/reviewer/*`, routes in `backend/config/routes.rb`
  (`api/v1/reviewer/**`), services in `backend/app/services/review_discussions/*` and
  `backend/app/services/reviewers/*`, policies incl. `review_discussion_policy`.

### Backend capabilities that already exist (frontend under-uses some)
- Report review lifecycle: per-section state (`pending` / `approved` / `needs_info`),
  section comments, overall note, submit → platform approval.
- Review **discussions** anchored to a message / finding / section, targeted at a
  co-reviewer **or** an employee (the employee case routes out via WhatsApp).
- Co-reviewer chat + co-reviewer activity/progress.
- Reviewer↔employee WhatsApp follow-up threads (hidden from the company API).
- Notifications.
- **Assignment cap: max 2 reviewers per company.**

> ⚠️ **Confirm on the backend (not yet re-verified this session):** whether a reviewer can
> **amend/edit report content** or only comment/approve. The two deep-dive exploration agents
> for reviewer FE/BE were interrupted at the session boundary — findings were folded in from
> direct file reads + screenshots, but the "can reviewers edit report text?" question is still
> **open** and gates Phase 2 (see §6 Decisions).

---

## 3. Problems found (the analysis)

Grounded in reading every reviewer file **and** screenshots of all 8 live reviewer screens
(production). Screenshots saved in the session scratchpad `rev-shots/` (dashboard,
report-review, company-overview, conversations, conversation-detail, inbox,
employee-followup, profile).

**IA / navigation**
1. **Duplicate/dead doors:** an orphan `ReviewerChat` page + `/companies/:id/chat` route, and a
   `ReviewerReportReview` shim that just re-exported the workspace. (FIXED in Phase 0.)
2. **Company Overview was a near-empty hub** — only "Open report review" + one "Conversations"
   button, ~60% blank; employees, follow-ups, intelligence, chat not reachable from it. (REBUILT in Phase 0.)
3. Two entry points to the same chat (page vs drawer) confused the model. (Consolidated on the drawer.)

**Report workspace bugs**
4. Right rail showed "Section review — no comments" on steps that have **no section**
   (Context/Evidence/Synthesis). (FIXED — rail only shows on the `sections` step.)
5. Stepper showed steps **pre-checked as done** at first load (done = "data exists"). (FIXED —
   done now means the reviewer actually visited the exploratory step, or real completion for
   sections/collaborate/submit.)
6. **Co-reviewer chat shown to solo reviewers** (backend disables it, UI still offered it). (FIXED — gated on `hasCoReviewers`.)
7. **15s poll clobbered the in-progress "overall note"** textarea (re-seeded on every refresh). (FIXED — seed once via ref.)
8. Used raw `window.confirm` for submit. (FIXED — `ConfirmDialog`.)
9. Section status/comments rail was **desktop-only** (`hidden lg:block`) → mobile reviewers
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

**Phase 1 — IA & information design** — make the reviewer's job legible:
- Tighten the dashboard "action queue" (what needs me, ranked).
- Company Overview → add an **intelligence preview** (signals/patterns/recommendations) using
  the reviewer intelligence endpoint, and surface employees as first-class (roster with
  per-employee follow-up entry point).
- Consistent page shell/header across all reviewer pages (workspace currently uses a bespoke header).

**Phase 2 — Capability completion** *(needs decisions in §6)*:
- Reviewer **amend/contribute to report** (inline edits/suggestions) — **iff** backend supports it.
- Wire **review discussions reply** (currently read-mostly) and employee-ask from findings/sections.
- Co-reviewer collaboration depth (mentions, read state).

**Phase 3 — Polish & motion** — micro-interactions, loading/skeleton consistency, contrast &
a11y audit, reduced-motion, final screenshots, and a proper `<title>`.

---

## 5. Status — done vs left

### ✅ Done in Phase 0
- **0a Dead code removed:**
  - Deleted `ReviewerChat.tsx` + its route + import.
  - Deleted `ReviewerReportReview.tsx` shim; review route now renders `ReviewerReportWorkspace` directly.
  - Removed 5 unused API methods from `lib/api.ts`: `reviewerMe`, `reviewerCompanies`,
    `reviewerReport`, `reviewerReportReview`, `reviewerMediaAttachments`.
- **0c Workspace bugs fixed** (`workspace/ReviewerReportWorkspace.tsx`, `workspace/ReviewerAnnotationRail.tsx`):
  step-aware rail (`showRail = activeStep === 'sections'`; grid widens to 2-col otherwise),
  honest `stepComplete` via a `visited` set, `hasCoReviewers` gating for all chat affordances,
  note seeded once via `noteSeeded` ref, `ConfirmDialog` for submit, `status-*` tokens instead of emerald.
- **0d Mobile parity:** section rail stacks under main on mobile (`border-t lg:border-l`).
- **0e (partial):** Company Overview rebuilt into a hub (report card + interview roster linking
  to transcripts + quick actions + collaboration state) using existing `reviewerCompany` +
  `reviewerConversations` APIs; added optional `action` slot to shared `ui/Card`.
- **0b Token unification complete:** replaced remaining reviewer-portal token aliases with
  semantic Pulse tokens across dashboard, inbox, profile, co-reviewer chat, and follow-up pages.
- **0e state pass complete:** added/normalized loading skeletons and empty/error states where
  reviewer pages were thin.
- **Visual verification complete:** captured screenshots under `docs/reviewer-screenshots/`:
  dashboard, company overview, inbox, conversations, workspace all six steps, submit dialog, and mobile sections rail.

### ✅ Done in Phase 1
- Dashboard action queue, employees roster on Company Overview, conversations polish, shell/breadcrumb audit.
- Screenshots: `docs/reviewer-screenshots/*-phase1.png`.

### ✅ Done in Phase 2
- **2.1 Suggestions:** `ReviewerAnnotationRail` reframes `needs_info` comments as suggested changes;
  `updateReviewComment` / `deleteReviewComment` in `api.ts`; edit, resolve/reopen, delete on own comments.
- **2.2 Discussions:** `reviewerDiscussions`, `resolveReviewDiscussion` in `api.ts`; threaded
  reply/resolve UI (`ReviewDiscussionThreadList`) on transcript, findings, and report sections.
- **2.3 Co-reviewer:** `reviewerReviewSync` lightweight poll (replaces full workspace reload);
  chat unread badge shows count of unseen messages.

### ⛔ Left
- **Phase 3** — motion, a11y/contrast, per-route `<title>`, final screenshot pass.

---

## 6. Product decisions for Phase 2 *(confirmed 2026-07-09)*

1. **Amend model — Option A (suggestions):** section status `needs_info` + comments as change
   requests; comment edit/delete/resolve wired in the annotation rail. No direct report-body edits.
2. **Employee follow-up placement:** transcript composer **plus** anchored ask from findings and
   report sections (via `EvidenceAskBubble` + discussion threads).
3. **Co-reviewer depth:** chat + activity digest + unread counts + `review_sync` polling (no
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
  `host.docker.internal`) so reviewer login works during containerized browser checks.
- Screenshot harness: `scripts/manual_test/capture_reviewer_screenshots.mjs` (plus containerized
  Playwright runner) with outputs in `docs/reviewer-screenshots/`.

### Seeded reviewer logins
- `reviewer@reqapp.local` / `password123` — published profile, assigned to Acme + Beta (solo on each).
- `reviewer2@reqapp.local` / `password123` — draft profile, **not** assigned (use to test the
  2-reviewer / co-reviewer chat path by assigning via the platform portal).

---

## 8. Production / deployment context (unrelated to this branch, but useful)
- Live: `https://req.pebbleintelligentsolutions.com` on a DigitalOcean droplet **142.93.240.146**
  (Ubuntu 24.04, 2 vCPU / 4 GB, NYC1), Docker Compose + Caddy on :80 behind Cloudflare (**Flexible** SSL).
- Deploy: push to `main` → GitHub Actions (`.github/workflows/deploy.yml`) SSHes in and runs
  `scripts/deploy/deploy.sh` (`git reset --hard origin/main` → compose build/up → `db:prepare`).
- **Therefore:** this `reviewer-redesign` branch will NOT auto-deploy. Merge to `main` to ship.
  `main` currently = old reviewer UI + the Pulse redesign (commit `01d5d3c`).

---

## 9. Suggested next actions for Cursor (in order)
1. Phase 3 polish: motion (`PageTransition`, `AnimatedNumber`), skeleton consistency, a11y/contrast, per-route titles.
2. Final screenshot pass (light + mobile) and update this doc when Phase 3 lands.
3. Merge `reviewer-redesign` → `main` when product signs off (auto-deploys to production).
