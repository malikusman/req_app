# Stage 1 pricing

How the Doc 17 Stage 1 fee is worked out, reviewed, put to the client and agreed, what it
stores, what it lets out, and what is still open. For where P24 sits among the other model
steps, see [AGENTS.md](AGENTS.md) §4 row 21 and Flow 10. For what each portal shows, see
[APPLICATION_GUIDE.md](APPLICATION_GUIDE.md) §3.10a (administrator), §4.4b (client) and
§5.7 (consultant).

## The path

```
KEY_PERSON_DISCOVERY ──(key user's conversation done, every count a number)──▶ STAGE_1_PRICING
   quote PROPOSED ──(super admin approves; below the floor only with a reason)──▶ ISSUED
   ISSUED ──(key user accepts)──▶ ACCEPTED, engagement ──▶ STAGE_1_ACTIVE (staff can be invited)
   ISSUED ──(declines)──▶ DECLINED · (validity passes)──▶ EXPIRED · (plan changes)──▶ SUPERSEDED
   PROPOSED ──(adjust price / correct inputs)──▶ SUPERSEDED + a new PROPOSED version
   PROPOSED ──(sent back with a note)──▶ REJECTED
   after DECLINED / EXPIRED / REJECTED: a fresh version, or Mjadi closes the engagement (CLOSED, with a reason)
```

1. **Proposed by the platform.** When the engagement reaches `STAGE_1_PRICING`, an
   `after_commit` on `Engagement` queues `ProposeStage1Job`, which runs
   `Pricing::ProposeStage1`. It reads the inputs (`Pricing::Stage1Inputs`), works out the
   fee (`Pricing::Stage1Calculator`), and saves version 1 with a template scope statement
   (`Pricing::ScopeTemplate`). It then emails the super admins. An engagement that reached
   pricing before quotes existed (Gulf Trading's #23) gets its quote from *Calculate Stage 1
   proposal* on the platform's company page.
2. **Explained by P24.** `ExplainStage1QuoteJob` runs `Pricing::Explainer` on every new
   version. If P24's reply passes the checks, it replaces the scope statement and adds the
   administrator's explanation. If not, the template stays.
3. **Reviewed by a super admin** (`Pricing::Review`, `PricingPolicy`). They can:
   - **approve and issue** (`valid_until` = today + the rate card's validity days);
   - **adjust the price**, with a structured reason;
   - **correct the deep dives, locations or country**;
   - **send it back** with a note, which tells the lead consultant;
   - **prepare a fresh version** after a decline, an expiry or a send-back;
   - **close the engagement**, with a reason.

   Any platform user can see all of this; only `super_admin` can act. The controller and
   the service both check the role.
4. **Read by the client** (`Pricing::ClientQuoteView`). The key user is told in the portal,
   and that notification's own email carries it too. Anyone at the company can read the
   proposal at `/company/proposal` and download its PDF (`Pricing::QuotePdf`, through
   Gotenberg).
5. **Agreed by the key user** (`Pricing::ClientDecision`). Accepting needs the
   acknowledgement box. It records who accepted and when, and moves the engagement to
   `STAGE_1_ACTIVE` in the same transaction. Declining keeps the reason they give. Mjadi
   staff impersonating the client can't do either. The super admins are emailed the
   outcome and the lead consultant is notified in the portal. `ExpireQuotesJob` runs
   overnight and expires unanswered quotes past their date.
6. **Mjadi may change the plan or the languages** until the client accepts. In pricing, a
   change supersedes the open quote with a fresh calculation. The consultant does this
   with *Who takes part* on the leadership page; the platform does it through the
   engagement update. The client's scope card stays closed once pricing starts.

## The fee

Every figure is computed in code (`Pricing::Stage1Calculator`, BigDecimal). The model never
produces a number.

| Line | Amount |
|---|---|
| Base engagement | `base_fee` |
| Team conversations | participants × `per_participant_fee` |
| Detailed sessions | deep dives × `per_deep_dive_fee`; deep dives default to the participant count, kept within 3–5 |
| Languages, locations and departments | (languages − 1) × `per_extra_language` + (locations − 1) × `per_extra_location` + departments over `departments_threshold` × `per_department_over_threshold`; no line when zero |
| Adjustment | only when an administrator changed the price: the difference, so the calculated lines still show |

- **Rounding:** each line is a whole unit of currency, and the subtotal is the sum of the
  lines. VAT is the subtotal × the client country's rate from the rate card, half up to the
  cent. There's no hidden rounding line.
- **Additional-participant rate:** stated on every quote.
- **Behind the fee:**
  - consultant hours per activity, at the consultant's internal cost;
  - AI usage per participant, deep dive and key person;
  - platform allocation and licences.

  Together these are the fully loaded cost. Margin = (subtotal − cost) ÷ subtotal, and it
  is compared with the floor.
- **Risk signals and confidence:**
  - no comparables;
  - several languages;
  - several locations;
  - participants not yet named;
  - one person from a department in a larger team;
  - placeholder rates.
- **Stops rather than guesses:** a rate card missing a value, a country with no tax rate,
  or a count that isn't a number stops the calculation, and the super admins are emailed.

Country and locations come from free text at onboarding (O3). The country is read as an ISO
code (UAE, Saudi Arabia, KSA and so on). Locations are counted from the profile list, which
can over-count ("Dubai, UAE; Riyadh, KSA" reads as four), so the administrator can correct
both.

## What it stores (Doc 06 §10)

| Table | Doc 06 | Notes |
|---|---|---|
| `rate_card_versions` | §10.3 RateCardVersion | `rates` by skill × delivery source (internal cost, charge rate); `stage1` holds the formula's values and quote terms. Never edited. v1 is seeded with `placeholder: true` |
| `margin_floor_versions` | §10.4 | 0.60 at launch. Never edited; a change is a new version with a reason |
| `quotes` | §10.10 QuoteRecord | `quote_stage` covers Stage 2/3 too. Figures are fixed at creation (validation). `estimate` and `internal` are INTERNAL_COMMERCIAL. One open (`PROPOSED`/`ISSUED`) and one `ACCEPTED` per engagement and stage, enforced by partial unique indexes |
| `estimate_overrides` | §10.11 | `ADJUST` or `FLOOR_OVERRIDE`. Can't be saved without a structured reason (Doc 17 §9.3, `BUNDLE` included); `OTHER` needs words |
| `quote_events` | Doc 17 §18 | proposed, explained, explanation_fallback, inputs_changed, adjusted, floor_overridden, issued, viewed, pdf_generated, accepted, declined, expired, rejected, superseded |
| `engagements.currency` | §3.4 | AED by default |
| `engagement_participants.added_after_pricing` | §3.6 | set by the invite path and for managers added once pricing started |

Admin actions also go to `PlatformAuditLog`, and engagement moves go to `status_history`.
Every P24 call writes an `AiRun` (stage `P24`).

## Staff invitations

`Engagements::StaffInvitations` is checked at the top of `InviteEmployeeService`. Every
staff invitation goes through it: single, bulk, a platform user impersonating the client,
and the scripts.

- Before `STAGE_1_ACTIVE`: **409** `invitations_locked`.
- After acceptance, an invitation that takes non-declined staff (invited since the
  engagement began) past `participants_included`: **409** `confirm_additional`, with the
  numbers and the rate. The same call with `confirm_additional: true` invites them and
  flags their participant row (a new `INVITED` row if they weren't planned).
- A bulk invitation is checked as a whole, including every row's validity, before anyone
  is invited.
- `SendEmployeeInvitationJob` holds an invitation if the engagement isn't open.
- Companies from before engagements are unaffected.

`Pricing::AdditionalParticipants` shows the running total to the client and to Mjadi.
Nothing is invoiced.

## The firewall — what never leaves

- **P24 sees only the pricing context.** `Pricing::Stage1Context` holds only: the
  engagement's scope, the participant plan, the fee components (formatted), hours,
  comparables (sizes and fees, no names), the margin (marked INTERNAL_COMMERCIAL),
  versions and risk signals. It never holds a transcript, a finding, management context,
  a consultant note or an onboarding answer.
- **Client-facing outputs use one whitelist.** Every client-facing output is built from
  `Pricing::ClientQuoteView`'s field list: the portal, the dashboard summary, the PDF, the
  notification and the consultant's view. Cost, hours, margin, rates, override reasons and
  the explanation never appear. Specs deep-scan the JSON, the PDF's HTML and the
  notification text for them.
- **P24's reply is checked** (`Pricing::ExplanationValidator`, P24 §8). A reply is dropped
  if:
  - any amount isn't one the platform computed;
  - the client's text contains anything internal, AI vocabulary or methodology words;
  - anything anywhere reads as discount or negotiation language;
  - the platform flagged risks and none are named ("no significant risks" doesn't count).

  Once a quote has left the administrator, nothing is written to it.
- **The discovery side never sees pricing.** `Companies::AgentContext`, the employee
  interview and the report assembly don't read `quotes`.

## Switches and models

- `AI_PRICING_EXPLAINER=false`, or no model: no P24. The administrator sees the computed
  derivation and the client gets the template, and the quote can still be approved.
- `PRICING_EXPLAINER_MODEL` falls back to `OPENAI_MODEL`. The production model isn't
  decided (Doc 05 §3.2).
- Outside production, a company's `pricing_scripted_replies` setting (or
  `PRICING_SCRIPTED_REPLIES=1`) runs P24 on `Pricing::ScriptedClient`, for the demo, the
  browser test and the benchmark only.
- Rate card and floor values live in the database, versioned. A super admin changes them
  on **Pricing → Rates and margin floor** (`/platform/pricing/rates`, `Pricing::NewVersions`).
  The form carries every value the formula reads, the consultant's internal cost and charge
  rate, VAT by country, validity and the quote's terms text, plus a reason. Saving makes a
  new version in effect from now; other skills' rates are carried over. Both actions are
  audited (`rate_card_version_created`, `margin_floor_changed`).
- **Quotes keep the version they were made with.** A quote still waiting on an older rate
  card or floor says so and offers **Recalculate on the current rates**. That keeps corrected
  inputs but drops a price adjustment, and is refused once the quote is with the client.

## Running it

```sh
# after demo:key_person (company 3, Gulf Trading Co.), or FRESH=1 to start from onboarding
docker compose exec rails bundle exec rails demo:pricing              # scripted P24
docker compose exec rails bundle exec rails demo:pricing REAL=1       # P24 on the configured model

docker compose exec rails bundle exec rails pricing:eval              # calculator + P24 over the scenarios
docker compose exec rails bundle exec rails pricing:eval REAL=1 ONLY=standard
docker compose exec rails bundle exec rails pricing:health            # DAYS=30

# browser test, across all three portals
docker compose exec rails bundle exec rails e2e:seed_pricing
docker run --rm --network req_app_default -v "$PWD/frontend:/src:ro" -e E2E_BASE_URL=http://frontend:5173 \
  mcr.microsoft.com/playwright:v1.56.1-noble bash -c "mkdir -p /work && cp -r /src/e2e /src/playwright.config.ts /work && \
  cd /work && npm init -y >/dev/null && npm i --silent @playwright/test@1.56.1 && npx playwright test e2e/pricing.spec.ts"
```

The benchmark scenarios are in `backend/spec/fixtures/pricing/scenarios/*.yml`. They cover
Doc 17 §19's twelve participants, no comparables, two languages and locations, thin
participation, and below the floor. Each runs in a transaction that is rolled back.

## Decided here, open with the client

The client-facing version of these, in plain English, is in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

Where the documents disagree or are silent, this build chose:

1. **The key user's acceptance starts Stage 1** (Doc 22 E12, Doc 06's `ACCEPTED`).
   Doc 17 §1 shows only approval and issue.
2. **"After Stage 1 approval" for staff invitations** (Doc 14 §4.1) is read as after the
   client accepts.
3. **Rate card v1 holds placeholder values** until K2 is agreed, and the admin screens say
   so.
4. **Approving issues the quote** (Doc 17 §9.2). Doc 06's separate `ADMIN_REVIEW` and
   `APPROVED` states are folded in: `approved_by` and `approved_at` are required to issue.
   `REJECTED` and `SUPERSEDED` are added for versioning.
5. **Doc 17 §9.3's override reasons**, `BUNDLE` included (Doc 06 §10.11 lists fewer).
6. **VAT** at 5% for AE. Another country needs its rate added to the rate card first.
   Margin is measured before tax.
7. **Deep dives default to the participant count, kept within 3–5.** An administrator can
   change it.
8. **Managers add hours and cost but have no fee line.** Managers added once pricing has
   started are flagged but not charged.
9. **Extra staff are counted, not named.** Anyone beyond the accepted number of invited,
   non-declined staff is extra, so a swap is free.
10. **Comparables** are accepted Stage 1 quotes of a similar size, labelled "actual hours
    not recorded yet".
11. **The delivery mix** is consultants only for Stage 1. *Change delivery mix* waits for
    Stage 2.
12. **Payment terms (K1) and the engagement-terms wording (K3)** are placeholder text on
    the quote. Nothing is paid before staff are invited.
13. **English only.** The app has no translation yet (Doc 17 §10.2 asks for Arabic where
    needed).
14. **Mjadi can change the plan until the client accepts.** The consultant or the platform
    can edit it in pricing, and each change makes a fresh quote. The client can't.
15. **Cancellation:** `STAGE_1_PRICING → CLOSED` is a normal move, made only by Mjadi with a
    reason.
16. **Extra deep dives later aren't handled here.** If the consultant later selects more
    deep dives than the quote included, nothing happens yet. `deep_dives_included` is kept
    for task selection to warn on.
17. **Consultants see the client's view only.** Doc 17 §15 leaves internal figures to
    administrator policy; the policy is "no" for now.

## Not built yet

- **Not in this phase:** invoices, deposits and online payment; selection with dependency
  warnings; Stage 2 and 3 pricing; change quotes; actual consultant hours and the learning
  loop; a platform notifications inbox (administrators are emailed).
- **Arabic quotes.**
- **Retiring the old subscription and Stripe billing** (analysis 09 #5); it is untouched.
- **Hand-off to the teammate:** the employee discovery start should rely on
  `STAGE_1_ACTIVE`, not on `ConversationLimitEnforcer`, for engagement companies.
