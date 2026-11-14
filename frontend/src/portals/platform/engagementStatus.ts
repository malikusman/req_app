import type { EngagementStatus, PrefillStatus, Stage1QuoteStatus } from '../../lib/api';

/** How each engagement stage reads to Mjadi staff. */
export const ENGAGEMENT_STATUS_LABELS: Record<EngagementStatus, string> = {
  SET_UP: 'Invited',
  ONBOARDING: 'Onboarding',
  KEY_PERSON_DISCOVERY: 'Leadership conversation',
  STAGE_1_PRICING: 'Preparing Stage 1 proposal',
  STAGE_1_ACTIVE: 'Stage 1 in progress',
  CLOSED: 'Closed',
};

/** The label for a status, or the status itself if the server knows one this build doesn't. */
export function engagementStatusLabel(status: string | null | undefined): string {
  if (!status) return '—';
  return ENGAGEMENT_STATUS_LABELS[status as EngagementStatus] ?? status;
}

/** Where a Stage 1 quote stands, as Mjadi staff read it (Doc 06 §10.10). */
export const QUOTE_STATUS_LABELS: Record<Stage1QuoteStatus, string> = {
  PROPOSED: 'Waiting for approval',
  ISSUED: 'With the client',
  ACCEPTED: 'Accepted',
  DECLINED: 'Declined',
  EXPIRED: 'Expired',
  REJECTED: 'Sent back',
  SUPERSEDED: 'Replaced',
};

export const QUOTE_STATUS_VARIANTS: Record<Stage1QuoteStatus, 'success' | 'warning' | 'error' | 'info' | 'neutral'> = {
  PROPOSED: 'warning',
  ISSUED: 'info',
  ACCEPTED: 'success',
  DECLINED: 'error',
  EXPIRED: 'neutral',
  REJECTED: 'error',
  SUPERSEDED: 'neutral',
};

/** Where reading the client's website for onboarding proposals has got to. */
export const PREFILL_STATUS_LABELS: Record<PrefillStatus, string> = {
  not_started: 'Not read',
  pending: 'Reading…',
  running: 'Reading…',
  done: 'Read',
  empty: 'Nothing usable found',
  failed: "Couldn't be read",
};
