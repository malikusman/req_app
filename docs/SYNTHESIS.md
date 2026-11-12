# Consolidation and synthesis

How the platform brings what employees described and what leadership said together (Doc 10,
prompts P10 and P11), what it stores, what the consultant does with it, what reaches the
report and task intelligence, and what is still open. For where P10 and P11 sit among the
other model steps, see [AGENTS.md](AGENTS.md) §4 rows 22–23 and Flow 11. For the consultant's
page, see [APPLICATION_GUIDE.md](APPLICATION_GUIDE.md) §5.7a.

## Two capabilities, one engine

| | Consolidation (Doc 10 stages A–F, P10) | Synthesis (stages G–H, P11) |
|---|---|---|
| Question | Are two pieces of work the same, duplicated, stages of one process, variants, or unrelated? | Across the engagement: what are the root causes, which opportunities sit above any one task, and does staff evidence bear out leadership's concerns? |
| Reads | Employees' work items (today: findings) | Clusters and their de-duplicated hours, unclustered work, each leader's context and strategic findings, planned initiatives, coverage |
| Model does | Judges one shortlisted pair at a time; no numbers | Reasons once over the whole engagement; directions, never designs; quotes figures, never computes them |
| Code does | Shortlists pairs, assembles clusters, **does all effort arithmetic** | Validates every reference and figure, sets platform priority, versions everything |
| Produces | `SynthesisCluster` (Doc 06's ProcessCluster), `ProcessRelationship`, `EffortNormalization`, sampling recommendation | `ConsultancyOpportunity`, `RootCause`, `ManagementValidation`, operating picture, initiative conflicts, role potential, coverage notes |

**Where it ends:** at approved, versioned clusters, de-duplicated effort, opportunities and
root causes each with a next step, and leadership verdicts. **Task intelligence (P12, the
teammate's) starts** at `TaskCandidate`: it turns these into candidates, scores and ranks
them, proposes the deep-dive portfolio and runs the consultant's selection. Synthesis never
ranks tasks or chooses deep dives.

## The path

```
interview findings drafted ─┐
leadership context built ───┼─▶ SynthesisRunJob.request ─(10 min quiet)─▶ Synthesis::Run
consultant "Run again" ─────┘                                              │
                                                                          ▼
 A WorkItems ─▶ B Candidates ─▶ C P10 per new pair ─▶ D clusters ─▶ E effort ─▶ G/H P11
                                                                          │
                                       consultant reviews on the Synthesis page (Doc 10 §17)
                                                                          │
                       approved only ─▶ report snapshot · ForTaskIntelligence (P12)
```

1. **Work items.** `Synthesis::WorkItems` reads the company's live findings in the
   work-item shape, keeping the employee's wording. It is the one place that changes when
   employee discovery keeps its own `WorkItem` records.
2. **Shortlist.** `Synthesis::Candidates` scores every pair on what the work is: the
   words of how it happens and what snags, shared systems, identical figures from one
   person, and the same role in the same department. A similar name alone never
   qualifies. A pair already judged is skipped until either side changes, and a pair the
   consultant settled is never asked again.
3. **P10** (`Synthesis::RelationshipClassifier`) judges each new pair. It sees the two
   items, the employees' own words, the shortlisting signals (including whether one person
   or two described them, never who), and the company's departments and systems.
   `RelationshipValidator` leans every correction towards keeping things apart:
   - auto-cluster is allowed only at HIGH for the same process or a shared sub-step;
   - nothing clusters at LOW;
   - any text with a figure is dropped.
   If the model is unavailable, the pair is kept separate and queued for the consultant.
4. **Clusters.** `Synthesis::ClusterAssembler` groups items only on verdicts recommending
   it at MEDIUM or HIGH. Variants stay inside a cluster, and end-to-end processes keep
   their stages. A cluster keeps its key when a later interview extends it. A consultant's
   cluster is never reshaped; a newcomer that belongs in it is offered as a suggestion.
5. **Effort** (`Synthesis::EffortNormalizer`, EN.v1). This is the arithmetic, in code.
   Raw hours are always kept beside de-duplicated hours.
   - The same execution is counted once (the fuller account stands).
   - Genuine duplication counts for each person, and is flagged.
   - A handoff counts each side's own part.
   - Waiting time never counts.
   - An unclear overlap is counted once, marked conservative, with a double-count warning.
   - Two platform rules apply whatever P10 said:
     - one person's work described twice is counted once;
     - two people's accounts are the same execution only on a consultant's word.
6. **P11** (`Synthesis::Synthesizer`) reads the engagement through
   `Synthesis::ContextPack`. The pack never includes consultant-private content,
   transcripts, commercial data or names (known names are replaced before the text is
   assembled). Every object the model may cite gets a reference (`cl-12`, `wi_40`,
   `sf_7`, `mc_2`, `pi_1`). `SynthesisValidator` drops:
   - items citing nothing real, and root causes explaining fewer than two things;
   - capacity figures that aren't the platform's, quoted exactly;
   - directions that read as designs;
   - text that names or describes a person, or carries an ungrounded figure.
   Every drop is recorded on the run.
7. **Priority.** Management importance comes from leadership's findings: those P11 cites,
   and those whose verdict rests on the same work. Platform priority comes from
   `Synthesis::Priority` (PRI.v1: de-duplicated hours, breadth, confidence, and +1 when
   staff evidence supports a leadership concern). The two are stored and shown apart.
8. **Re-runs** never undo a consultant's decision. A proposal the model still makes gets
   a new version only if it changed; one it no longer makes is superseded, and kept.

## What it stores (Doc 06 §6)

`synthesis_runs` · `process_relationships` · `synthesis_clusters` + `synthesis_cluster_members`
· `effort_normalizations` · `consultancy_opportunities` · `root_causes` ·
`management_validations` · `synthesis_decisions`.

Doc 06 calls the cluster `ProcessCluster`. That name belongs to the deep-dive engine's
clusters for now; see [CONSOLIDATION_ENGINES.md](CONSOLIDATION_ENGINES.md).

- Every object is versioned (`version`, `parent_version_id`, `SUPERSEDED`) through
  `SynthesisVersioned`. Nothing is edited in place, and rejected output is kept.
- Cluster members carry a digest of the finding as it stood, because findings are
  rebuilt in place; a later change shows as stale.
- Evidence references have one shape: `finding`, `employee_turn`, `strategic_finding`,
  `management_context`, `planned_initiative`, `cluster`.
- An engagement's state (`not_started`, `queued`, `running`, `failed`, `stale`,
  `needs_review`, `approved`) is worked out by `Synthesis::Status`, not stored.

## The consultant (Doc 10 §17)

The **Synthesis** page for each company (`/consultant/companies/:id/synthesis`) has four
tabs:
- **Shared work:** clusters by role and department, never by name, with raw against
  de-duplicated hours, warnings, variants and who a deep dive would need. Pairs to settle
  and suggested newcomers sit above.
- **Leadership vs evidence:** each strategic finding with leadership's importance beside
  the verdict and what staff describe.
- **Opportunities:** management importance beside platform priority, with the next step.
- **How the business runs:** the operating picture.

Every action goes through `Synthesis::Decide`:
- **Clusters:** approve, split, merge (including a suggested newcomer), change variants,
  override effort, reject.
- **Opportunities:** approve, reclassify, add, defer, reject.
- **Root causes:** approve, reject.
- **Leadership verdicts:** approve, resolve, ask about.
- **Operating picture:** edit, approve.
- **Pairs the model couldn't settle:** classify.

Each action needs a reason, acts only on the current version, makes a new version and is
logged. Splitting or rejecting a cluster records that its items are separate, and merging
records that they belong together, so later runs respect it. A change to a cluster or its
effort re-normalises it, publishes `synthesis.changed`, and queues a run two minutes later.

## The report (Doc 15)

`Synthesis::ForReport` passes only what a consultant approved (C11), because the snapshot
is served to the company:
- the operating picture, as **How the business runs today** (§4.4);
- opportunities above any one task, as **What connects the findings**, a subsection
  inside the findings, never a section of its own (C7);
- root causes, worded as analysis;
- material leadership-versus-staff differences, worded "Management reports … Staff
  describe … this should be validated", or with the consultant's conclusion (§8.4);
- opportunities marked not recommended, in **What we are not recommending**.

`Findings::ForReport` counts confirmed shared work once. A finding set aside as the same
execution keeps its own row and figures, marked "Counted once, with …", and no total adds
it again; the critic's reconciliation check follows the same rule. Findings in shared work
across departments say where else it appears. With nothing approved, the report is
unchanged.

## Hand-off to task intelligence (proposed contract SYN-TI.v1 — to be agreed)

The deep-dive engine (task intelligence, task selection, plans) doesn't read this yet; it
keeps its own clusters. How the two join is in
[CONSOLIDATION_ENGINES.md](CONSOLIDATION_ENGINES.md).

`Synthesis::ForTaskIntelligence.call(engagement)` is the one read P12 needs, as
`Companies::AgentContext.neutral_management_context` is for leadership. Its shape is pinned
by `spec/services/synthesis/for_task_intelligence_spec.rb`:

```ruby
{ "contract_version" => "SYN-TI.v1", "synthesis_version" => 7, "generated_at" => ..., "stale" => false,
  "clusters" => [{ "key", "version", "status" /* APPROVED | PROVISIONAL */, "name", "cluster_type", "departments",
                   "roles", "member_work_item_ids" /* Finding ids until WorkItem exists */, "participant_ids",
                   "variants", "stages", "single_member",
                   "effort" => { "raw_min", "raw_max", "dedup_min", "dedup_max", "conservative",
                                 "double_count_warning", "consultant_override" },
                   "sampling" => { "recommended_participant_ids", "coverage_reason", "variants_covered",
                                   "not_needed", "confidence" },
                   "confidence", "evidence" }],
  "unclustered_work_item_ids" => [...],
  "opportunities" => [{ "key", "version", "status", "level", "category", "title", "problem_statement",
                        "affected_cluster_keys", "affected_work_item_ids", "root_cause_key",
                        "recommended_next_action", "management_importance", "platform_priority",
                        "planned_initiative_conflict", "dependencies", "confidence" }],
  "root_causes" => [{ "key", "version", "status", "statement", "explains", "confidence", "fact_status" }],
  "management_validations" => [{ "strategic_finding_id", "status", "relationship", "material", "what_evidence_shows" }],
  "initiative_conflicts" => [...] }
```

- Rejected and superseded objects are left out. Participants appear by id only.
- It carries nothing consultant-private, no transcripts and no operating-picture prose.
- Subscribe to `ActiveSupport::Notifications` `"synthesis.changed"` (`engagement_id`,
  `synthesis_version`, `effort_changed`, `reason`) to re-rank.

**Ownership:**
- **Employee discovery (teammate):** `WorkItem`, `EffortEstimate`, cross-employee signals
  and posture signals.
- **Synthesis:** clusters, relationships, effort normalisation, opportunities, root causes,
  sampling and leadership verdicts.
- **Task intelligence (teammate):** `TaskCandidate`, `CandidateAssessment`,
  `DeepDiveRecommendation`, `PortfolioProposal` and `ConsultantDeepDiveDecision`.

## The firewall

`spec/firewall/synthesis_context_spec.rb` plants sentinels wherever synthesis keeps
something, and in the consultant-private notes it must never read. It checks that:
- nothing consultant-private, and no name, reaches P10 or P11;
- a reply naming someone is stripped before it is stored;
- nothing synthesis produced reaches an employee's interview, the agent pack, the
  document-analysis snapshot, the neutral line to staff, the key user's portal (even once
  approved), the platform view or a manager's link.

`Companies::AgentContext` has no synthesis reader for employees.

## Switches and models

- `AI_SYNTHESIS=false`, or no model: every pair is kept separate and queued for the
  consultant, and runs finish `PARTIAL`, carrying the last synthesis forward. Effort
  arithmetic and the report don't depend on the model.
- `SYNTHESIS_CLASSIFIER_MODEL` (P10) and `SYNTHESIS_MODEL` (P11) fall back to
  `OPENAI_MODEL`. Doc 05 asks for a strong reasoning model; see the benchmark below.
- Outside production, a company's `synthesis_scripted_replies` setting (or
  `SYNTHESIS_SCRIPTED_REPLIES=1`) runs on `Synthesis::ScriptedClient`, for the demo, the
  browser test and the benchmark's plumbing only.
- Every model call is an `AiRun` (stage `P10` or `P11`) tied to its run.

## Running it

```sh
docker compose exec rails bundle exec rails synthesis:run COMPANY=3           # now, on the configured model
docker compose exec rails bundle exec rails synthesis:run COMPANY=3 SCRIPTED=1
docker compose exec rails bundle exec rails synthesis:eval                    # scripted plumbing
docker compose exec -e REAL=1 rails bundle exec rails synthesis:eval          # the real model
docker compose exec rails bundle exec rails synthesis:health                  # DAYS=30

# browser test
docker compose exec rails bundle exec rails e2e:seed_synthesis
docker run --rm --network req_app_default -v "$PWD/frontend:/src:ro" -e E2E_BASE_URL=http://frontend:5173 \
  mcr.microsoft.com/playwright:v1.56.1-noble bash -c "mkdir -p /work && cp -r /src/e2e /src/playwright.config.ts /work && \
  cd /work && npm init -y >/dev/null && npm i --silent @playwright/test@1.56.1 && npx playwright test e2e/synthesis.spec.ts"
```

The benchmark lives in `backend/spec/fixtures/synthesis/`: 8 pairs (P10 §10) in
`pairs.yml` and 8 small engagements (P11 §11) in `syntheses.yml`. Each runs in a
transaction that is rolled back.

On gpt-4.1-mini (11 November 2026), **10–11 of 16 pass**. The misses:
- **Two coordinators' quotes.** P10 calls this "the same execution". The platform now
  counts it once, conservatively, with a warning for the consultant.
- **One buyer's work named twice.** P10 calls it two stages. It is counted twice, with a
  warning.
- **Leadership blames finance.** P11 says SUPPORTED where the evidence points to
  approvals.
- **Model variance.** A stock lookup is called a VARIANT, and a handoff is sometimes kept
  apart.

gpt-4.1 passes the buyer, handoff and stock cases, and still misses the coordinators'
quotes and the finance case. Use a stronger model for P10 and P11 before release.

## Decided here, open with the client

The client-facing version of these, in plain English, is in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

1. **Work items are findings** until employee discovery keeps `WorkItem` records, so only
   areas where someone described a problem are compared.
2. **Enums follow Doc 10 / P10 / P11**, which are newer and richer than Doc 06 §6.3/§6.5.
   The models carry mapping constants to Doc 06's names.
3. **No minimum coverage** (C12). Consolidation needs two work items; P11 runs on
   whatever there is, and says what is thin in coverage notes.
4. **Platform priority is PRI.v1** (above), pending the client's rule.
5. **Leadership is attributed as "management"**, never by role or name, in the report.
6. **A consultant's effort override on a cluster informs task intelligence but does not
   change report totals.** Changing totals would mean rewriting an employee's own figures
   on their row. Report figures are corrected per finding, as before.
7. **Synthesis runs per engagement over the company's live findings**, because findings
   and conversations carry no engagement yet.
8. **Debounce:** ten minutes after new evidence, two minutes after a consultant's change,
   and immediately on "Run again".

## Not built yet

- **Posture** (Doc 10 §16.2): no posture signals are captured.
- **Clarification requests to employees:** "ask about it" is recorded, not sent; it needs
  the teammate's follow-up loop.
- **Report placement where the cause sits.** Shared work is cross-referenced from each
  department, and its hours count in the department of the account that stands.
- **The brief report variant** doesn't show the synthesis pages yet.
- **Change-impact alerts on approved implementation work.** There is no Stage 2 or 3 yet.
- **Hand-offs to the teammate:**
  - structured cross-employee signals (Doc 09 §20: same-activity claims, upstream and
    downstream roles, business object, variant signals) and posture signals in the
    dossier;
  - `engagement_id` on conversations and findings;
  - agreeing SYN-TI.v1 and re-ranking on `synthesis.changed`.
