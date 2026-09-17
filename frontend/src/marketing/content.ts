/**
 * Marketing site copy — single source of truth for the public homepage.
 *
 * Written against the Mjadi website brief (v1.0, Sept 2026). Two rules from it
 * govern everything here:
 *
 *   1. Mjadi is new. There are no clients, no case studies, no results. So the
 *      site cannot claim experience — it has to demonstrate thinking. Every
 *      claim is either true today or plainly labelled as an illustration.
 *   2. Specificity is the whole strategy. Every competitor says "unlock the
 *      power of AI". The moment we say "prices re-keyed item by item every
 *      morning, roughly 170 hours a year", we stop being a category and become
 *      a company that has looked at real work.
 *
 * The reader is an owner or MD of a mid-sized business, most likely in the UAE.
 * They are not shopping for AI. They are shopping for clarity about their own
 * company. Write to them, not to a transformation office: no "evidence graph",
 * no "readiness scoring", no "operational truth" — those are our words for our
 * machinery, and they mean nothing across a desk.
 *
 * A third rule, learned from the first draft: length is not generosity. An
 * owner scanning this on a phone between meetings reads the headings and two
 * lines under each. Anything longer is decoration. Every card body here is one
 * or two sentences, and the page is nine blocks rather than thirteen.
 *
 * Brand: Mjadi
 */

export const BRAND_NAME = 'Mjadi';
export const SALES_EMAIL = 'sales@mjadi.com';

/**
 * Icon keys are resolved to components in the section that renders them.
 *
 * Deliberately not the display title: the previous version matched icons by
 * card title, so rewriting the copy silently dropped every card back to the
 * same fallback icon. Keys are stable; copy is not.
 */
export type DiscoverIcon = 'clock' | 'coins' | 'wrench' | 'ban';

export const marketingContent = {
  nav: {
    links: [
      { label: 'The situation', href: '#situation' },
      { label: 'An example', href: '#example' },
      { label: 'How we work', href: '#how-it-works' },
    ],
    signInLabel: 'Sign in',
    ctaLabel: 'Talk to us',
    signupLabel: 'Sign up',
    signupHref: '/company/signup',
  },

  hero: {
    eyebrow: 'AI transformation, starting with what you already do',
    headline: 'We show you where your business is losing time and money',
    headlineAccent: '— and what to do about it.',
    subhead:
      'Mjadi studies how your company actually works, department by department, then sizes what the waste is costing you and designs the fix.',
    primaryCta: 'Talk to us',
    secondaryCta: 'See how it works',
    chat: {
      contactName: 'Mjadi',
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
          text: 'That sounds heavy. Roughly how long does the re-typing take you in a week?',
        },
        {
          from: 'employee' as const,
          text: 'Four, maybe five hours. The approvals are worse — finance sign-off takes three days every time.',
        },
      ],
      insight: {
        label: 'What we heard',
        text: 'Invoices re-keyed by hand · ~5 hrs a week · approvals waiting 3 days · Finance',
      },
    },
    // Three plain facts, each answering an objection an owner arrives with:
    // is this a big commitment, will my staff cope, what will it cost me.
    stats: [
      { value: '0 apps', label: 'Your team answers on WhatsApp, in their own words' },
      { value: 'Fixed fee', label: 'Priced on how many people take part, known before we begin' },
      { value: '3 stages', label: 'You decide after each one' },
    ],
    // The industry strip used to be its own section. It is one line of context,
    // so it belongs to the hero rather than to a band of its own.
    industriesLabel: 'Built for owner-led businesses in',
    industries: ['Trading & distribution', 'Manufacturing', 'Logistics', 'Construction', 'Professional services'],
  },

  // ── The most important section on the page. ────────────────────────────────
  // Not their industry — their texture. An owner should recognise their own
  // company here and immediately think: what else is happening that I cannot
  // see? That question is the product.
  problem: {
    eyebrow: 'The situation',
    title: 'Some of this is happening in your company this morning',
    subtitle:
      'Not a diagnosis of your industry. The small, specific things that quietly accumulate in every business that has been running a few years.',
    pains: [
      {
        title: 'The first forty minutes of every morning',
        description:
          'Someone opens two systems and copies figures between them. It has never been questioned, because it has always been part of the job.',
      },
      {
        title: 'The report nobody trusts',
        description:
          'The system produces one. Somebody rebuilds it by hand every week anyway, because two years ago the system’s version was wrong.',
      },
      {
        title: 'The approval that waits for one person',
        description:
          'Orders sit because the one person who signs them off is travelling. Nothing is broken. It is just slower than anyone has measured.',
      },
      {
        title: 'The ChatGPT nobody approved',
        description:
          'Someone has quietly started writing quotations with it. It works. Nobody has decided whether it is allowed, or who is accountable if it is wrong.',
      },
    ],
    // The turn. This is the line the whole section exists to earn.
    closing:
      'None of this is on anyone’s report. Nobody planned it. It accumulated. And it is almost certainly costing more than anything on your P&L calls it.',
  },

  // ── Outcomes in their language, not our stages. ────────────────────────────
  discover: {
    eyebrow: 'What you get',
    title: 'What you will know that you do not know now',
    subtitle:
      'At the end of the first stage you have a report written for you, not for your IT department.',
    cards: [
      {
        icon: 'clock' as DiscoverIcon,
        title: 'Where your time actually goes',
        description: 'Role by role, task by task, in hours — not impressions.',
      },
      {
        icon: 'coins' as DiscoverIcon,
        title: 'What it is costing you',
        description: 'Sized in hours and money, with the working shown so you can check it.',
      },
      {
        icon: 'wrench' as DiscoverIcon,
        title: 'What can be fixed, and what it returns',
        description: 'Named solutions against named problems, each carrying an effort and a return.',
      },
      {
        icon: 'ban' as DiscoverIcon,
        title: 'What is not worth doing',
        description: 'We will tell you that too, and why. Usually the most useful page in the report.',
      },
    ],
  },

  // ── One concrete case does more than every claim on the site. ──────────────
  // Mjadi has no clients yet, so this cannot be an anonymised real engagement
  // and must not pretend to be. It is labelled an illustration — which the
  // brief's own rule requires of every number here anyway. The counterpoint
  // matters more than the finding: recommending against a build is evidence of
  // judgement, and nobody expects it.
  workedExample: {
    eyebrow: 'An example',
    title: 'What a finding looks like',
    subtitle:
      'An illustration, not a client. This is the shape a finding takes: the detail, the sizing, and the recommendation against doing something.',
    company: 'A trading company, 40 staff. Procurement.',
    figures: [
      { value: '40 min', label: 'every morning re-keying supplier prices' },
      { value: '170 hrs', label: 'a year, on one task in one role' },
      { value: '150 hrs', label: 'released by the fix we recommended' },
    ],
    blocks: [
      {
        label: 'What we found',
        body: 'Supplier price lists arrive as spreadsheets in varying formats. The procurement officer re-keys them into the ERP item by item, checking variant codes by hand. Pricing errors on variants reach customers about twice a month.',
      },
      {
        label: 'What we recommended',
        body: 'A direct feed from the supplier sheets into the ERP, with a validation step that flags only the exceptions — new items, price movements beyond a threshold, unmatched codes.',
      },
    ],
    counterpoint: {
      label: 'And what we advised against',
      body: 'We also recommended against automating their quotation approval chain. The volume did not justify the build, and the delay came from one person’s availability, not from the process. Automating it would have bought them very little and cost them a project.',
    },
  },

  // ── The "I did not know that was possible" moment. ─────────────────────────
  // Framed as what companies are doing, never as a promise about what we will
  // build for this reader — we have not looked at their business yet.
  alwaysOn: {
    eyebrow: 'What is possible',
    title: 'Things companies like yours are already doing',
    subtitle: 'A sense of what is within reach once you know where the time is going.',
    items: [
      {
        badge: 'Procurement',
        title: 'An agent that watches the market',
        body: 'It checks supplier marketplaces each morning and tells one person what is new and what moved on price. Nobody has to remember to look.',
      },
      {
        badge: 'Sales & catalogue',
        title: 'Product copy for four thousand items',
        body: 'An entire catalogue written in one consistent voice — the job that has sat on somebody’s list for two years because it is too big to start.',
      },
      {
        badge: 'Operations',
        title: 'A system that reads your supplier email',
        body: 'It pulls out the commitments — dates, quantities, prices — and puts them where someone can act on them.',
      },
    ],
  },

  // ── The commercial model, which does real work here: it makes starting feel
  // small. Deliberately placed after the proof, not before it.
  howItWorks: {
    eyebrow: 'How we work',
    title: 'Three stages. You decide after each one.',
    subtitle:
      'Most of what we do is the first stage. Many companies act on that report themselves, and that is a perfectly good outcome.',
    steps: [
      {
        title: 'Diagnosis',
        description:
          'We study how the company works and show you where the money is going: what the work costs, what can be fixed, and what is not worth touching.',
        details: [
          'We learn how the work gets done, from the people doing it',
          'Everything we find is sized in hours and money',
        ],
      },
      {
        title: 'Solution design',
        description:
          'You choose what to take forward. We design those solutions in detail — what gets built, what it touches, what it costs, what it returns.',
        details: [
          'Only the items you pick',
          'Designed against your actual systems, and costed before anything is built',
        ],
      },
      {
        title: 'Implementation',
        description:
          'We build and deploy what you approve, and stay with it until it is genuinely in use rather than merely delivered.',
        details: [
          'Built, deployed and handed over working',
          'Your team trained on what changed',
        ],
      },
    ],
    closing: 'You decide what happens after each stage. Nothing commits you to the next one.',
    // The three load-bearing facts from what used to be a twelve-bullet
    // "platform" section. These are the ones an owner actually needs: what it
    // asks of their staff, what protects them, and who checks the work.
    facts: [
      {
        label: 'On WhatsApp',
        body: 'Your team answers in their own words — text, voice notes, a photo of a form. Nothing to install.',
      },
      {
        label: 'Invitation only',
        body: 'Consent is captured before anything is asked. Nobody is scored, rated or assessed.',
      },
      {
        label: 'Independently reviewed',
        body: 'An expert reviews the report section by section, and can go back to your team, before it reaches you.',
      },
    ],
  },

  // ── With a new firm, personal credibility carries the site. Who we are and
  // what we refuse to do are one act, so they share a section.
  whoWeAre: {
    eyebrow: 'Who we are',
    title: 'The people who would be doing this',
    subtitle:
      'Mjadi is new. So rather than a company story, here is who you would actually be working with.',
    founders: [
      {
        name: 'Masood Al Baskati',
        role: 'Co-founder',
        body: 'Spent decades running a real trading company — a thousand customers across the UAE, the GCC and Africa, with real staff, suppliers and margin pressure. He has run the kind of company Mjadi advises, which is a different thing from having consulted for one.',
      },
      {
        name: 'Usman Malik',
        role: 'Co-founder',
        // TODO(usman): replace with your own background before this goes live.
        // Left deliberately unwritten rather than invented — a fabricated bio is
        // exactly the kind of claim this site exists not to make.
        body: 'Builds the technology behind Mjadi — the discovery platform, the agents that run the interviews, and the analysis that turns them into a report.',
      },
    ],
    name: {
      label: 'The name',
      body: 'Mjadi is Emirati dialect for someone concentrating hard on a target — the goal in football, the bird in the sights. It is the state of aiming seriously at something, which is what we are asking a company to do.',
    },
    // Confidence as differentiation. A new firm can say this credibly; a large
    // one usually will not.
    stance: {
      label: 'Where we stand',
      items: [
        'We do not sell software. We have nothing to license you.',
        'We will tell you when the answer is not AI.',
        'We will tell you when a process should be removed rather than automated.',
        'We will tell you when something is not worth doing.',
      ],
    },
  },

  faq: {
    title: 'The questions we are usually asked',
    items: [
      {
        q: 'What does it cost?',
        a: 'The first stage is a fixed fee based on how many people take part. You will know the cost before anything begins, and it does not change as we go. There is no subscription and nothing to license.',
      },
      {
        q: 'How long does the first stage take?',
        a: 'Weeks rather than months, and most of that is your people answering when it suits them. There is no workshop to schedule and nobody sitting in your office.',
      },
      {
        q: 'What do you actually need from my team?',
        a: 'A conversation each, on WhatsApp or in a browser, in their own words. They answer when they have a moment. Nobody has to install anything or learn a system.',
      },
      {
        q: 'Will my staff think this is about cutting jobs?',
        a: 'It is a fair thing for them to wonder, so it is worth saying plainly to them: we are mapping tasks, systems and handoffs, not people. Nobody is rated, scored or assessed, and the report talks about time returned to better work — not headcount.',
      },
      {
        q: 'What if the answer is that we do not need AI?',
        a: 'Then that is what the report says. Some of what we find is a process that should be removed rather than automated, or a delay caused by one person’s availability that no software will fix. We would rather tell you that than sell you a build.',
      },
      {
        q: 'What happens to what my people tell you?',
        a: 'It is held against your company, used to produce your report, and seen by us and the independent expert who reviews it. Participation is invitation-only with consent captured first. Our Privacy page sets out retention and contact details.',
      },
      {
        q: 'You are a new firm. Why should we trust you with this?',
        a: 'We have no client list to point at, and inventing one would be the first sign not to trust us. What we can offer is a first stage that is fixed in price and scope, ends in a document you can judge on its own merits, and commits you to nothing further.',
      },
    ],
  },

  cta: {
    eyebrow: 'How to start',
    title: 'Start with a conversation',
    subtitle:
      'Tell us roughly what your company does and what you suspect is being wasted. If we are not the right thing for you, we will say so on that call rather than after an invoice.',
    button: 'Talk to us',
    note: 'The first stage is a fixed fee based on how many people take part. You will know the cost before anything begins.',
  },

  footer: {
    tagline: 'We show you where the time is going, and what to do about it.',
    links: [
      { label: 'The situation', href: '#situation' },
      { label: 'An example', href: '#example' },
      { label: 'How we work', href: '#how-it-works' },
      { label: 'Who we are', href: '#who-we-are' },
      { label: 'Sign up', href: '/company/signup' },
      { label: 'Become a consultant', href: '/consultant/apply' },
      { label: 'Privacy', href: '/privacy' },
    ],
    // Moved off the hero, where eleven-pixel legalese under the first thing a
    // visitor reads was working against the page. It still has to be said.
    disclaimer:
      'Mjadi is a new firm. Figures shown anywhere on this site are illustrations of the shape of a finding, not results from past clients.',
  },
} as const;

export type HeroChatMessage = (typeof marketingContent.hero.chat.messages)[number];
