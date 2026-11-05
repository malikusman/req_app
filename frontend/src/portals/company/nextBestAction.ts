import type { CompanyDashboardPayload } from '../../lib/api';

export type DashboardActionId =
  | 'get-started'
  | 'review-report'
  | 'answer-questions'
  | 'nudge-stalled'
  | 'add-profile'
  | 'participant-counts'
  | 'leadership'
  | 'pricing'
  | 'running';

export interface DashboardAction {
  id: DashboardActionId;
  /** Hero form */
  eyebrow: string;
  title: string;
  description: string;
  primaryLabel: string;
  to: string;
  readiness?: { percent: number; label?: string };
  /** Attention-row form */
  tone: 'attention' | 'neutral';
  attnTitle: string;
  attnDetail?: string;
  attnActionLabel?: string;
  optionalLabel?: string;
}

export interface NextBestExtras {
  consultantName?: string | null;
  unansweredQuestions: number;
  signalCount: number;
  patternCount: number;
  recommendationCount: number;
  readinessScore: number;
}

/**
 * Pure ranking of what a company admin should do next, from data already fetched.
 * The first matching candidate becomes the hero; the rest become attention rows.
 */
export function nextBestAction(
  payload: CompanyDashboardPayload,
  extras: NextBestExtras
): { hero: DashboardAction; also: DashboardAction[] } {
  const { consultantName, unansweredQuestions, signalCount, patternCount, recommendationCount, readinessScore } =
    extras;
  const invited = payload.company.invited_count ?? 0;
  const completed = payload.company.completed_count ?? 0;
  const totalDocs = payload.intel_counts?.total_documents ?? 0;
  const stalled = payload.employees_summary.stalled_count ?? 0;
  const profileSubmitted = Boolean(payload.onboarding_submitted_at);
  const status = payload.engagement_status ?? null;
  // Counts may be left "Not sure" at onboarding; they are needed before the fee is agreed.
  const countsNeeded = status === 'KEY_PERSON_DISCOVERY' && payload.planned_participant_count == null;
  const leadership = payload.leadership ?? null;
  const ownConversation = leadership?.is_key_user ? leadership.own : null;
  // Staff are invited once the Stage 1 fee is agreed, never during the leadership
  // stage or pricing; companies from before engagements carry on as they were.
  const teamStage = status == null || status === 'STAGE_1_ACTIVE';
  const report = payload.latest_report;
  const reportReady = Boolean(report && (report.status === 'ready' || report.status === 'shared'));
  const consultant = consultantName || 'your consultant';

  const candidates: DashboardAction[] = [];

  // (0) The conversation with leadership, then the proposal (Doc 08, Doc 17 §1)
  if (status === 'KEY_PERSON_DISCOVERY' && ownConversation && !ownConversation.finished) {
    const started = ownConversation.participation_status === 'STARTED' || ownConversation.participation_status === 'PAUSED';
    candidates.push(
      leadership?.available || started
        ? {
            id: 'leadership',
            eyebrow: started ? 'Carry on' : 'Do this next',
            title: started ? 'Pick up your conversation with Mjadi' : 'Your conversation with Mjadi',
            description:
              'About fifteen to twenty minutes on where you’re taking the business and what gets in the way. Type or send voice notes, and pause whenever you need.',
            primaryLabel: started ? 'Carry on' : 'Start the conversation',
            to: '/company/leadership',
            tone: 'attention',
            attnTitle: 'Your conversation with Mjadi',
            attnDetail: 'About fifteen to twenty minutes',
            attnActionLabel: started ? 'Carry on' : 'Start',
          }
        : {
            id: 'leadership',
            eyebrow: 'Next step',
            title: 'A conversation about where you’re taking the business',
            description: 'The Mjadi team will be in touch to arrange it.',
            primaryLabel: 'Your consultant',
            to: '/company/consultants',
            tone: 'neutral',
            attnTitle: 'Leadership conversation',
            attnDetail: 'The Mjadi team will be in touch to arrange it',
          }
    );
  }
  if (status === 'STAGE_1_PRICING') {
    candidates.push({
      id: 'pricing',
      eyebrow: 'In progress',
      title: 'We’re preparing your Stage 1 proposal',
      description:
        'Thank you for the conversation. Your consultant is putting together the scope and fee for the first stage, and will be in touch.',
      primaryLabel: 'Your consultant',
      to: '/company/consultants',
      tone: 'neutral',
      attnTitle: 'Stage 1 proposal in preparation',
      attnDetail: 'Your consultant will be in touch',
    });
  }

  // (a) Nothing started yet
  if (teamStage && invited === 0 && totalDocs === 0) {
    candidates.push({
      id: 'get-started',
      eyebrow: 'Get started',
      title: 'Add documents or invite your team',
      description:
        'Discovery starts with evidence. Upload internal documents or invite a few teammates and insights begin to surface.',
      primaryLabel: 'Add documents',
      to: '/company/documents',
      tone: 'attention',
      attnTitle: 'Add documents or invite your team',
      attnDetail: 'Discovery starts with evidence',
      attnActionLabel: 'Start',
    });
  }

  // (b) Report ready to review
  if (reportReady && report) {
    const parts: string[] = [];
    if (signalCount > 0) parts.push(`${signalCount} friction${signalCount === 1 ? '' : 's'}`);
    if (patternCount > 0) parts.push(`${patternCount} cross-team theme${patternCount === 1 ? '' : 's'}`);
    if (recommendationCount > 0)
      parts.push(`${recommendationCount} tailored recommendation${recommendationCount === 1 ? '' : 's'}`);
    const summary = parts.length
      ? `Version ${report.version} pulls together ${joinList(parts)}${
          consultantName ? ` — reviewed by your expert, ${consultantName}.` : '.'
        }`
      : `Version ${report.version} of your discovery report is ready${
          consultantName ? ` — reviewed by your expert, ${consultantName}.` : '.'
        }`;
    candidates.push({
      id: 'review-report',
      eyebrow: 'Do this next',
      title: 'Your discovery report is ready to review',
      description: summary,
      primaryLabel: 'Open report',
      to: '/company/reports',
      readiness: { percent: readinessScore, label: 'Ready' },
      tone: 'neutral',
      attnTitle: `Discovery report v${report.version} is ready`,
      attnDetail: 'See what we found for your company',
      attnActionLabel: 'Open',
    });
  }

  // (c) Consultant questions waiting
  if (unansweredQuestions > 0) {
    candidates.push({
      id: 'answer-questions',
      eyebrow: 'Do this next',
      title: `Answer ${unansweredQuestions} question${unansweredQuestions === 1 ? '' : 's'} from ${consultant}`,
      description: `A few details will sharpen your report. It takes about ${Math.max(
        1,
        unansweredQuestions * 2
      )} minutes.`,
      primaryLabel: 'Answer questions',
      to: '/company/outreaches',
      tone: 'attention',
      attnTitle: `Answer ${unansweredQuestions} question${unansweredQuestions === 1 ? '' : 's'} from ${consultant}`,
      attnDetail: 'A few details will sharpen your report',
      attnActionLabel: 'Answer',
    });
  }

  // (d) Stalled teammates
  if (stalled > 0) {
    candidates.push({
      id: 'nudge-stalled',
      eyebrow: 'Needs a nudge',
      title: `Nudge ${stalled} teammate${stalled === 1 ? '' : 's'} who stalled`,
      description: `${stalled} invited teammate${
        stalled === 1 ? ' has' : 's have'
      } paused mid-discovery. A quick reminder helps them finish.`,
      primaryLabel: 'Nudge teammates',
      to: '/company/employees',
      tone: 'attention',
      attnTitle: `Nudge ${stalled} stalled teammate${stalled === 1 ? '' : 's'}`,
      attnDetail: 'They paused mid-discovery',
      attnActionLabel: 'Nudge',
    });
  }

  // (e) Company profile not submitted yet
  if (!profileSubmitted) {
    candidates.push({
      id: 'add-profile',
      eyebrow: 'Next step',
      title: 'Finish your company profile',
      description: 'A few facts about the company and who should take part. It takes about five minutes.',
      primaryLabel: 'Finish profile',
      to: '/company/onboarding',
      tone: 'attention',
      attnTitle: 'Finish your company profile',
      attnDetail: 'About five minutes',
    });
  } else if (countsNeeded) {
    candidates.push({
      id: 'participant-counts',
      eyebrow: 'Before we agree the fee',
      title: 'How many people will take part?',
      description:
        'Some departments are still marked “Not sure”. We need a number for each before we can agree the fee — a rough one is fine.',
      primaryLabel: 'Add the numbers',
      to: ownConversation ? '/company/leadership' : '/company/onboarding',
      tone: 'attention',
      attnTitle: 'Participant numbers needed',
      attnDetail: 'Needed before the fee is agreed',
    });
  }

  const fallback: DashboardAction = {
    id: 'running',
    eyebrow: 'In progress',
    title: "Discovery is running",
    description: "We'll surface frictions, themes and recommendations here as they land. Nothing needs you right now.",
    primaryLabel: 'See what we found',
    to: '/company/intelligence',
    readiness: readinessScore > 0 ? { percent: readinessScore, label: 'Ready' } : undefined,
    tone: 'neutral',
    attnTitle: 'Discovery in progress',
    attnDetail: "We'll notify you when there's something to review",
    optionalLabel: 'Waiting',
  };

  // Keep completed context available for callers without unused-var noise.
  void completed;

  const hero = candidates[0] ?? fallback;
  const also = candidates.slice(1, 3);
  return { hero, also };
}

function joinList(parts: string[]): string {
  if (parts.length === 1) return parts[0];
  if (parts.length === 2) return `${parts[0]} and ${parts[1]}`;
  return `${parts.slice(0, -1).join(', ')}, and ${parts[parts.length - 1]}`;
}
