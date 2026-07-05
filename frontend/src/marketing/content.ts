/**
 * Marketing site copy — single source of truth for the public homepage.
 * Edit here when positioning, pricing, or product capabilities change.
 * Voice: warm, plain, confident — the product interviews people, so the site talks like a person.
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
    ctaLabel: 'Get started',
  },

  hero: {
    eyebrow: 'Workflow discovery on WhatsApp',
    headline: 'Your team already knows what’s broken.',
    headlineAccent: 'Just ask.',
    subhead:
      'Req chats with every employee on WhatsApp — text, voice notes, photos, documents — and turns what they say into signals, patterns, and a board-ready automation roadmap. No new apps. No six-month discovery project.',
    primaryCta: 'Get started',
    secondaryCta: 'See how it works',
    chat: {
      contactName: 'Req',
      contactStatus: 'online · WhatsApp',
      messages: [
        {
          from: 'req' as const,
          text: 'Morning Jordan! Walk me through what happens after an invoice lands in your inbox? 📄',
        },
        {
          from: 'employee' as const,
          text: 'Honestly? I re-type it into SAP, then chase two approvals over email. Month-end it’s 40+ invoices…',
        },
        {
          from: 'req' as const,
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
      { value: '3–5 wks', label: 'to first executive report' },
      { value: '85%+', label: 'employee participation on WhatsApp' },
      { value: '100%', label: 'of findings traceable to real quotes' },
    ],
    statsDisclaimer: 'Early enterprise programs; timelines vary with cohort size.',
  },

  logos: {
    eyebrow: 'Trusted by transformation teams across',
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
      'Transformation stalls when discovery is slow, shallow, or filtered through three layers of management. Req goes straight to the people doing the work.',
    pains: [
      {
        title: 'Surveys measure mood, not workflow',
        description:
          'A Likert scale can’t capture the seventeen-step workaround finance invented after the ERP rollout — or who still emails spreadsheets because approvals time out.',
      },
      {
        title: 'Consulting discovery is expensive and episodic',
        description:
          'A six-week interview blitz produces a deck, then the map goes stale. Req keeps discovery running: invite more people, refresh intelligence, regenerate the report.',
      },
      {
        title: 'IT assessments miss the front line',
        description:
          'Architecture diagrams show systems talking to systems. They never show the 45 minutes per invoice someone spends reconciling SAP against three trackers.',
      },
      {
        title: 'AI pilots fail without operational truth',
        description:
          'You can’t prioritise automation until you know which processes are manual, duplicated, and politically entrenched. Req surfaces the evidence — quotes included.',
      },
    ],
  },

  howItWorks: {
    eyebrow: 'How it works',
    title: 'From a WhatsApp “hi” to a board-ready roadmap',
    subtitle: 'Three layers: conversation, intelligence, and governed delivery.',
    steps: [
      {
        title: 'Employees chat. That’s it.',
        description:
          'Invite your team with per-person access codes. Req says hello on WhatsApp, gets consent in their language, and interviews them the way a great consultant would — adapting questions by role, department, and what they said last.',
        details: [
          'No login, no app, no training',
          'Voice notes transcribed, photos and PDFs understood',
          'Specialist AI interviewers for domain, process, technical and strategy questions',
        ],
      },
      {
        title: 'Conversations become intelligence',
        description:
          'Every answer is distilled into signals — pain points, tools, time sinks. Signals cluster into patterns: recurring bottlenecks, shadow processes, cross-team dependencies. Your dashboard fills in live as interviews complete.',
        details: [
          'Readiness score and department coverage at a glance',
          'Pattern detection across teams and systems',
          'Company memory: every interview makes the next one smarter',
        ],
      },
      {
        title: 'A report you can defend',
        description:
          'Req generates versioned reports with deltas against the last run. Expert reviewers annotate section by section and follow up with employees on WhatsApp before anything reaches your leadership. Recommendations map to real tools.',
        details: [
          'Versioned PDF & share links with access logging',
          'Independent expert review before delivery',
          'Ranked automation opportunities with evidence',
        ],
      },
    ],
  },

  discover: {
    eyebrow: 'Intelligence',
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
    eyebrow: 'Platform',
    title: 'One platform. Every seat at the table.',
    subtitle:
      'Operators run discovery, companies consume intelligence, independent experts guarantee quality — each in their own portal.',
    audiences: [
      {
        title: 'Company portal',
        for: 'Transformation leads & operations',
        features: [
          'Onboarding wizard: profile, employee invites, WhatsApp setup',
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
          'WhatsApp follow-ups with employees, invisible to the company',
          'Co-reviewer chat for coordination on complex accounts',
        ],
      },
      {
        title: 'Platform console',
        for: 'Req operators & partners',
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
      'Run discovery in-house or as a partner — Req compresses time-to-insight without sacrificing depth.',
    items: [
      {
        title: 'COO & transformation offices',
        body: 'A single source of operational truth before a reorg, ERP cutover, or AI rollout — grounded in frontline interviews, not workshop stickies.',
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
        body: 'Repeatable discovery engagements with governed reviewer workflows, client-ready PDFs, and WhatsApp-level participation rates.',
      },
    ],
  },

  testimonial: {
    quote: {
      text: 'We finally had a shared picture of how work actually flows — not how the org chart says it should. The WhatsApp channel got us answers from people who would never join a workshop.',
      attribution: 'VP Operations',
      company: 'Fortune 500 industrial group',
    },
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
        a: 'Plans are tiered by conversation volume — trial, starter, and growth — with in-app billing. Get started for a guided walkthrough and cohort sizing.',
      },
    ],
  },

  cta: {
    eyebrow: 'Get started',
    title: 'Hear what your team has been trying to tell you',
    subtitle:
      'Tell us about your organisation and discovery goals. We’ll walk you through a live demo with the company portal, sample intelligence, and report output.',
    button: 'Get started',
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
export type HeroChatMessage = (typeof marketingContent.hero.chat.messages)[number];
