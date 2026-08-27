export const WORKSPACE_STEPS = [
  { id: 'context', label: 'Context', description: 'Engagement overview' },
  { id: 'evidence', label: 'Source evidence', description: 'Profiles & transcript' },
  { id: 'synthesis', label: 'Agent synthesis', description: 'What the agent concluded' },
  { id: 'sections', label: 'Report sections', description: 'Judge each conclusion' },
  { id: 'collaborate', label: 'Collaborate', description: 'Co-consultant alignment' },
  { id: 'submit', label: 'Submit', description: 'Final handoff' },
] as const;

export type WorkspaceStepId = (typeof WORKSPACE_STEPS)[number]['id'];

export const REPORT_SECTIONS = [
  'executive_summary',
  'readiness',
  'participation',
  'delta',
  'signals',
  'patterns',
  'recommendations',
] as const;

export type ReportSectionKey = (typeof REPORT_SECTIONS)[number];

export const SECTION_STATUS_OPTIONS = [
  { value: 'pending', label: 'Not judged yet' },
  // Values are persisted (report_review_section_states.status) and the platform
  // approval gate reads "needs_info" — only the labels change here.
  { value: 'approved', label: 'Stands as written' },
  { value: 'needs_info', label: 'Not settled — needs more' },
] as const;

export function parseWorkspaceStep(value: string | null): WorkspaceStepId {
  const match = WORKSPACE_STEPS.find((s) => s.id === value);
  return match?.id ?? 'context';
}

export function parseReportSection(value: string | null): ReportSectionKey {
  const match = REPORT_SECTIONS.find((s) => s === value);
  return match ?? 'executive_summary';
}
