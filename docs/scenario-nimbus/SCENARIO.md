# Nimbus Trading Co — full-application scenario

A single end-to-end run that touches **every actor and the whole pipeline**, so we
can watch for bugs and judge features on realistic data.

**Runner:** `backend/lib/nimbus_scenario_runner.rb` · **Task:** `rails scenario:nimbus`
(`CLEANUP=1` purges the sim employees afterward). Results JSON →
`backend/tmp/nimbus_scenario_results.json`.

**Slow local model?** The run is strictly serial (one employee interviewed at a
time) and starts with a hard reset (clears all Sidekiq queues + the OpenAI circuit
breaker). Two knobs keep the LLM load small:

| Env | Default | Meaning |
|---|---|---|
| `NIMBUS_MAX_EMPLOYEES` | `2` | employees interviewed (2 = 1 WhatsApp + 1 web) |
| `NIMBUS_QUESTION_TARGET` | `6` | discovery questions per employee before wrap-up |

Raise to `4` / `10` for a full run once the model is fast enough.

## The company
**Nimbus Trading Co LLC** — a Dubai import/distribution SME (electronics & home
appliances). The friction is procurement-to-pay: manual **proforma-invoice (PI)
checking** against LPOs/quotes, and 100% manual **AP three-way-match re-keying**.
Chosen to mirror the real "check the PI automatically" use case.

## Actors
| Actor | Who | Login |
|---|---|---|
| Platform admin | Worktruth operator | `admin@reqapp.local` |
| Company admin | Omar Haddad (CEO) | `omar@nimbus.ae` / `password123` |
| Consultant | Samir Al-Farsi (trade-ops & finance expert) | `samir.ops@consultants.worktruth.local` / `password123` |
| Employees | 4 (below) | invite-first |

## Employees & channels (both exercised)
- **WhatsApp** (Meta webhook path): Fatima Noor (Procurement Officer), Raj Patel (AP Accountant)
- **Web** (`Web::TurnRouter`): Sara Haddad (Sales Coordinator), Ahmed Saleh (Logistics Coordinator)

Each is scripted with realistic, quantified answers (PI mismatch ~1 in 4, AP
first-pass ~72%, invoice-to-pay 9–12 days vs 5, demurrage at 48h, etc.).

## Documents (realistic, quantified — in this folder)
`procurement-sop.txt` · `ap-three-way-match-policy.txt` · `supplier-terms.txt` ·
`proforma-invoice-sample.txt` (a sample PI with a 2.4% price drift vs its LPO).

## The flow the runner drives
1. Provision platform admin, company + admin, consultant; assign consultant.
2. Upload the 4 documents (ingested + chunked, ready).
3. Interview all 4 employees — 2 over WhatsApp, 2 over web — onboarding → profiling → discovery.
4. Aggregate intelligence (signals → patterns → recommendations → agentic ideas → readiness).
5. **Gated** report generation → `internal_only`, `awaiting_consultants`; assert the company **cannot** download it yet.
6. Consultant **contributes**: approve section decisions + a comment; a prose **EDIT that replaces** the AI executive summary; an **added** "Risk register" section; a publishable executive-conclusion finding; an overall note; a company-admin clarification **Q&A**.
7. Assert the **gate**: a `needs_info` review blocks approval (then resolve).
8. Consultant submits → **platform approves** → report `shared_with_company`; assert the company **can now** download; company is notified.
9. Inspect the final deliverable: the consultant's edited exec summary and added section appear; no raw internal scores leak.

## LLM (fully local — Gemma)
All services are pointed at LM Studio via `.env` **Profile B**
(`google/gemma-4-12b-qat` for chat, `text-embedding-embeddinggemma-300m-qat` for
embeddings) — no OpenAI. `LANGGRAPH_READ_TIMEOUT=240` gives local inference headroom
(the 45s default trips the circuit breaker on every turn).

```bash
docker exec req_app-rails-1 bundle exec rails scenario:nimbus
```

## What to watch
Channel parity (WhatsApp vs web), interview quality/repetition, signal/metric
grounding, the enforced review gate, consultant edits reaching the final PDF,
notifications firing at the right time, and any errors along the way.
