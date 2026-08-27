# Consultant Module — In-Depth Implementation Plan

> Companion to [`CONSULTANT_REDESIGN.md`](./CONSULTANT_REDESIGN.md) (status/handoff). **That** doc =
> where we are. **This** doc = exactly what to build in each phase and how, at a level Cursor
> can execute without re-deriving anything.
>
> Branch: `consultant-redesign`. Verify after every phase with:
> `docker compose run --rm --no-deps frontend sh -c "npm run lint && npm run build"`

---

## 0. Read this first — conventions & ground truth

### Design tokens (Pulse) — never hardcode colors
Use semantic Tailwind tokens only. Canonical set (defined in `frontend/tailwind.config.js` +
`frontend/src/index.css`):

| Use | Token |
|-----|-------|
| Page text | `text-foreground` / `text-muted-foreground` |
| Surfaces | `bg-card`, `bg-muted`, `bg-background` |
| Accent (green) | `text-accent`, `bg-accent`, `bg-accent-muted`, `text-accent-foreground` |
| Status | `text-status-success` / `bg-status-successBg` (and `warning`/`error`/`info` variants) |
| Borders | `border-border` |
| Radius | `rounded-lg` (cards), `rounded-full` (pills/buttons) |

**Deprecated aliases still in some consultant files** (resolve to correct colors but must be
replaced for consistency): `text-text-primary`→`text-foreground`, `text-text-secondary`→
`text-muted-foreground`, `bg-surface-muted`→`bg-muted`, `rounded-card`→`rounded-lg`,
`rounded-button`/`rounded-badge`→`rounded-full`, any `emerald-*`→`status-success*`.

### Frontend API pattern
All calls live in `frontend/src/lib/api.ts` as methods on the `api` object; **every method takes
`token` as its first arg**. Get the token in a page via `useConsultantToken()` (`lib/auth.tsx`).
Errors throw `Error(message)`; pages catch into local `error` state. No react-query — data is
`useEffect` + `useState`; near-real-time via `setInterval` polling.

### Shared UI components (`frontend/src/components/ui`, barrel `index.ts`)
`PageHeader` (title/description/breadcrumbs), `Card` (now supports `title`, `action`, `padding`),
`StatCard`, `Button` (variants primary/secondary/ghost/danger; `icon`, `loading`), `Badge`
(success/warning/info/...), `DataTable`, `Select` (use this, **not** native `<select>`),
`Input`, `Textarea`, `Modal`, `ConfirmDialog`, `EmptyState`, `Skeleton`, `Tabs`,
`Timeline`, `ReadinessGauge`, `ParticipationSummary`.

### Backend consultant endpoints (verified — all under `/api/v1/consultant`)
Controllers in `backend/app/controllers/api/v1/consultant/`. Consultant is scoped to assigned
companies via Pundit `policy_scope`; **max 2 consultants/company**.

| Method | Path | Purpose | FE method in `api.ts` |
|--------|------|---------|-----------------------|
| GET | `/dashboard` | portfolio KPIs, action queue, follow-ups | `consultantDashboard` ✅ |
| GET | `/companies` / `/companies/:id` | assigned companies / detail | `consultantCompany` ✅ |
| GET | `/companies/:id/employees` `/employees/:eid` | **employee roster** (dept, participation_status, timestamps) | **MISSING — add** |
| GET | `/companies/:id/conversations` `/conversations/:cid` | transcripts | `consultantConversations` ✅ |
| GET | `/companies/:id/signals` `/patterns` `/recommendations` | intelligence | `consultantSignals`/`Patterns`/`Recommendations` ✅ |
| GET | `/companies/:id/review_sync` | lightweight collab digest for polling | `consultantReviewSync` ✅ |
| GET | `/companies/:id/reports` `/reports/:rid` `/reports/:rid/download` | reports + PDF | ✅ (workspace + preview/download) |
| GET | `/reports/:rid/workspace` | full workspace payload | `consultantReportWorkspace` ✅ |
| GET/POST | `/reports/:rid/discussions` | anchored discussions (message/finding/section; target co-consultant or employee) | `consultantDiscussions` ✅ / `createReviewDiscussion` ✅ |
| POST | `/reports/:rid/discussions/:did/reply` | **reply to a discussion** | `replyReviewDiscussion` ✅ |
| PATCH | `/reports/:rid/discussions/:did/resolve` | **resolve a discussion** | `resolveReviewDiscussion` ✅ |
| GET/PATCH | `/reports/:rid/review` | review (show / update `status`+`overall_note`) | `consultantReportWorkspace` + `updateConsultantReportReview` ✅ |
| POST | `/reports/:rid/review/submit` | submit review | `submitConsultantReportReview` ✅ |
| GET/POST/PATCH/DELETE | `/reports/:rid/review/comments` | **section comments full CRUD** (+ `resolved` flag) | `addReviewComment` / `updateReviewComment` / `deleteReviewComment` ✅ |
| PATCH | `/reports/:rid/review/section_states/:key` | set section status | `updateSectionState` ✅ |
| GET/POST | `/companies/:id/info_requests` + `/employees/:eid/followup` | **WhatsApp follow-up** to an employee (+ `thread`) | `sendConsultantFollowup` ✅ (+ employee-followup page) |
| GET/POST | `/companies/:id/chat_messages` | **co-consultant chat** | `consultantChatMessages` / `sendConsultantChat` ✅ |
| GET/PATCH | `/notifications` + `/mark_all_read` | notifications | `markAllConsultantNotificationsRead` ✅ |
| GET/PATCH | `/profile` (+ `/avatar`) | consultant profile | `consultantProfile`/`updateConsultantProfile`/`uploadConsultantAvatar` ✅ |

> **CRITICAL — amend capability:** `report_reviews#update` permits **only** `status` and
> `overall_note` (see `report_reviews_controller.rb`). There is **NO endpoint to edit report
> body/snapshot content.** Consultants annotate (comments), set per-section status, write an
> overall note, and submit. **"Amend the report" is not currently possible without new backend
> work.** See Phase 2 for the two options.

---

## Phase 0 — Cleanup & correctness  *(✅ COMPLETE)*

All done and committed on `consultant-redesign`:
- **0a** dead code removed; **0c** workspace bugs fixed; Company Overview rebuilt; Card `action` slot.
- **0b Token sweep — done.** No deprecated aliases remain in `frontend/src/portals/consultant`
  (verify: `grep -rnE "text-text-|bg-surface-muted|rounded-card|rounded-button|rounded-badge|emerald-" frontend/src/portals/consultant` → empty).
  > Note: the shared `components/ui/PageHeader.tsx` still uses `text-text-secondary` internally —
  > out of scope for the consultant sweep, but worth cleaning globally later.
- **0e Empty/error/loading states — done** across consultant pages (pattern: `Skeleton` loading →
  `error` branch → `EmptyState`).
- **Visual verification — done.** Screenshots in `docs/consultant-screenshots/` (dashboard,
  company overview, inbox, conversations, all six workspace steps, submit dialog, mobile sections rail).

**Local dev is now fixed** (was blocked by `:3000`): the frontend Vite proxy honors
`VITE_PROXY_TARGET` (compose sets it to `http://rails:3000`), `vite.config.ts` has
`allowedHosts: true`, and Rails `development.rb` allowlists Docker hostnames. Run:
`docker compose up -d` → `docker compose run --rm rails bundle exec rails db:migrate db:seed` →
dev at `http://localhost:5173`. Screenshot harness: `scripts/manual_test/capture_consultant_screenshots.mjs`.

---

## Phase 1 — IA & information design  *(✅ COMPLETE)*

**Objective:** make the consultant's job legible; one consistent shell; no dead space; employees
and intelligence are first-class. No product decisions required. Mostly frontend; one small API add.

**Progress:** all planned Phase 1 items are now implemented.

### 1.1 Shared page shell / header  *(✅ workspace done; audit the rest)*
- **Done:** `ConsultantReportWorkspace` now renders `PageHeader` (title/description/breadcrumbs/actions).
- **Left:** confirm every other consultant page uses `PageHeader` consistently and page padding is
  uniform via `ConsultantLayout`/`PortalShell`.
- **Acceptance:** every page has identical header rhythm + working breadcrumbs.

### 1.2 Dashboard action queue  *(✅ done)*
- **Problem:** dashboard shows KPIs but the "what needs me now" list is weak.
- **Do:** add a ranked **Action queue** card at top of `ConsultantDashboard.tsx` derived from
  `consultantDashboard` payload: pending reviews first, then employee follow-ups awaiting reply,
  then unread co-consultant messages/notifications. Each row = one click to the exact surface
  (report review / employee thread / chat). Use `Badge` for state, `Button`/`Link` for the action.
- **Acceptance:** a consultant can clear their queue without hunting through company pages.

### 1.3 Company Overview — employees + intelligence  *(✅ done)*
- **Intelligence preview — done:** signals/patterns/recommendations cards wired via
  `consultantSignals`/`consultantPatterns`/`consultantRecommendations` with an empty state.
  *(Optional polish: add a "View report review" CTA on each block.)*
- **Employees (first-class) — done:**
  - Added `consultantEmployees(token, companyId)` in `api.ts` → `GET /companies/:id/employees`.
  - Added an **Employees** card in `ConsultantCompanyOverview.tsx`: name, department,
    participation-status badge, follow-up link, transcript link.
- **Acceptance:** Company Overview is a genuine hub — report, employees, interviews,
  intelligence, collaboration — no dead space at 1280px or mobile.

### 1.4 Conversations list polish  *(✅ done)*
- `ConsultantConversations.tsx` now includes department + last-active columns with row-to-transcript navigation and consistent `DataTable` empty/loading handling.

**Verify Phase 1:** lint+build passing; screenshots added:
- `dashboard-action-queue-phase1.png`
- `company-overview-acme-employees-phase1.png`
- `conversations-acme-phase1.png`
- `inbox-phase1.png`
- `profile-phase1.png`
- `conversation-detail-acme-phase1.png`

---

## Phase 2 — Capability completion  *(✅ COMPLETE)*

**Decisions (confirmed):** Option A suggestions; transcript + findings + section anchors; chat + activity + unread (no @mentions).

### 2.1 "Amend / contribute to the report" — Option A  *(✅ done)*
- `updateReviewComment`, `deleteReviewComment` in `api.ts`.
- `ConsultantAnnotationRail`: suggestions UI when section status is `needs_info`; edit/delete/resolve on own comments.

### 2.2 Wire review discussions (reply + resolve + list)  *(✅ done)*
- `consultantDiscussions`, `resolveReviewDiscussion` in `api.ts` (`replyReviewDiscussion` was already present).
- `ReviewDiscussionThreadList` surfaced in `ConsultantTranscriptPanel`, `ConsultantSharedFindingsPanel`, and sections step.

### 2.3 Co-consultant depth  *(✅ done)*
- `consultantReviewSync` poll every 15s (co-consultant comments/states + discussions refresh).
- Chat unread count badge in workspace header and annotation rail.

**Verify Phase 2:** lint+build passing. Manual: assign `consultant2@reqapp.local` via platform, exercise comment CRUD, discussion reply/resolve, employee ask→WhatsApp, chat unread.

---

## Phase 3 — Polish & motion  *(✅ COMPLETE)*

- **Motion:** `AnimatedNumber` on `ConsultantDashboard` KPIs and workspace context `StatCard`s; `PageTransition` + `ChatBubble` entrance respect `prefers-reduced-motion`.
- **Skeletons:** profile, co-consultant chat panel, workspace 3-column loading, dashboard 6-card KPI skeleton.
- **A11y:** `aria-label` / `aria-expanded` on `EvidenceAskBubble` and workspace chat control; global `:focus-visible` rings via `index.css`.
- **Titles:** `index.html` → `Req`; `usePageMeta` sets `document.title` (`Employee follow-up` route added).

**Verify Phase 3:** lint+build passing; refresh screenshots via `scripts/manual_test/capture_consultant_screenshots.mjs`.

---

## Appendix — quick file map
- Pages: `frontend/src/portals/consultant/*.tsx`
- Workspace: `frontend/src/portals/consultant/workspace/*.tsx`
- API: `frontend/src/lib/api.ts` (consultant block)
- Shared UI: `frontend/src/components/ui/*`
- Backend controllers: `backend/app/controllers/api/v1/consultant/*`
- Backend routes: `backend/config/routes.rb` (`namespace :consultant`)
- Policies: `backend/app/policies/*` (esp. `review_discussion_policy.rb`)

## Appendix — seeded logins
- `consultant@reqapp.local` / `password123` — assigned to Acme + Beta (solo on each).
- `consultant2@reqapp.local` / `password123` — unassigned; assign via platform portal to test the
  2-consultant / co-consultant-chat / discussions paths.
