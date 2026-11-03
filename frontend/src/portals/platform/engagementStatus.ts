import type { EngagementStatus } from '../../lib/api';

/** How each engagement stage reads to Mjadi staff. */
export const ENGAGEMENT_STATUS_LABELS: Record<EngagementStatus, string> = {
  SET_UP: 'Invited',
  ONBOARDING: 'Onboarding',
  KEY_PERSON_DISCOVERY: 'Leadership conversation',
  STAGE_1_ACTIVE: 'Stage 1 in progress',
  CLOSED: 'Closed',
};
