import type { CompanyDashboardPayload } from '../../lib/api';

export type DashboardActionId =
  | 'get-started'
  | 'review-report'
  | 'answer-questions'
  | 'nudge-stalled'
  | 'add-profile'
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
  reviewerName?: string | null;
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
  const { reviewerName, unansweredQuestions, signalCount, patternCount, recommendationCount, readinessScore } =
    extras;
  const invited = payload.company.invited_count ?? 0;
  const completed = payload.company.completed_count ?? 0;
  const totalDocs = payload.intel_counts?.total_documents ?? 0;
  const stalled = payload.employees_summary.stalled_count ?? 0;
  const qPercent = Math.round(payload.questionnaire_completion_percent ?? 0);
  const report = payload.latest_report;
  const reportReady = Boolean(report && (report.status === 'ready' || report.status === 'shared'));
  const reviewer = reviewerName || 'your reviewer';

  const candidates: DashboardAction[] = [];

  // (a) Nothing started yet
  if (invited === 0 && totalDocs === 0) {
    candidates.push({
      id: 'get-started',
      eyebrow: 'Get started',
      title: 'Add documents or invite your team',
      description:
        'Discovery starts with evidence. Upload internal documents or invite a few teammates and insights begin to surface.',
      primaryLabel: 'Add documents',
      to: '/company/documents',
      tone: 'attention',
      attnTitle: 'Invite your team',
      attnDetail: 'Kick off employee discovery interviews',
      attnActionLabel: 'Invite',
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
          reviewerName ? ` — reviewed by your expert, ${reviewerName}.` : '.'
        }`
      : `Version ${report.version} of your discovery report is ready${
          reviewerName ? ` — reviewed by your expert, ${reviewerName}.` : '.'
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

  // (c) Reviewer questions waiting
  if (unansweredQuestions > 0) {
    candidates.push({
      id: 'answer-questions',
      eyebrow: 'Do this next',
      title: `Answer ${unansweredQuestions} question${unansweredQuestions === 1 ? '' : 's'} from ${reviewer}`,
      description: `A few details will sharpen your report. It takes about ${Math.max(
        1,
        unansweredQuestions * 2
      )} minutes.`,
      primaryLabel: 'Answer questions',
      to: '/company/outreaches',
      tone: 'attention',
      attnTitle: `Answer ${unansweredQuestions} question${unansweredQuestions === 1 ? '' : 's'} from ${reviewer}`,
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

  // (e) Incomplete profile (optional)
  if (qPercent < 100) {
    candidates.push({
      id: 'add-profile',
      eyebrow: 'Optional next step',
      title: 'Add your company profile',
      description: 'Industry, systems and goals sharpen every insight we produce. It takes about 2 minutes.',
      primaryLabel: 'Add profile',
      to: '/company/onboarding',
      tone: 'neutral',
      attnTitle: 'Add your company profile',
      attnDetail: `Sharpens every future insight · ${qPercent}% done`,
      optionalLabel: 'Optional',
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
