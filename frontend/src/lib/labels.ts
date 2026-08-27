/**
 * Human-facing labels for backend enums. Machine states (snake_case) must never
 * reach users — map the ones we display, and humanize() anything unmapped so an
 * unknown value still reads as words, not code.
 */
export function humanize(value?: string | null): string {
  if (!value) return '—';
  return value.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}

const MAPS = {
  reportStatus: {
    queued: 'Preparing…',
    generating: 'Generating…',
    ready: 'Ready',
    failed: 'Failed',
  },
  reviewWorkflow: {
    not_required: 'No review needed',
    awaiting_consultants: 'Awaiting consultants',
    in_review: 'In review',
    reviews_complete: 'Ready to approve',
    platform_approved: 'Approved',
  },
  reviewStatus: {
    pending: 'Not started',
    in_review: 'In review',
    needs_info: 'Needs clarification',
    approved: 'Reviewed',
  },
  participation: {
    invited: 'Invited',
    started: 'In progress',
    completed: 'Completed',
    declined: 'Declined',
  },
  onboardingStep: {
    awaiting_name: 'Awaiting name',
    awaiting_company: 'Awaiting company',
    awaiting_consent: 'Awaiting consent',
    verified: 'Verified',
  },
  outreachStatus: {
    draft: 'Draft',
    pending_admin_approval: 'Waiting on you',
    approved: 'Approved',
    declined: 'Declined',
    queued: 'Queued',
    sent: 'Sent',
    replied: 'Replied',
    closed: 'Closed',
    failed: 'Failed',
  },
  priority: {
    low: 'Low',
    medium: 'Medium',
    high: 'High',
  },
  conversationStatus: {
    onboarding: 'Onboarding',
    profiling: 'Getting set up',
    discovery: 'In interview',
    completed: 'Completed',
    abandoned: 'Stalled',
  },
} as const;

export type LabelKind = keyof typeof MAPS;

export function label(kind: LabelKind, value?: string | null): string {
  if (!value) return '—';
  const map = MAPS[kind] as Record<string, string>;
  return map[value] ?? humanize(value);
}
