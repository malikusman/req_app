# Reviewer Module Redesign — Working Doc & Handoff

> **Status:** Phase 0 in progress (WIP committed & pushed)
> **Branch:** `reviewer-redesign` (branched from `main` @ `01d5d3c`)
> **Last commit:** `e33e7ee` — "Reviewer module Phase 0 (WIP): remove dead code, fix workspace bugs, rebuild company overview"
> **Last updated:** 2026-07-08
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

### ✅ Done in Phase 0 (committed `e33e7ee`, builds clean: `tsc -b && vite build`)
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

### ⛔ Left in Phase 0
- **0b Token unification (light pass):** replace remaining `text-text-secondary` /
  `text-text-primary` / `bg-surface-muted` / `rounded-card` / `rounded-button` / `rounded-badge`
  aliases with Pulse semantic tokens across `ReviewerDashboard.tsx`, `ReviewerFollowups.tsx`,
  `ReviewerProfile.tsx`, `ReviewerCoReviewerChatPanel.tsx`, `ReviewerConversationDetail.tsx`,
  `ReviewerEmployeeFollowup.tsx`. Also sweep for any remaining `emerald-*`/hardcoded colors and
  native `<select>` vs the shared `Select`. **These resolve correctly today — cosmetic/consistency only.**
- **0e Finish empty/error states:** audit each reviewer page for a loading skeleton, a guiding
  empty state, and an error state (several only handle loading).
- **Visual verification (screenshots):** NOT yet done for the new changes — see §7 (local env
  blocker). Build passes but the changes haven't been eyeballed running.

---

## 6. Open product decisions (BLOCK Phase 2 — get answers before building it)

1. **Can reviewers amend report content, or only comment/approve?** Verify backend support first
   (look in `backend/app/controllers/api/v1/reviewer/review_workspace_controller.rb` and the
   report/section models). If no edit capability exists, Phase 2 amend = new backend work.
2. **Amend model if supported:** direct edit of the report snapshot vs *suggestions* the platform
   accepts on approval? (Governance implication — recommend suggestions, not direct edits.)
3. **Employee follow-up placement:** keep the follow-up composer inside the transcript
   (`ReviewerTranscriptPanel`) as the single path, or also expose "ask this employee" from
   findings/sections? (Backend `createReviewDiscussion` with `target_type: 'employee'` already supports anchored asks.)
4. **Co-reviewer depth:** is chat + activity enough, or do we want @mentions / unread counts /
   read receipts? (Affects notification + data model scope.)

---

## 7. How to run & verify

### Build / typecheck (works today)
```bash
docker compose run --rm --no-deps frontend sh -c "npm run build"   # tsc -b && vite build
docker compose run --rm --no-deps frontend sh -c "npm run lint"
```

### Local dev preview — ⚠️ blocker
- Port **3000 is occupied by another project (`helios-platform`)**, and this repo's Vite dev proxy
  (`frontend/vite.config.ts`) targets `http://localhost:3000`, so the local frontend can't reach
  this app's Rails. Our Rails container also isn't running locally.
- **Options for Cursor:**
  1. Stop `helios-platform`, bring up this stack (`docker compose up -d`), seed
     (`docker compose run --rm rails bundle exec rails db:seed`), dev at `localhost:5173`.
  2. Temporary, non-invasive: point the Vite proxy at production to eyeball UI against real data —
     set `server.proxy['/api'].target` to `https://req.pebbleintelligentsolutions.com` (+ `secure:false`),
     restart the frontend container, screenshot, then **revert**. (Read-only navigation only —
     do NOT click submit/destructive actions against prod.)
- **Screenshot harness** used this session lives in the scratchpad (`reviewer-shots.mjs`): a
  dockerized `puppeteer-core` + Chromium script that logs in as `reviewer@reqapp.local` /
  `password123` and captures each reviewer screen. Reuse/adapt it for before/after shots.

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
1. Get a working preview (see §7) and **screenshot the Phase 0 changes** — verify the workspace
   (all 6 steps), the new Company Overview, and mobile widths actually look right.
2. Finish **Phase 0b** (token sweep) and **Phase 0e** (empty/error states); rebuild; commit.
3. Answer the **§6 decisions** with the product owner.
4. Start **Phase 1** (dashboard action queue + Company Overview intelligence preview + shared page shell).
5. Keep this doc updated — flip statuses as phases land.
