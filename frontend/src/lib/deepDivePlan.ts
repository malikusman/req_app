export type PlanStatus = 'not_started' | 'queued' | 'generating' | 'failed' | 'draft' | 'approved';

export type PlanSummary = { task_id: string; title: string; status: PlanStatus; retry_available: boolean };

export type PlanQuestion = { text: string; source_ids: number[]; clarification_ids: number[] };

export type PlanContent = {
  objective: string; scope: string; instructions: string; duration_minutes: number;
  focus_areas: string[]; document_requests: string[];
  sections: { title: string; questions: PlanQuestion[] }[];
};

export type PlanContext = {
  selection_version: number;
  cluster_revision_ids: number[];
  participants: { id: number; display_name?: string; role_title?: string; department?: string; eligible: boolean; discovery_consent_recorded: boolean }[];
  sources: {
    id: number; name: string; version: number; employee_id: number; conversation_id: number; finding_id?: number;
    facts: { field: string; reported_value: string; reference: { message_id?: number; turn?: number } }[];
    effort_observations: {
      scope: string; effort_type: string; frequency: { min?: number; max?: number; unit?: string };
      duration: { min?: number; max?: number; unit?: string };
    }[];
  }[];
  open_clarifications: { id: number; missing_evidence: string[]; why_it_matters: string[]; source_ids: number[] }[];
  relationships: { source_ids: number[]; kind: string; rationale: string }[];
  relationship_judgments: { source_ids: number[]; classification: string; reason: string }[];
  effort: { effective_effort?: { status: string; annual_hours_min?: number; annual_hours_max?: number }; effort_assumptions?: Record<string, { reason: string; effort_type: string }> };
  gaps: string[];
};

export type PlanDetail = PlanSummary & {
  version: number | null; latest_version: number | null; approved_version: number | null;
  context: PlanContext | null; content: PlanContent | null; generation_error: string | null;
  history: { version: number; action: string; reason: string; consultant_user_id: number; created_at: string }[];
};
