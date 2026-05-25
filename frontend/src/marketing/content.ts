/**
 * Marketing site copy — single source of truth for the public homepage.
 * Edit here when positioning, pricing, or product capabilities change.
 */

export const marketingContent = {
  nav: {
    links: [
      { label: 'How it works', href: '#how-it-works' },
      { label: 'What you discover', href: '#what-you-discover' },
      { label: 'Platform', href: '#platform' },
      { label: 'FAQ', href: '#faq' },
    ],
    signInLabel: 'Sign in',
    ctaLabel: 'Request access',
  },

  hero: {
    eyebrow: 'Enterprise workflow discovery',
    headlinePrefix: 'From conversations to',
    rotatingWords: ['workflows', 'bottlenecks', 'patterns', 'roadmaps'],
    headline: 'Understand how your company',
    headlineAccent: 'actually works',
    subhead:
      'Req runs adaptive AI interviews over WhatsApp with the people who do the work — then turns thousands of micro-conversations into signals, patterns, and an executive-ready transformation report. No new apps for employees. No six-month discovery projects.',
    bullets: [
      'Meet employees on WhatsApp — voice, text, images, and documents',
      'LangGraph-powered interviews that adapt by role and department',
      'Live intelligence dashboard plus versioned PDF reports for leadership',
    ],
    primaryCta: 'Request access',
    secondaryCta: 'See how it works',
    // discoveryGraph positions: keep x/y outside center ~30–70% so bubbles avoid headline
    discoveryGraph: {
      ariaLabel:
        'Animated discovery graph showing interviews connecting into shared intelligence',
      hub: { id: 'hub', x: 50, y: 72 },
      whatsappAppearances: 2,
      loopResetMs: 28000,
      interviews: [
        {
          id: 'sarah',
          name: 'Sarah K.',
          insight: 'Approvals stall 3 days in finance',
          x: 82,
          y: 16,
          connectsTo: ['hub'],
        },
        {
          id: 'james',
          name: 'James O.',
          insight: 'Ops handoffs lose context every Friday',
          x: 12,
          y: 20,
          connectsTo: ['sarah'],
        },
        {
          id: 'priya',
          name: 'Priya M.',
          insight: 'Onboarding docs are never the latest version',
          x: 90,
          y: 38,
          connectsTo: ['hub', 'sarah'],
        },
        {
          id: 'marcus',
          name: 'Marcus T.',
          insight: 'IT tickets reopen when procurement delays',
          x: 8,
          y: 48,
          connectsTo: ['james'],
        },
        {
          id: 'elena',
          name: 'Elena R.',
          insight: 'Sales quotes need three systems to align',
          x: 78,
          y: 58,
          connectsTo: ['priya', 'hub'],
        },
        {
          id: 'david',
          name: 'David L.',
          insight: 'Legal review blocks launches by a week',
          x: 18,
          y: 72,
          connectsTo: ['marcus', 'james'],
        },
        {
          id: 'amira',
          name: 'Amira H.',
          insight: 'HR policies differ by region in practice',
          x: 88,
          y: 78,
          connectsTo: ['elena', 'priya'],
        },
        {
          id: 'noah',
          name: 'Noah W.',
          insight: 'Warehouse scans do not sync until morning',
          x: 14,
          y: 88,
          connectsTo: ['david', 'hub'],
        },
        {
          id: 'lisa',
          name: 'Lisa P.',
          insight: 'Customer refunds need manager override twice',
          x: 72,
          y: 88,
          connectsTo: ['elena', 'amira'],
        },
        {
          id: 'omar',
          name: 'Omar B.',
          insight: 'Field teams share workarounds only on WhatsApp',
          x: 50,
          y: 12,
          connectsTo: ['sarah', 'priya'],
        },
      ],
    },
  },

  problem: {
    title: 'Your org chart is not your operating model',
    subtitle:
      'Transformation programs stall when discovery is slow, shallow, or filtered through layers of management. Req goes direct to the work.',
    pains: [
      {
        title: 'Surveys tell you sentiment, not workflow',
        description:
          'Likert scales cannot capture the seventeen-step workaround finance invented after the ERP rollout — or who still emails spreadsheets because the approval chain times out.',
      },
      {
        title: 'Consulting discovery is expensive and episodic',
        description:
          'A six-week interview blitz produces a deck, then the map goes stale. Req keeps discovery continuous: invite more employees, refresh intelligence, regenerate reports as the business changes.',
      },
      {
        title: 'IT-only assessments miss the front line',
        description:
          'Architecture diagrams show systems. They rarely show the 45 minutes per invoice someone spends reconciling SAP with three trackers — or which handoffs break every month-end.',
      },
      {
        title: 'AI pilots fail without operational truth',
        description:
          'You cannot prioritize automation until you know which processes are manual, duplicated, and politically entrenched. Req surfaces that evidence with quotes, signals, and ranked recommendations.',
      },
    ],
  },

  howItWorks: {
    title: 'How it works',
    subtitle:
      'From WhatsApp message to board-ready roadmap in three layers — conversation, intelligence, and governed delivery.',
    steps: [
      {
        title: 'Invite employees. They interview on WhatsApp.',
        description:
          'You upload or invite participants with per-person access codes. Req sends compliant WhatsApp templates; employees consent in their language. The AI interviewer adapts questions by department playbook — operations, finance, HR, or custom — and accepts text, voice notes, photos, and PDFs.',
        details: [
          'No employee login or training',
          'Adaptive follow-ups based on prior answers',
          'Multimodal input: voice (transcribed), images, documents',
        ],
      },
      {
        title: 'AI structures raw conversation into intelligence',
        description:
          'Each turn is processed through our LangGraph discovery agent. Insights become signals (pain points, tools, time sinks). Signals roll up into patterns — recurring bottlenecks, shadow processes, cross-team dependencies. A live dashboard shows readiness, department coverage, and top themes as interviews complete.',
        details: [
          'Per-turn insight extraction and session quality tracking',
          'Pattern detection across teams and systems',
          'Discovery questions you can flag as off-track or not relevant',
        ],
      },
      {
        title: 'Reports, reviewers, and recommendations you can act on',
        description:
          'When readiness thresholds are met, Req generates versioned HTML/PDF reports with deltas vs. the previous run. Assigned reviewers annotate sections, request WhatsApp follow-ups with employees, and collaborate in a private channel — invisible to the company admin until you choose. Recommendations tie to your solution catalog with prioritized AI opportunities.',
        details: [
          'Shareable report links with access logging',
          'Optional platform QA before delivery to the client',
          'Stripe-backed plans: trial, starter, and growth tiers',
        ],
      },
    ],
  },

  discover: {
    title: 'What you discover',
    subtitle:
      'Every interview feeds a structured model of how work really happens — not how the process wiki says it should.',
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
          'High-impact candidates for automation or copilots — mapped to your solution catalog with evidence from conversations.',
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

  platform: {
    title: 'One platform. Three audiences.',
    subtitle:
      'Req is built for operators running discovery, companies consuming intelligence, and expert reviewers ensuring quality.',
    audiences: [
      {
        title: 'Company portal',
        for: 'Transformation leads & operations',
        features: [
          'Onboarding wizard: profile, employee invites, WhatsApp instructions',
          'Live dashboard: participation, readiness score, department heatmap',
          'Signals, patterns, timeline, and discovery-question preview',
          'Document upload with AI extraction into the same intelligence graph',
          'Versioned reports, share links, settings, and billing',
        ],
      },
      {
        title: 'Reviewer portal',
        for: 'Domain experts & delivery partners',
        features: [
          'Assigned companies only — up to two reviewers per client',
          'Section-by-section report review and approval workflow',
          'WhatsApp follow-ups with employees (hidden from company APIs)',
          'Co-reviewer chat for coordination on complex accounts',
        ],
      },
      {
        title: 'Platform console',
        for: 'Req operators & partners',
        features: [
          'Company and trial management, audit log, impersonation for support',
          'Discovery playbooks by department, solution catalog, system health',
          'Cross-tenant monitoring: LangGraph, queues, WhatsApp delivery',
          'Report approval gate when clients require platform sign-off',
        ],
      },
    ],
  },

  personas: {
    title: 'Built for teams who own change',
    subtitle: 'Whether you run discovery in-house or as a partner, Req compresses time-to-insight without sacrificing depth.',
    items: [
      {
        title: 'COO & transformation offices',
        body: 'Get a single source of operational truth before a reorg, ERP cutover, or AI rollout — grounded in frontline interviews, not workshop stickies.',
      },
      {
        title: 'Operations & process excellence',
        body: 'See department coverage, pain-point strength, and pattern recurrence in one dashboard instead of synthesizing fifty interview notes.',
      },
      {
        title: 'Technology & automation leaders',
        body: 'Prioritize integrations and agents using evidence: which tools are actually used, where APIs will not fix the real bottleneck.',
      },
      {
        title: 'Consultancies & BPO partners',
        body: 'Run repeatable discovery engagements with governed reviewer workflows, client-ready PDFs, and WhatsApp-native participation rates.',
      },
    ],
  },

  socialProof: {
    eyebrow: 'Trusted by transformation teams',
    logos: [
      'Global manufacturers',
      'Financial services',
      'Healthcare operators',
      'Logistics & supply chain',
      'Professional services',
    ],
    quote: {
      text: 'We finally had a shared picture of how work actually flows — not how the org chart says it should. The WhatsApp channel got us answers from people who would never join a workshop.',
      attribution: 'VP Operations',
      company: 'Fortune 500 industrial group',
    },
    stats: [
      { value: '3–5 wks', label: 'Typical time to first executive report' },
      { value: '85%+', label: 'Employee participation when using WhatsApp' },
      { value: '100%', label: 'Interview evidence traceable to source turns' },
    ],
    disclaimer:
      'Figures represent outcomes from early enterprise programs; your timeline depends on cohort size and departments in scope.',
  },

  faq: {
    title: 'Frequently asked questions',
    items: [
      {
        q: 'Do employees need to install an app?',
        a: 'No. Interviews happen in WhatsApp after a one-time consent flow. They can reply with text, voice notes, images, or documents — whatever matches how they already work.',
      },
      {
        q: 'How is this different from an employee survey?',
        a: 'Surveys aggregate opinions. Req conducts adaptive interviews: the AI asks follow-ups, clarifies tools and steps, and extracts structured signals and patterns tied to real workflow evidence.',
      },
      {
        q: 'What languages are supported?',
        a: 'Discovery adapts to the language employees use in WhatsApp. Playbooks can be scoped by department; platform operators manage active playbook versions.',
      },
      {
        q: 'How do you handle privacy and access?',
        a: 'Per-employee access codes, consent capture, JWT-scoped portals, and role separation between company admins and external reviewers. Report share links are tokenized with access logging.',
      },
      {
        q: 'Can we upload existing process documents?',
        a: 'Yes. The company portal accepts PDFs; text is chunked, embedded, and merged with conversation intelligence so recommendations reflect both interviews and documentation.',
      },
      {
        q: 'What does pricing look like?',
        a: 'Plans are tiered by conversation volume — trial, starter, and growth — with in-app billing. Request access for a guided walkthrough and cohort sizing.',
      },
    ],
  },

  cta: {
    title: 'See your operating model — not your assumptions',
    subtitle:
      'Tell us about your organization and discovery goals. We will walk you through a live demo with the company portal, sample intelligence, and report output.',
    button: 'Request access',
    note: 'Typical onboarding: profile setup, employee invites, first interviews within days — not months.',
  },

  footer: {
    tagline: 'Operational intelligence from the people who do the work.',
    links: [
      { label: 'How it works', href: '#how-it-works' },
      { label: 'Platform', href: '#platform' },
      { label: 'FAQ', href: '#faq' },
      { label: 'Privacy', href: '#' },
    ],
  },
} as const;

export type DiscoverCardContent = (typeof marketingContent.discover.cards)[number];
