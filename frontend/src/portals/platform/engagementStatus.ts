import type { EngagementStatus, PrefillStatus } from '../../lib/api';

/** How each engagement stage reads to Mjadi staff. */
export const ENGAGEMENT_STATUS_LABELS: Record<EngagementStatus, string> = {
  SET_UP: 'Invited',
  ONBOARDING: 'Onboarding',
  KEY_PERSON_DISCOVERY: 'Leadership conversation',
  STAGE_1_PRICING: 'Preparing Stage 1 proposal',
  STAGE_1_ACTIVE: 'Stage 1 in progress',
  CLOSED: 'Closed',
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
