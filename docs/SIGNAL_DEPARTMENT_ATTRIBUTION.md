# Signals never carry the department their evidence came from

**Status: FIXED**, 6 September 2026, on `report-redesign`. Kept as the record of
what the bug was and why the fix is shaped the way it is. What actually shipped
is in ["What was done"](#what-was-done) at the end; the analysis above it is the
original write-up and still describes the code as it was.

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


---

## What was done

Two independent causes had to be fixed, because fixing either alone leaves
`Patterns detected (0)` on the screen.

### 1. Departments are derived per signal, from its own evidence

`SignalExtractor` now returns a `departments:` key on every signal, collected
from the evidence that actually produced it:

| Evidence | Department source |
|---|---|
| documents whose text matched the rule | `document.department` |
| interview messages kept as `source_excerpts` | that message's employee's department |
| media exhibits that matched | that attachment's employee's department |
| corroborating derived text (facts, knowledge, insight summaries) | **none, deliberately** — not traceable to one team |
| topic-only inference | **none** — a topic string carries no provenance |

`SignalUpsertService` reads that per-signal set and treats the caller's
`department:` scalar as advisory. `AggregateCompanyIntelligence`'s parameter
stays for the document/media paths that legitimately know one department; the
interview path passing none is now correct rather than a gap.

**Replace vs merge.** A full-company run (`reconcile_stale: true`) has seen all
the evidence, so its derived set replaces what is stored — otherwise a
department whose evidence has since gone sticks to the signal forever. A
department-scoped run sees only a slice and merges.

### 2. The cross-department rule needed its own strength floor

Attribution alone was not enough. Two employees in different departments
describing the same friction produce `evidence_count = 2`, hence
`strength = 1 - exp(-2/6) = 0.28` — below `MIN_STRENGTH` (0.35), so the signal
was filtered out before rule 3 ever saw it.

`PatternDetector::CROSS_DEPARTMENT_MIN_STRENGTH = 0.2` now applies to rule 3
only. The asymmetry is deliberate:

- a **combo** pattern asserts a fixed, high confidence (0.82 / 0.78) that two
  signal *types* reinforce each other; on thin evidence that claim is unearned,
  so `MIN_STRENGTH` guards it;
- a **cross-department** pattern reports its own signal's strength as its
  confidence, so a thinly-evidenced one surfaces as a *low-confidence* pattern
  — the report states the uncertainty instead of hiding it. And the spread is
  itself corroboration: two teams independently describing the same friction is
  the finding, whatever the keyword-hit count.

### 3. Two things that only became visible once it worked

**Pattern spam.** Once departments were attributed properly, *most* signals in
a multi-department company span two teams, so an uncapped rule 3 emitted one
near-identical "<signal> across departments" pattern per signal type — seven on
one company, which says less than the signal list already does.
`MAX_CROSS_DEPARTMENT = 3`, ranked by spread then strength: a friction in three
departments is a bigger finding than a slightly stronger one in two.

**Patterns were never reconciled.** `PatternUpsertService` had no
`reconcile_stale`, so a pattern detected once lived forever, its confidence only
ever increased (`[pattern.confidence, attrs[:confidence]].max`), and its status
was forced to `confirmed` on every pass. That would have quietly defeated the
new cap, and more generally kept reporting a pattern whose evidence had gone. It
now prunes on full runs, takes the fresh confidence, and lets a pattern fall
back to `emerging`. Nothing holds a foreign key to `patterns` —
`recommendations` and `agentic_ideas` reference them by id in jsonb arrays that
are read defensively, and `RecommendationSynthesizer` re-runs immediately after
in the same aggregation pass.

## Measured result

Against the two scenario companies that produced the original write-up:

| | patterns before | patterns after | departments before | departments after |
|---|---|---|---|---|
| Nimbus Trading | **0** | **3** | `[]` on every signal | procurement / finance / sales |
| GulfLink Logistics | 7 | 4 | `["operations"]` on 5 of 6 | finance + operations |

Nimbus is the case the write-up was about. GulfLink's count *fell* because the
stale patterns it had accumulated were pruned and its confidences are now the
current ones rather than historical maxima — `0.74 emerging` where it had
previously been stuck at `confirmed`.

## Tests

`spec/services/intelligence/signal_department_attribution_spec.rb` covers
interview-only, document-only, combined, multi-department, no-department, and
derived-text-only attribution, plus two end-to-end cases through
`AggregateCompanyIntelligence` — including the one that reproduces the original
bug (the interview path passing no department scalar).
`signal_upsert_service_spec.rb` covers replace-vs-merge and the case-insensitive
dedupe.

## Still open

The scenario runners were not given a shared-department fixture. The dedicated
spec above exercises the multi-department path directly, which is a better test
than a scenario assertion, but `rake scenario:nimbus` still checks
`Patterns detected` against whatever its fixture happens to produce.
