# Signals never carry the department their evidence came from

**Status:** open, not yet fixed. Deliberately left out of the
`discovery-consultant-rebuild` branch — this is intelligence aggregation, not
Discovery/Consultant, and wants its own PR with a multi-department scenario to
test against.

**Found:** 2026-09-04, investigating the single failing check (`Patterns
detected (0)`) in an otherwise 59/60 `scenario:nimbus` run against
`gpt-4.1-mini`.

## Symptom

`Patterns detected (0)` with six healthy signals extracted. Reproduces on every
nimbus run, on both local Gemma and gpt-4.1-mini, so it is not model-related.

## Why no pattern forms

`Intelligence::PatternDetector` can form a pattern three ways. None can fire
with this data:

1. Combo `approval_bottleneck + manual_process`
2. Combo `data_silo + time_sink`
3. Any single signal whose `departments` spans 2 or more

Observed signals:

| signal_type | strength | departments |
|---|---|---|
| manual_process | 0.89 | `[]` |
| tool_dependency | 0.56 | `[]` |
| communication | 0.45 | `[]` |
| time_sink | 0.32 | `[]` |
| approval_bottleneck | 0.28 | `[]` |
| data_silo | 0.28 | `[]` |

**Rules 1 and 2 fail legitimately.** `PatternDetector::MIN_STRENGTH` is 0.35 and
signals below it are filtered out before combo matching, so
`approval_bottleneck` (0.28) and `data_silo` (0.28) never participate.
`SignalExtractor` computes `strength = 1 - exp(-weighted / 6)`, so 0.28 means
roughly 2 units of evidence against manual_process's ~13. Two employees working
on unrelated problems (invoice matching vs order handoff) genuinely produce thin
evidence for approvals — this is the floor doing its job, and more interviewed
employees lifts it without any code change. **Not a bug.**

**Rule 3 is the real problem:** `departments` is empty on every signal.

## Root cause

`SignalExtractor.call(company:)` extracts signals across the WHOLE company. The
department is not derived from each signal's evidence; it arrives as a single
scalar that `AggregateCompanyIntelligence` forwards to
`SignalUpsertService(department:)`, which applies it to every signal in the
batch. Three consequences:

1. **`Discovery::FinalizeConversationService`** (the post-interview path) calls
   `AggregateIntelligenceJob.perform_later(@company.id)` with no department at
   all, so interview-derived signals are never tagged — in production, not just
   in scenarios.

2. **Only the document/media paths tag anything:**
   `Multimodal::ParseDocumentService` and `Multimodal::IndexMediaService` pass
   `document.department` / `employee.department`. So rule 3 is reachable in
   production, but only by two *documents* from different departments happening
   to accumulate on the same signal type — never from interviews.

3. **When it does tag, the attribution is coarse and can be wrong:** the scalar
   is applied to every company-wide signal in the batch, so a signal derived
   entirely from Fatima's procurement interview gets tagged with whatever
   department the triggering document belonged to.

Additionally, `nimbus_scenario_runner.rb#ingest_document!` creates documents
directly (upload, chunk, `status: "ready"`) and never calls
`ParseDocumentService`, so even the document tagging path does not run in that
scenario. That part is a scenario artifact rather than a product bug, but it is
why the check fails there specifically.

## Proposed fix

The data needed is already present: each signal's `source_excerpts` carry
`employee_id` (`SignalExtractor#message_evidence_for`), and document sources
carry their department. So departments can be derived **per signal, from the
evidence that actually produced it**:

- In `SignalExtractor`, collect the departments of the employees behind each
  signal's `source_excerpts` plus the departments of its matched documents, and
  return them on the signal hash.
- In `SignalUpsertService`, merge those per-signal departments instead of (or in
  addition to) the caller's scalar. Keep `canonical_departments` for the
  case-insensitive dedupe.
- Then `AggregateCompanyIntelligence`'s `department:` parameter becomes
  advisory-only, and `FinalizeConversationService` no longer needs to pass one.

Worth doing alongside it:

- Give `nimbus_scenario_runner` a second employee in a **shared** department, or
  documents whose signals overlap, so rule 3 is actually exercised by a test
  rather than only reasoned about.
- Consider whether `MIN_STRENGTH` (0.35) should apply to combo *participation*
  at all, or only to the anchor. Right now a genuine-but-thinly-evidenced
  `approval_bottleneck` cannot combine with a very strong `manual_process`,
  which is arguably the pattern most worth surfacing early. That is a
  product-judgement call about false positives on small samples, not a bug.

## Reproducing

```
docker compose exec rails bash -lc "cd /app && bundle exec rake scenario:nimbus"
# then:
Company.find_by(slug: "nimbus-trading").company_signals
       .order(strength: :desc)
       .pluck(:signal_type, :strength, :departments)
```
