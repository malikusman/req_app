# Two consolidation engines, and how they become one

Doc 10 asks for one engine that finds work several people describe, groups it, and counts
its effort once. For the MVP there are two: synthesis (`app/services/synthesis/`, see
[SYNTHESIS.md](SYNTHESIS.md)) and the deep-dive engine (`app/services/process_clusters/`,
`app/services/task_intelligence/`, `app/services/task_selection/`,
`app/services/deep_dive_plans/`). They were built at the same time on separate branches and
merged in `mvp-stage1`.

Each does a job the other doesn't, so both stay until they are joined. This page says how.
Code on both sides points here with "(docs/CONSOLIDATION_ENGINES.md §n)".

- [1. Why there are two](#1-why-there-are-two)
- [2. Side by side](#2-side-by-side)
- [3. The goal: one set of clusters](#3-the-goal-one-set-of-clusters)
- [4. What task intelligence should read](#4-what-task-intelligence-should-read)
- [5. One way to ask for clarification](#5-one-way-to-ask-for-clarification)
- [6. Company or engagement](#6-company-or-engagement)
- [7. One refresh path](#7-one-refresh-path)
- [8. Model calls](#8-model-calls)
- [9. Order of the work](#9-order-of-the-work)
- [10. Questions for both of us](#10-questions-for-both-of-us)

---

## 1. Why there are two

- **Synthesis** answers "what goes in the report". It groups findings, counts shared
  work once, and sets leadership's view against what staff describe (P10, P11). The
  report reads only what a consultant approved there.
- **The deep-dive engine** answers "what should we investigate". It groups the tasks the
  interview recorded, scores them, and takes the consultant through choosing tasks and
  approving interview plans (Doc 11).

Until they are joined, the consultant sees shared work on two pages (Synthesis, and Task
selection), and the hours on each can differ.

## 2. Side by side

| | Synthesis | Deep-dive engine |
|---|---|---|
| Groups | `Finding` rows: role areas where someone described a problem (`Synthesis::WorkItems`) | `TaskSource` rows: each task the interview recorded, with trigger, steps, output, tools (`TaskSources::SyncFromConversation`) |
| Finds pairs | Shortlist in code (`Synthesis::Candidates`) | Every pair across conversations (`ProcessClusters::Rebuild`) |
| Decides how two relate | P10, checked by `Synthesis::RelationshipValidator`; stored in `ProcessRelationship` | Rules on trigger, output and step words (`ProcessClusters::Relationship`); stored on the cluster revision |
| Groups into | `SynthesisCluster` + `SynthesisClusterMember`, versioned (`SynthesisVersioned`) | `ProcessCluster` + `ProcessClusterRevision` + `ProcessClusterMembership` |
| Shared hours | `Synthesis::EffortNormalizer`: counted once when unsure, lower figure, warning | `ProcessClusters::EffortReconciliation`: no figure when work may overlap |
| Unclear pairs | P10 `CLARIFY` or `CONSULTANT_REVIEW`, shown to the consultant | `ClarificationRequest` (`ProcessClusters::ReconcileClarifications`) |
| Consultant | Synthesis page: confirm, split, merge, correct hours, with a reason (`Synthesis::Decide`) | Task selection page: merge, split, participants, hours, finalise (`TaskSelection::Review`) |
| Scope | Engagement (reads the company's live findings) | Company |
| Runs on | `SynthesisRunJob`, debounced | `RefreshTaskEvidenceJob`, every minute |
| Feeds | The report (`Synthesis::ForReport`), and `Synthesis::ForTaskIntelligence` (not read yet) | `TaskIntelligence::Generate` → task selection → deep-dive plans |

## 3. The goal: one set of clusters

- **One table, named `ProcessCluster`** as in Doc 06. It keeps her revisions and
  memberships. Members are `TaskSource` rows, the work item Doc 06 §5.7 asks for. Each
  `TaskSource` already links to its `Finding` (`task_sources.finding_id`), which is how the
  report keeps its per-finding figures.
- **Her rules come first, the model second.** `ProcessClusters::Relationship` becomes the
  shortlist and a first judgement. `same_work`, `different_stages` and `related_distinct`
  are settled in code. `uncertain` and `shared_variant` go to P10. A pair the rules don't
  connect is never sent to the model (P10 §2).
- **Consultant decisions carry over.** Synthesis never redraws a cluster a consultant
  approved, split, merged or made (Doc 10 §21). Task selection's merges and splits should
  be stored the same way, so a rebuild can't undo them.
- **One effort rule** (needs agreeing). Today synthesis counts work that may be the same
  execution once, using the lower figure, with a warning. The deep-dive engine gives no
  figure at all. Proposed: keep the de-duplicated figure with its warning for the report,
  and have task intelligence score on its lower bound. Both engines already agree that
  waiting time never counts and that hours are worked out in code, never by the model.
- `ProcessRelationship` (synthesis) and the relationships on a cluster revision (deep dive)
  hold the same thing. One of them goes.

## 4. What task intelligence should read

`TaskIntelligence::Generate` should read `Synthesis::ForTaskIntelligence` (contract
SYN-TI.v1) as well as clusters. That brings:

- opportunities above task level, with their next step (`DEEP_DIVE`, `DIRECT_FINDING`,
  `CLARIFY`, `TECHNOLOGY_REVIEW`, `DEFER`, `NOT_RECOMMENDED`);
- **management importance** beside **platform priority**, kept apart (Doc 08 §17). These
  replace `business_goal_keyword_alignment` in `TaskIntelligence::EvaluateCluster`;
- leadership's verdicts (supported, partly, not yet observed, points elsewhere), so a
  concern staff bear out ranks higher and one they don't is flagged;
- initiative conflicts, so work a planned change will replace is deferred, not dropped.

Re-rank on the `synthesis.changed` notification.

## 5. One way to ask for clarification

Synthesis has `CLARIFY` on a pair (from P10) and on a leadership verdict (from the
consultant, `Synthesis::Decide#request_clarification`). The deep-dive engine has
`ClarificationRequest`. They should be one record, and that record is the one the
follow-up route will send to employees when it exists.

## 6. Company or engagement

Synthesis is per engagement; the deep-dive engine is per company. Neither interviews nor
findings record their engagement yet. Once conversations carry `engagement_id`, both should
work per engagement, so a company's second engagement starts clean.

## 7. One refresh path

`RefreshTaskEvidenceJob` (every minute) and `SynthesisRunJob` (debounced, ten minutes after
new evidence) both react to the same interviews. One chain is wanted: task sources →
clusters → synthesis → task intelligence, each step started by the one before.

## 8. Model calls

- **Logging.** Deep-dive plan generation (`agent/app/deep_dive_plan.py`) has no prompt
  version and writes no `AiRun`. Every other prompt does (P02–P04, P10, P11, P24). It should
  get a prompt file and a version, and a record per call.
- **Names.** `DeepDivePlans::Context` sends each participant's name, role and department to
  the model. Synthesis sends no names (`Synthesis::ContextPack`). Plans are for consultants
  only, so names may be acceptable; agree one rule and add it to the firewall specs.

## 9. Order of the work

Each step is checked with both spec suites, `rake synthesis:eval`, and the Playwright files
for synthesis, task selection and deep-dive plans.

1. **`Synthesis::WorkItems` reads `TaskSource`** instead of `Finding`, keeping the
   `Finding` link for the report. Synthesis then compares tasks, not only problem areas.
2. **`Synthesis::Candidates` uses her rules** for the shortlist and first judgement (§3).
3. **One table.** A data migration moves synthesis clusters onto `ProcessCluster` revisions;
   `SynthesisCluster` and `ProcessRelationship` go.
4. **Task intelligence reads `ForTaskIntelligence`** (§4); the two clarification records
   become one (§5).
5. **One job chain** (§7), then engagement scope (§6) once conversations carry it.

## 10. Questions for both of us

1. The effort rule for possible overlap (§3).
2. Whether task intelligence should also see clusters a consultant hasn't confirmed yet.
3. Who owns the joined clarification record, and the route to employees (§5).
4. Whether employee names may go to the model in deep-dive plans (§8).
5. When conversations get `engagement_id` (§6).
