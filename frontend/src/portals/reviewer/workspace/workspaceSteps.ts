export const WORKSPACE_STEPS = [
  { id: 'context', label: 'Context', description: 'Engagement overview' },
  { id: 'evidence', label: 'Source evidence', description: 'Profiles & transcript' },
  { id: 'synthesis', label: 'Agent synthesis', description: 'Findings & reasoning' },
  { id: 'sections', label: 'Report sections', description: 'Validate deliverable' },
  { id: 'collaborate', label: 'Collaborate', description: 'Co-reviewer alignment' },
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
  { value: 'pending', label: 'Not started' },
  { value: 'approved', label: 'Reviewed' },
  { value: 'needs_info', label: 'Needs clarification' },
] as const;

export function parseWorkspaceStep(value: string | null): WorkspaceStepId {
  const match = WORKSPACE_STEPS.find((s) => s.id === value);
  return match?.id ?? 'context';
}

export function parseReportSection(value: string | null): ReportSectionKey {
  const match = REPORT_SECTIONS.find((s) => s === value);
  return match ?? 'executive_summary';
}
