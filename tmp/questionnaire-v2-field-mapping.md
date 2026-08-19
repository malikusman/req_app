# Onboarding Questionnaire v2 — Field Mapping & Build Reference

**Purpose.** This is the authoritative input for rebuilding the company onboarding questionnaire. It maps every field in the current (v1) questionnaire to its destination in the new (v2) spec, and defines every v2 field with its storage key, type, tier, step and options.

**How to use it.** Section 6 is the build target — the new config should be written from that table. Section 5 exists to answer "what happened to the old field X?" during review. Section 7 lists the fields that ship with placeholder components first.

**Scope.** Questionnaire wording, structure and UX mechanics only. Document upload/analysis, AI opportunity signals, data-provenance tagging, and the completion/dashboard screens are explicitly out of scope for this rebuild.

---

## 1. Change summary

| | Count |
|---|---|
| v1 fields total | 41 |
| — carried over (same meaning, reworded/regrouped) | 20 |
| — merged into a combined v2 field | 8 → 3 |
| — dropped (no v2 equivalent) | 13 |
| v2 fields total (stored) | 45 |
| — of which entirely new | 22 |
| v2 profile fields (outside the questionnaire) | 3 |

**Note on "41 questions".** The spec numbers questions Q01–Q41, but four are lettered sub-questions with their own storage (Q10A, Q10B, Q25A, Q37A). The user-facing count is 41; the stored field count is 45.

**Note on earlier estimates.** An earlier summary quoted roughly 10 dropped and 20 new. The exact figures after full mapping are 13 dropped and 22 new. This does not change any of the approved decisions — recording it for accuracy.

---

## 2. Storage key convention

v2 keys use the spec question ID plus a short descriptive name, lowercase snake_case:

```
q01_primary_industry
q10a_documentation_types
q37a_ai_training
```

Rationale: the ID prefix makes the mapping between spec document, config file and stored data unambiguous, and keeps keys sorted in the order the user encounters them. Sub-question letters are lowercased in the key.

Per the approved plan, v2 keys are **new keys, not renames of v1 keys.** No v1 key is reused. Old answers remain in the `questionnaire_answers` blob under their v1 keys, untouched and unread.

---

## 3. Version handling

- Add a `questionnaire_version` integer column on `companies`, defaulting to `1`.
- Existing rows stay at `1`. Their v1 answers stay in the blob and continue to be read by anything that reads v1 keys.
- New onboarding sessions are stamped `2` and write only v2 keys.
- Companies mid-way through v1 at cutover start v2 from Step 1. Their partial v1 answers remain saved but unused.
- The backend whitelist, section map and progress calculation branch on the version.

---

## 4. Answer tiers

| Tier | Meaning | Effect on completion |
|---|---|---|
| **Essential** | Must be answered before onboarding can be marked complete | Counts toward completion % |
| **Recommended** | Encouraged; user may skip or answer "Not sure" | Does not count |
| **Optional** | Narrative or detail fields | Does not count |
| **Conditional** | Only shown when a prior answer applies; tier of its parent when visible | Counts only when visible and its parent tier is Essential |

No red asterisks anywhere. Optional fields are labelled "Optional" in the UI.

---

## 5. v1 → v2 disposition (all 41 old fields)

### Carried over — 20 fields

| v1 key | v1 question (abbrev.) | → v2 key | Change |
|---|---|---|---|
| `company_industry` | What industry is your company in? | `q01_primary_industry` | Reworded; same option list |
| `company_size` | How many employees? | `q03_employee_count` | Option bands changed from 5 to 8 |
| `company_location` | Where headquartered? | `q04_headquarters_country` | Now a full country list, not a preset 20 |
| `business_model` | Business model (B2B/B2C/…) | `q05_customer_types` | Reframed: who you sell to, not the model label |
| `num_locations` | Physical locations/branches | `q06_operating_sites` | Reworded; option bands changed |
| `departments_present` | Which departments exist? | `q07_departments` | Options expanded (adds Production, Project Mgmt, QC) |
| `manual_processes` | Done manually or on spreadsheets? | `q11_manual_process_areas` | Now reuses the Q09 process taxonomy |
| `approval_workflow` | How are approvals handled? | `q14_approval_methods` | Single-select → multi-select; options expanded |
| `document_types` | Document types managed | `q16_information_types` | Rescoped to what employees work with |
| `communication_tools` | Communication/collaboration tools | `q23_productivity_tools` | Options expanded to productivity suites |
| `tech_stack_maturity` | Overall tech maturity | `q24_system_connection` | Reframed from maturity to integration level |
| `data_storage_location` | Where is data stored? | `q26_information_storage` | Options expanded |
| `search_difficulty` | Ease of finding information | `q27_information_findability` | Reworded; 4 options → 6 |
| `reporting_frequency` | How often are reports generated? | `q28_reporting_method` | Reframed from frequency to method |
| `customer_channels` | How customers reach you | `q29_external_parties_channels` | Expanded to all external parties, two-stage |
| `top_bottlenecks` | Biggest operational bottlenecks | `q31_operational_challenges` | Options expanded; **max-3 cap removed** |
| `error_prone_areas` | Where errors happen most | `q32_error_delay_areas` | Options expanded to departments |
| `ai_openness` | Readiness to adopt AI | `q36_adoption_readiness` | Reworded; 4 options → 6 |
| `compliance_requirements` | Compliance requirements | `q39_restrictions` | Broadened to all restrictions |
| `additional_context` | Anything else? | `q41_specific_investigation` | Reframed as a direct ask |

### Merged — 8 fields into 3

| v1 keys | → v2 key | Note |
|---|---|---|
| `erp_system`, `crm_system`, `accounting_software`, `hr_software` | `q22_business_systems` | Four dropdowns become one category→system matrix covering 12 categories |
| `current_ai_usage`, `ai_tools_used` | `q35_current_ai_automation` | Usage level and tool list become one grouped multi-select |
| `desired_ai_functions`, `primary_goals` | `q40_desired_outcomes` | Two goal questions become one grouped multi-select; **max-3 cap removed** |

No backfill for merged fields. The v2 shapes carry information the v1 values don't, so old values can't be collapsed losslessly. Start fresh.

### Dropped — 13 fields

| v1 key | Why |
|---|---|
| `annual_revenue` | Not in v2 |
| `operational_structure` | Centralisation question not in v2 |
| `department_pain_point` | Superseded by Q11/Q12, which ask it more precisely |
| `repetitive_task_frequency` | Superseded by Q21 (high-volume activity) |
| `document_volume` | Estimate management may not know |
| `monthly_inquiry_volume` | Superseded by Q21 |
| `response_time_current` | Not in v2 |
| `support_team_size` | Not in v2 |
| `time_lost_estimate` | Estimate management may not know |
| `data_hosting` | Security section reduced to Q39 |
| `security_posture` | Security section reduced to Q39 |
| `timeline` | AI adoption timeline not in v2 |
| `budget_range` | AI adoption budget not in v2 |

**Side effect to check:** `annual_revenue` currently feeds `company_profile.annual_revenue_band` via `QuestionnaireSync`. Once dropped, that band no longer refreshes from onboarding. It remains editable from the settings page, so reports keep working — but confirm this is acceptable rather than assuming.

---

## 6. v2 field specification (build target)

Types: `single_select` · `multi_select` · `searchable_select` · `text` · `textarea` · plus new types marked ⚠ (see Section 7).

### Profile fields (outside the 8 steps)

| Key | Label | Type | Tier | Notes |
|---|---|---|---|---|
| `profile_name` | Your name | text | Essential | Non-empty |
| `profile_phone` | Your phone number | text (intl) | Recommended | Country-code selector; accept pasted international formats |
| `profile_website` | Company website | text (url) | Recommended | Must accept `company.com` without scheme; normalise to HTTPS. **Already implemented** — verify only |

---

### Step 1 of 8 — About Your Business

One scrollable screen.

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q01_primary_industry` | What is your company's primary industry? | searchable_select | Essential | Retail & E-commerce · Manufacturing · Construction & Engineering · Healthcare & Medical · Real Estate · Logistics & Transportation · Hospitality & Food Service · Professional Services · Financial Services & Insurance · Education · IT & Software · Energy & Utilities · Automotive · Agriculture · Media & Entertainment · Government & Public Sector · Other → `q01_primary_industry_other` |
| `q02_business_description` | Briefly describe your business. What are your main products or services, and who are your main customers? | textarea | Essential | Helper: "A few sentences are enough." 100–1,500 chars. **NEW** |
| `q03_employee_count` | How many employees does your company have? | single_select | Essential | 1–10 · 11–25 · 26–50 · 51–100 · 101–250 · 251–500 · 501–1,000 · 1,000+ |
| `q04_headquarters_country` | Where is your company headquartered? | searchable_select | Essential | Full country list |
| `q05_customer_types` | Who does your company primarily sell to or serve? | multi_select | Essential | Businesses · Consumers · Government / public sector · Other → `q05_customer_types_other` |
| `q06_operating_sites` | How many physical offices, branches, stores, warehouses, factories or other operating sites does your company have? | single_select | Essential | 1 · 2–5 · 6–20 · 21–50 · 51+ · Fully remote / no permanent operating site |

---

### Step 2 of 8 — Organisation & Business Processes

Two screens.

**Screen 2A — Your Organisation**

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q07_departments` | Which departments or functions exist in your organisation? | multi_select ⚠chips | Essential | Sales · Marketing · Customer Service / Support · Operations · Finance & Accounting · HR & Recruitment · IT · Procurement / Purchasing · Legal / Compliance · R&D / Product · Logistics / Supply Chain · Production / Manufacturing · Project Management / Delivery · Quality Control · Executive / Administration · Other → `q07_departments_other` |
| `q08_department_headcount` | Approximately how many employees work in each selected department or function? | ⚠ per_item_numeric | Recommended | One numeric input per item selected in Q07, each with a "Not sure" toggle. Integer > 0. Total need not match Q03. **NEW** |
| `q09_core_processes` | Which processes are important to the day-to-day running of your business? | multi_select (grouped) | Essential | **Sales & Customer:** lead generation / sales · quotations / proposals · order processing · customer service. **Supply & Operations:** procurement / purchasing · supplier management · inventory / warehouse · logistics / delivery · production / manufacturing · project management / delivery. **Corporate & Support:** finance / accounting · collections / payment follow-up · HR / recruitment · payroll · reporting / MI · internal approvals · compliance / quality control · document processing · scheduling · Other. No maximum. **NEW** |

**Screen 2B — How Work Is Organised**

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q10_process_documentation` | How well documented are your company's main processes? | single_select | Essential | Most major processes are formally documented · Some processes are documented · Documentation is limited · We do not have formal process documentation · Not sure. **NEW** |
| `q10a_documentation_types` | What types of process documentation are available? | multi_select | ⚠ Conditional | Shown on the same card as Q10, only when documentation exists. SOPs · ISO procedures / work instructions · Process maps / flowcharts · Departmental procedures · Policies · Quality manuals · Checklists · Training manuals · Forms / templates · Compliance procedures · Other · Not sure. **NEW** |
| `q10b_certifications` | Does your organisation hold any formal management-system certifications or process standards? | multi_select | Optional | Same card as Q10. ISO 9001 · ISO 14001 · ISO 45001 · ISO 27001 · Other ISO certification · Other formal certification / standard · None · Not sure. **NEW** |
| — | *Informational message (not a field)* | static | — | "You can upload procedures and process documents after onboarding. Worktruth can analyse them together with employee interviews to identify AI, automation and process-improvement opportunities." |
| `q11_manual_process_areas` | Which areas do you believe currently involve the most manual or administrative work? | multi_select (grouped) | Essential | Reuses the Q09 taxonomy, plus Other and Not sure. No maximum |
| `q12_department_handoffs` | Are there any areas where one department regularly has to wait for, chase or manually exchange information with another department? | textarea | Optional | Helper: "If yes, briefly describe one or two examples." **NEW** |
| `q13_key_person_dependency` | Are there important tasks or processes that depend heavily on the knowledge of one or a few employees? | textarea | Optional | Helper gives examples. **NEW** |
| `q14_approval_methods` | How are internal approvals usually handled? | multi_select | Essential | Automated workflow · Through ERP or another business system · Email · Teams / Slack / internal messaging · WhatsApp or similar · Paper / printed forms · Verbal / in person · Combination of methods · Very few approvals required · Not sure |

---

### Step 3 of 8 — How Work Gets Done

Three screens. Do not put all seven questions on one page.

**Screen 3A — Where Employee Time Goes**

Intro copy: "Think about the organisation as a whole. Select activities that take meaningful employee time rather than things that happen only occasionally."

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q15_time_consuming_work` | Which types of work currently take significant employee time? | multi_select (grouped) ⚠chips+search | Essential | **Communication & Follow-up:** reading / responding to emails or messages · following up with customers · following up with suppliers · following up internally · answering repetitive questions. **Documents & Data:** searching for information · reading / reviewing documents · processing scanned documents, forms or images · working extensively in Excel · entering data · uploading / importing data · moving information between systems. **Analysis & Decisions:** comparing information from different sources · checking information against rules · analysing information before deciding · monitoring orders, projects, cases or deadlines. **Creating & Coordinating:** preparing reports · preparing quotations / proposals · drafting documents / correspondence · scheduling / coordinating · creating marketing or content material · updating systems after work is done. Other · Not sure. **NEW** |
| `q21_high_volume_activity` | Are there activities your organisation performs repeatedly or in particularly high volumes? | ⚠ multi_select_with_detail | Recommended | Shown here in the UX; ID stays Q21. Customer enquiries · emails / messages · orders · quotations · purchase orders · supplier communications · invoices · payments / collections · documents / forms · scanned documents · data entries · data uploads / imports · reports · applications / requests / cases · customer or supplier follow-ups · social-media / marketing content · Other · None significant · Not sure. Each selected item gets an optional free-text "approximate volume or frequency" (e.g. "500/day", "every morning"). **NEW** |

**Screen 3B — What Employees Do With Information**

Intro visual: "Information comes in → Employee reviews or thinks → Action follows."

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q16_information_types` | What kinds of information or documents do employees regularly work with? | multi_select | Essential | Emails / messages · PDFs · scanned documents · forms · contracts · invoices · purchase orders · quotations · delivery documents · spreadsheets · reports · customer records · supplier records · policies / SOPs · technical documents · images / photographs · website or online information · Other · Not sure |
| `q17_information_processing` | When employees receive information such as an email, document, spreadsheet or request, what do they commonly need to do with it? | multi_select | Essential | Extract specific information · classify or categorise it · check whether information is complete · verify it against rules or policies · compare it with another document or source · summarise it · analyse it · identify errors or exceptions · decide who should handle it · decide what action should happen next · draft a response · enter or update information in a system · create a report or document · escalate unusual cases · Other · Not sure. **NEW** |

**Screen 3C — What Happens Next**

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q18_actions_after_review` | After employees review or process information, what actions do they commonly take? | multi_select | Essential | Send an email or message · update ERP, CRM or another system · upload a file or record · create a task · prepare a document · request approval · approve or reject something · follow up · schedule something · notify another employee or department · notify a customer or supplier · escalate an exception · update a spreadsheet · create or update a report · Other · Very little / none · Not sure. **NEW** |
| `q19_monitoring_activity` | What activities require employees to keep checking for changes, updates or exceptions? | multi_select | Essential | Customer enquiries · supplier responses · orders · shipments / deliveries · stock levels · payments / overdue accounts · approvals · projects · deadlines · service requests / tickets · compliance requirements · system alerts · competitor or market activity · website / online activity · Other · None that I am aware of · Not sure. **NEW** |
| `q20_content_research` | Do employees spend meaningful time on any of the following content, research or knowledge activities? | multi_select | Recommended | Preparing presentations · writing reports · drafting emails or correspondence · creating marketing content · creating social-media content · managing or scheduling social media · SEO / website content optimisation · market research · competitor research · product descriptions · preparing training materials · creating internal procedures or documentation · analysing customer feedback · researching information online · translating or adapting content · Other · None / not significant · Not sure. **NEW** |

---

### Step 4 of 8 — Systems & Information

Two screens.

**Screen 4A — Your Main Tools**

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q22_business_systems` | Which main software systems does your company use? | ⚠ category_matrix | Recommended | 12 categories: ERP / core business system · CRM / sales management · accounting / finance · HR / payroll · warehouse / inventory · POS / retail · project management · customer service / ticketing · production / manufacturing · document management · BI / reporting · other important systems. Per category: searchable known-system list, free-text fallback, None, Custom / in-house, Not sure. Not every row need be completed. **MERGE of 4 v1 fields** |
| `q23_productivity_tools` | Which of these tools are regularly used by employees? | multi_select ⚠chips | Essential | Microsoft 365 · Outlook · Excel · Microsoft Teams · SharePoint / OneDrive · Google Workspace · Gmail · Google Drive · Slack · WhatsApp · Zoom · Other · Not sure |

**Screen 4B — How Information Moves**

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q24_system_connection` | How well are your main business systems connected? | single_select | Essential | Most systems exchange information automatically · Some systems are integrated while others are separate · Most systems operate separately · Employees frequently copy or re-enter information between systems · Not sure |
| `q25_manual_data_movement` | Where do employees manually copy, move, upload or re-enter information? | multi_select | Recommended | From emails into business systems · from Excel into business systems · between CRM and ERP · from business systems into Excel · from websites or online forms into internal systems · from customer portals into internal systems · from supplier portals into internal systems · between internal systems · from paper or scanned documents into systems · Other · Very little / none · Not sure. **NEW** |
| `q25a_manual_movement_example` | Briefly describe an important example, if useful. | text | Optional | Same card as Q25. **NEW** |
| `q26_information_storage` | Where is company information mainly stored? | multi_select | Essential | ERP / CRM / other business systems · SharePoint / OneDrive · Google Drive · other cloud storage · on-premise servers · employee computers · email inboxes · spreadsheets · physical / paper files · Other · Not sure |
| `q27_information_findability` | How easy is it for employees to find the information they need to do their jobs? | single_select | Essential | Very easy — centralised and searchable · Generally easy · Sometimes difficult · Difficult — spread across systems or people · Very difficult — depends on specific employees · Not sure |
| `q28_reporting_method` | How are management or operational reports typically prepared? | multi_select | Recommended | Mostly automated dashboards · generated automatically from business systems · generated from systems but manually reviewed or reformatted · mainly prepared in Excel · manually collected from several systems · manually collected from several departments · prepared when requested · require significant written analysis or commentary · Other · Not sure |

---

### Step 5 of 8 — External Business Activity

Single screen.

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q29_external_parties_channels` | Which external parties does your organisation regularly interact with, and how do you usually communicate or exchange information with them? | ⚠ two_stage_matrix | Essential | **Stage 1 — parties:** customers / clients · suppliers / vendors · distributors / dealers · contractors / subcontractors · logistics / freight providers · banks / financial institutions · government / regulatory bodies · professional advisers · business partners · Other. **Stage 2 — channels per selected party:** email · phone · WhatsApp · website / online forms · customer or supplier portals · direct system integration / EDI · shared files / cloud folders · mobile apps · social media · in person · paper documents · Other. Desktop may use a compact matrix; mobile must use cards |
| `q30_external_manual_work` | Which activities involving external parties require significant manual work or repeated follow-up? | multi_select | Essential | Responding to enquiries · preparing quotations / proposals · processing customer orders · requesting supplier quotations · comparing supplier offers · creating purchase orders · customer follow-up · supplier follow-up · shipment / delivery follow-up · document exchange · updating customer or supplier portals · processing invoices or statements · collecting information from external parties · updating internal systems · scheduling meetings / appointments · resolving issues or exceptions · Other · Very little / none · Not sure. **NEW** |

---

### Step 6 of 8 — Challenges & Priorities

Single screen. **Q33 is displayed first**, ahead of Q31 and Q32, to capture a spontaneous answer before the user sees structured categories. Storage keys keep spec numbering.

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q33_top_improvements` | If you could significantly improve three things about how work gets done in your company, what would they be? | ⚠ parallel_text (×3) | Essential | Three short text inputs: first / second / third priority. Do not show suggested categories before this question. **NEW** |
| `q31_operational_challenges` | What are the biggest operational challenges in your organisation today? | multi_select | Essential | Too much manual or repetitive work · high employee workload · too much time spent on administration · slow customer or external-party response · slow supplier / procurement processes · disconnected systems · duplicate data entry · slow approvals · difficulty finding information · dependence on particular employees · errors caused by manual work · slow reporting · lack of management visibility / KPIs · too many emails or messages · difficult coordination between departments · difficult coordination with external parties · inventory / stock visibility problems · difficulty scaling · high operating cost · Other · Not sure. **No maximum** |
| `q32_error_delay_areas` | Where do errors, delays or inconsistencies occur most often? | multi_select | Recommended | Sales / quotations · customer orders · procurement / purchasing · supplier management · inventory / warehouse · logistics / delivery · production / operations · finance / invoicing · HR / payroll · reporting · data entry · scheduling · approvals · documents · communication between departments · communication with external parties · Other · No significant recurring issues · Not sure |
| `q34_active_projects` | Are there any major system, digital transformation, automation or AI projects already underway that Worktruth should know about? | textarea | Optional | Helper examples: ERP implementation, CRM replacement, Power BI, Power Automate, document automation, chatbot, custom AI. **NEW** |

---

### Step 7 of 8 — AI, Automation & Employee Readiness

Single screen. Avoid unnecessary technical terminology.

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q35_current_ai_automation` | Which AI or automation capabilities does your organisation currently use? | multi_select (grouped) | Essential | **Automation:** built into ERP / CRM / other existing systems · Microsoft Power Automate · Zapier · Make · UiPath · Automation Anywhere · custom scripts or applications · other workflow / process automation. **AI:** ChatGPT / Claude / similar · Microsoft Copilot · Google Gemini / Workspace AI · AI features built into existing software · chatbots / conversational AI · tools that read, extract or check documents · AI for reporting / analytics · AI for marketing / content · AI used within automated workflows · custom-built AI applications · AI agents that carry out multi-step tasks. **Other:** we currently use none of these · Other · Not sure. **Mutually exclusive:** selecting "none of these" must block or warn on other selections. **MERGE of 2 v1 fields** |
| `q36_adoption_readiness` | How ready is your organisation to introduce new technology, automation or AI solutions? | single_select | Essential | Very ready — actively looking to implement · Ready if there is a clear business case · Interested, but would prefer to test or pilot first · Cautious about major changes · Not currently ready · Not sure |
| `q37_ai_employee_capability` | How would you describe employees' current ability to use AI and modern productivity tools effectively? | single_select | Essential | Strong — many employees already use them effectively · Mixed — some capable, others need support · Basic — usage is limited · Very limited — most employees have little experience · We have not assessed this · Not sure. **NEW** |
| `q37a_ai_training` | What AI guidance or training does your organisation currently provide? | multi_select | Recommended | Same card as Q37, separate field. Formal AI policy / acceptable-use guidance · general AI-awareness training · role-specific AI training · Copilot / productivity-AI training · other formal AI training · informal guidance only · no formal guidance or training · Not sure. **NEW** |
| `q38_failed_ai_projects` | Has your organisation previously tried an AI or automation solution that did not work as expected? | textarea | Optional | Helper: if yes, briefly explain what was attempted and what happened. **NEW** |

---

### Step 8 of 8 — Governance & What You Want to Achieve

Single screen.

| Key | Question | Type | Tier | Options / notes |
|---|---|---|---|---|
| `q39_restrictions` | Are you aware of any privacy, security, regulatory or data restrictions that Worktruth should consider? | multi_select | Essential | GDPR · healthcare / patient-data requirements · financial-services regulations · government / confidential-information requirements · local data-residency requirements · ISO 27001 or similar · internal restrictions on cloud systems · internal restrictions on AI · Other · None known · Not sure |
| `q40_desired_outcomes` | What would you most like Worktruth to help your organisation achieve? | multi_select (grouped) | Essential | **Find Opportunities:** identify work where AI could assist employees · identify work AI agents could partially perform · identify work AI agents could substantially or fully perform with appropriate controls · reduce repetitive or administrative work · automate multi-step processes · improve employee decision support · make better use of AI already in existing software · identify opportunities using Microsoft 365 / Copilot or similar · identify where employee AI training could improve productivity. **Improve the Business:** reduce operating costs · save employee time · increase productivity · reduce errors · improve customer service · improve supplier / external-party interaction · improve response times · improve access to company knowledge · improve reporting and management visibility · improve decision-making · scale without increasing headcount at the same rate · improve employee experience · Other. **No maximum. MERGE of 2 v1 fields** |
| `q41_specific_investigation` | Is there anything specific you would like Worktruth to investigate during this assessment? | textarea | Optional | Helper examples: quotation preparation, supplier follow-up, scanned-document checking, Excel-heavy work, management reporting, marketing activities |

---

## 7. Fields needing new component types

Everything not listed here uses an existing field type and can be built in Stage 2 from config alone.

| Key | New type needed | Stage 2 placeholder |
|---|---|---|
| `q08_department_headcount` | `per_item_numeric` — one numeric input per Q07 selection | Single text field: "Approx. headcount per department" |
| `q29_external_parties_channels` | `two_stage_matrix` — parties, then channels per party | Two separate multi-selects (parties; channels overall) |
| `q21_high_volume_activity` | `multi_select_with_detail` — optional free text per selected item | Plain multi-select, no detail capture |
| `q33_top_improvements` | `parallel_text` — three inputs, one field | One textarea, three lines requested in helper text |
| `q22_business_systems` | `category_matrix` — 12 category rows with searchable value | 12 separate searchable_selects, or one textarea |
| `q10a_documentation_types` | Conditional reveal on same screen | Always visible (condition added in Stage 4) |
| `q07`, `q15`, `q23` | Chip/card selection with search | Existing checkbox grid |
| All "Other" fields | Inline "Please specify" text input | Plain "Other" option, no text capture |

**"Other" storage.** Per the approved decision, the typed value goes in a sidecar key — `<field_key>_other` — not inside the array. Multi-select values stay `string[]`, which is what the agent context, admin UI and API types already expect.

Fields with an "Other" option needing a sidecar key: `q01`, `q05`, `q07`, `q09`, `q10a`, `q10b`, `q11`, `q15`, `q16`, `q17`, `q18`, `q19`, `q20`, `q21`, `q23`, `q25`, `q26`, `q28`, `q29`, `q30`, `q31`, `q32`, `q35`, `q39`, `q40`.

---

## 8. Downstream code that reads v1 keys

From the codebase investigation. These read questionnaire keys directly and must be checked when v2 lands — they will not break (v1 keys are untouched), but they will not see v2 data either until updated.

- `Companies::QuestionnaireProgress` — `FIELD_IDS`, `SECTION_FIELDS` (whitelist + progress)
- `Companies::QuestionnaireSync` — `SYSTEM_KEYS`, `INDUSTRY_MAP`, `SIZE_MAP`, `REVENUE_MAP`
- `Api::V1::Company::OnboardingController` — step clamp (1..10 → 1..8) and the whitelist slice
- `Api::V1::Platform::CompaniesController#company_detail_json` — serves raw answers to admin
- `Companies::AgentContext.docs_profile_snapshot` — ships the raw blob to the agent runtime
- `Services::Documents::LocalDocsAnalysisFallback` — reads `primary_goals`, `erp_system`
- `agent/app/docs_analysis_graph.py` — reads `primary_goals`
- `frontend/src/portals/platform/PlatformCompanyDetail.tsx` — hardcoded label map for ~23 v1 keys
- `frontend/src/lib/api.ts` — types answers as `Record<string, string | string[]>`
- Specs: `onboarding_profile_spec.rb`, `questionnaire_progress_spec.rb`

---

## 9. Open items

1. **`annual_revenue_band` refresh.** Dropping `annual_revenue` means the profile band stops updating from onboarding. Still editable via settings. Confirm acceptable.
2. **Mutually exclusive options.** Q35 needs "none of these" to clear other selections. Q21 ("None significant") and Q37A ("no formal guidance") have the same pattern. Confirm the behaviour is consistent — clear-on-confirm, or warn-only.
3. **Country list source.** Q04 needs a full country list; the v1 field used a preset 20. Confirm which list to use.
4. **Known-systems lists for Q22.** The matrix needs a searchable list per category. v1 has lists for ERP/CRM/accounting/HR only — the other 8 categories need sources or start as free text.
5. **Migration scope.** How many companies have completed or started v1 is still unknown — needs a running database. Does not block, since versioning handles both cases.

---

*Generated as build input for the v2 questionnaire rebuild. Section 6 is the authoritative field list; the spec document is the authority on intent.*
