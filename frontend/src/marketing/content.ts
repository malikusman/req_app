/**
 * Marketing site copy — single source of truth for the public homepage.
 * Edit here when positioning, pricing, or product capabilities change.
 * Voice: warm, plain, confident — the product interviews people, so the site talks like a person.
 * Brand: Worktruth
 */

export const BRAND_NAME = 'Worktruth';
export const SALES_EMAIL = 'sales@worktruth.com';

export const marketingContent = {
  nav: {
    links: [
      { label: 'How it works', href: '#how-it-works' },
      { label: 'What you discover', href: '#what-you-discover' },
      { label: 'Platform', href: '#platform' },
      { label: 'FAQ', href: '#faq' },
    ],
    signInLabel: 'Sign in',
    ctaLabel: 'Request a demo',
  },

  hero: {
    eyebrow: 'Operational discovery — documents and conversations',
    headline: 'Your team already knows what’s broken.',
    headlineAccent: 'Just ask.',
    subhead:
      'Worktruth builds operational truth from the evidence you already have: upload SOPs and exports for a baseline, then interview people on WhatsApp or web chat. Same intelligence graph. Versioned reports your leadership can defend.',
    primaryCta: 'Request a demo',
    secondaryCta: 'See how it works',
    chat: {
      contactName: 'Worktruth',
      contactStatus: 'online · WhatsApp',
      messages: [
        {
          from: 'agent' as const,
          text: 'Morning Jordan! Walk me through what happens after an invoice lands in your inbox? 📄',
        },
        {
          from: 'employee' as const,
          text: 'Honestly? I re-type it into SAP, then chase two approvals over email. Month-end it’s 40+ invoices…',
        },
        {
          from: 'agent' as const,
          text: 'That sounds heavy. Where does it usually get stuck — the re-typing or the approvals?',
        },
        {
          from: 'employee' as const,
          text: 'Approvals. Finance sign-off can take three days every single time.',
        },
      ],
      insight: {
        label: 'Signal detected',
        text: 'Manual invoice entry + 3-day approval bottleneck · Finance · high automation potential',
      },
    },
    stats: [
      { value: '2 ways in', label: 'Start from documents, from interviews, or run both together' },
      { value: '1 evidence graph', label: 'Signals strengthen as interviews add live evidence' },
      { value: '0 apps to install', label: 'Employees answer on WhatsApp or a browser chat link' },
    ],
    statsDisclaimer:
      'Early enterprise programs. Document baselines cite internal files; quote-level interview evidence appears once conversations complete.',
  },

  logos: {
    eyebrow: 'Built for transformation teams in',
    industries: [
      'Global manufacturers',
      'Financial services',
      'Healthcare operators',
      'Logistics & supply chain',
      'Professional services',
    ],
  },

  problem: {
    eyebrow: 'The problem',
    title: 'Your org chart is not your operating model',
    subtitle:
      'Transformation stalls when discovery is slow, shallow, or filtered through three layers of management. Worktruth goes straight to the evidence — documents and the people doing the work.',
    pains: [
      {
        title: 'Surveys measure mood, not workflow',
        description:
          'A Likert scale can’t capture the seventeen-step workaround finance invented after the ERP rollout — or who still emails spreadsheets because approvals time out.',
      },
      {
        title: 'Consulting discovery is expensive and episodic',
        description:
          'A six-week interview blitz produces a deck, then the map goes stale. Worktruth keeps discovery running: upload more docs, invite more people, refresh intelligence, regenerate the report.',
      },
      {
        title: 'IT assessments miss the front line',
        description:
          'Architecture diagrams show systems talking to systems. They never show the 45 minutes per invoice someone spends reconciling SAP against three trackers.',
      },
      {
        title: 'AI pilots fail without operational truth',
        description:
          'You can’t prioritise automation until you know which processes are manual, duplicated, and politically entrenched. Worktruth surfaces structured evidence you can defend.',
      },
    ],
  },

  howItWorks: {
    eyebrow: 'How it works',
    title: 'Two ways in. One governed report out.',
    subtitle: 'Start with documents, start with people, or run both — intelligence accumulates on the same graph.',
    steps: [
      {
        title: 'Upload a document baseline',
        description:
          'Drop in SOPs, policies, org charts, and finance exports. Worktruth parses text, extracts structured signals, and can produce a baseline report with zero employees invited.',
        details: [
          'SOPs, policies, CSVs, and common office formats',
          'Department tagging for coverage and readiness',
          'Baseline PDF when readiness hits the docs-phase bar',
        ],
      },
      {
        title: 'Interview the people who do the work',
        description:
          'Invite employees with per-person access codes. They answer on WhatsApp or web chat — text, voice, photos, documents. Specialist interviewers adapt by role and department when advanced discovery is enabled.',
        details: [
          'WhatsApp-primary; web chat when WhatsApp isn’t practical',
          'Consent capture and adaptive follow-ups',
          'Live quotes strengthen the same signals from your docs',
        ],
      },
      {
        title: 'A report you can defend',
        description:
          'Worktruth generates versioned reports with deltas against the last run. Expert reviewers annotate section by section before anything reaches leadership. Recommendations map to your solution catalog with evidence links.',
        details: [
          'Versioned PDF & share links with access logging',
          'Independent expert review before delivery',
          'Ranked opportunities grounded in signals and patterns',
        ],
      },
    ],
  },

  discover: {
    eyebrow: 'Intelligence',
    title: 'What you discover',
    subtitle:
      'Documents and interviews feed a structured model of how work really happens — not how the process wiki says it should.',
    cards: [
      {
        title: 'Bottlenecks',
        description:
          'Queues, approval delays, and system timeouts where work waits — ranked by frequency and departments affected.',
        span: 'lg:col-span-2 lg:row-span-2' as const,
      },
      {
        title: 'Manual workflows',
        description: 'Copy-paste between tools, duplicate data entry, and swivel-chair processes ripe for automation.',
        span: '' as const,
      },
      {
        title: 'Time sinks',
        description:
          'Activities that consume hours every week but never appear on a strategy slide — until your people describe them.',
        span: '' as const,
      },
      {
        title: 'Cross-team dependencies',
        description:
          'Handoffs that fail under load: who waits on whom, which teams become blockers at month-end or quarter-close.',
        span: 'lg:col-span-2' as const,
      },
      {
        title: 'AI opportunities',
        description:
          'High-impact candidates for automation or copilots — mapped to your solution catalog with evidence from documents and conversations.',
        span: '' as const,
      },
      {
        title: 'Shadow processes',
        description:
          'Workarounds, personal spreadsheets, and unofficial steps that keep the business running when official tools do not.',
        span: '' as const,
      },
    ],
  },

  evidenceFlow: {
    eyebrow: 'The evidence graph',
    title: 'Watch evidence become a report',
    subtitle:
      'Every file and every answer lands on one graph. Signals cluster into patterns, patterns rank opportunities, and the report regenerates — version by version — as evidence grows.',
    inputs: [
      { kind: 'document' as const, title: 'freight-billing-sop.pdf', caption: 'Uploaded by ops' },
      { kind: 'chat' as const, title: '“Approvals take 3 days, every time.”', caption: 'WhatsApp · Finance' },
      { kind: 'voice' as const, title: 'Voice note · 0:42', caption: 'Warehouse walkthrough' },
      { kind: 'image' as const, title: 'pod-scan-sample.png', caption: 'Read with vision OCR' },
    ],
    hub: {
      title: 'Evidence graph',
      caption: 'Signals · patterns · systems',
    },
    outputs: [
      { step: 'Signal', text: 'Manual invoice entry + approval bottleneck · Finance' },
      { step: 'Pattern', text: 'Confirmed across 3 teams · high automation potential' },
      { step: 'Report v3', text: 'Reviewer-approved PDF · ranked opportunities · deltas vs v2' },
    ],
  },

  alwaysOn: {
    eyebrow: 'Beyond the report',
    title: 'Discovery that keeps working after the PDF',
    subtitle:
      'The report is a milestone, not the finish line. Worktruth keeps matching your evidence against what is possible — and tells the right people when something changes.',
    items: [
      {
        title: 'An agentic-AI backlog, grounded in your evidence',
        body: 'Signals and patterns are matched against your actual tool stack to draft automation and AI-agent ideas — each with the systems it touches and a confidence score. Experts review and publish them into the report’s Opportunities section.',
        badge: 'Opportunities',
      },
      {
        title: 'AI market intelligence, matched to your people',
        body: 'Curated AI and automation news is analyzed and matched to opted-in employees by role, department, and tools — only high-fit items are sent, capped at a couple of emails a month. No newsletter noise.',
        badge: 'Market alerts',
      },
      {
        title: 'Stack-aware recommendations',
        body: 'Worktruth infers which systems you already run from documents and interviews. Recommendations flag whether a tool extends something you own or adds a new capability — so effort estimates are honest.',
        badge: 'Client stack',
      },
    ],
  },

  platform: {
    eyebrow: 'Platform',
    title: 'One platform. Every seat at the table.',
    subtitle:
      'Operators run discovery, companies consume intelligence, independent experts guarantee quality — each in their own portal.',
    audiences: [
      {
        title: 'Company portal',
        for: 'Transformation leads & operations',
        features: [
          'Onboarding: profile, documents-first or hybrid mode, employee invites',
          'Live dashboard: participation, readiness, department heatmap',
          'Signals, patterns, timeline, and discovery-question feedback',
          'Document upload feeding the same intelligence graph',
          'Versioned reports, share links, settings, and billing',
        ],
      },
      {
        title: 'Reviewer portal',
        for: 'Domain experts & delivery partners',
        features: [
          'Assigned companies only — up to two reviewers per client',
          'Section-by-section report review and approval workflow',
          'WhatsApp follow-ups with employees for clarification',
          'Co-reviewer chat for coordination on complex accounts',
        ],
      },
      {
        title: 'Platform console',
        for: 'Worktruth operators & partners',
        features: [
          'Company and trial management, audit log, support impersonation',
          'Discovery playbooks by department and solution catalog',
          'Cross-tenant monitoring: agents, queues, WhatsApp delivery',
          'Report approval gate when clients require platform sign-off',
        ],
      },
    ],
  },

  personas: {
    eyebrow: 'Who it’s for',
    title: 'Built for teams who own change',
    subtitle:
      'Run discovery in-house or as a partner — Worktruth compresses time-to-insight without sacrificing depth.',
    items: [
      {
        title: 'COO & transformation offices',
        body: 'A single source of operational truth before a reorg, ERP cutover, or AI rollout — grounded in documents and frontline interviews, not workshop stickies.',
      },
      {
        title: 'Operations & process excellence',
        body: 'Department coverage, pain-point strength, and pattern recurrence in one dashboard instead of fifty interview notes.',
      },
      {
        title: 'Technology & automation leaders',
        body: 'Prioritise integrations and agents with evidence: which tools people actually use, and where an API won’t fix the real bottleneck.',
      },
      {
        title: 'Consultancies & BPO partners',
        body: 'Repeatable discovery engagements with governed reviewer workflows, client-ready PDFs, and high participation without new apps.',
      },
    ],
  },

  method: {
    eyebrow: 'The method',
    quote:
      'Start with the files that already describe how work should happen — then interview the people who know where it actually breaks. Worktruth keeps both on one evidence graph so the report gets stronger over time, not rewritten from scratch.',
    label: 'How every Worktruth engagement runs',
  },

  faq: {
    title: 'Frequently asked questions',
    items: [
      {
        q: 'Do employees need to install an app?',
        a: 'No. Interviews happen in WhatsApp after a one-time consent flow, or in a browser chat when WhatsApp isn’t the right channel. They can reply with text, voice notes, images, or documents.',
      },
      {
        q: 'How is this different from an employee survey?',
        a: 'Surveys aggregate opinions. Worktruth runs adaptive interviews and structured extraction from documents: follow-ups clarify tools and steps, then signals and patterns are tied to workflow evidence — quotes from interviews, excerpts from files.',
      },
      {
        q: 'What languages are supported?',
        a: 'Discovery adapts to the language employees use in chat. Playbooks can be scoped by department; platform operators manage active playbook versions.',
      },
      {
        q: 'How do you handle privacy and access?',
        a: 'Per-employee access codes, consent capture, JWT-scoped portals, and role separation between company admins and external reviewers. Report share links are tokenized with access logging. See our Privacy page for retention and contact details.',
      },
      {
        q: 'Can we upload existing process documents?',
        a: 'Yes — and you can start there. Upload SOPs, policies, and finance exports for a document baseline report with zero employees invited. When people join later, the same signals strengthen with interview evidence. Quote-level traceability applies once interviews are in the mix.',
      },
      {
        q: 'Do we have to interview employees on day one?',
        a: 'No. Choose documents-only or hybrid in onboarding. Many teams start with internal docs, generate a baseline, then invite employees so intelligence accumulates rather than starting over.',
      },
      {
        q: 'How does readiness scoring work?',
        a: 'With no completed interviews, readiness is document-weighted (ready files, department coverage, signals, confirmed patterns). As employees finish interviews, the score blends toward interview-weighted dimensions so you don’t fall off a cliff when the first person completes.',
      },
      {
        q: 'What does “tied to real quotes” mean?',
        a: 'Interview findings can link back to employee answers. Document baselines cite internal files and excerpts — not live quotes — until conversations add them.',
      },
      {
        q: 'What happens after the report is delivered?',
        a: 'Discovery stays on. Upload more documents or invite more people and the same intelligence refreshes — reports regenerate with deltas against the last version. Evidence is also matched against your tool stack to maintain an agentic-AI opportunity backlog, and opted-in employees receive occasional high-fit AI market alerts relevant to their role.',
      },
      {
        q: 'What does pricing look like?',
        a: 'Plans are tiered by conversation volume: trial (included with setup), Starter ($499/mo), and Growth ($1,499/mo), with Enterprise available via sales. A conversation is a completed discovery interview. Document uploads are included; talk to sales for cohort sizing.',
      },
    ],
  },

  cta: {
    eyebrow: 'Request a demo',
    title: 'Hear what your team has been trying to tell you',
    subtitle:
      'Tell us about your organisation and discovery goals. We’ll walk you through the company portal, a sample baseline vs discovery report, and how readiness gates delivery.',
    button: 'Request a demo',
    note: 'Typical onboarding: profile setup, optional document uploads, then employee invites when you are ready — days, not months.',
  },

  footer: {
    tagline: 'Operational truth from the people who do the work.',
    links: [
      { label: 'How it works', href: '#how-it-works' },
      { label: 'Platform', href: '#platform' },
      { label: 'FAQ', href: '#faq' },
      { label: 'Privacy', href: '/privacy' },
    ],
  },
} as const;

export type DiscoverCardContent = (typeof marketingContent.discover.cards)[number];
export type HeroChatMessage = (typeof marketingContent.hero.chat.messages)[number];
