export type SelectionRun = { id: number; version: number; evaluation_mode: string };

export type EffortRange = { min?: number; max?: number; unit?: string };
export type AnnualWorkload = { status: string; annual_hours_min?: number; annual_hours_max?: number };
export type TaskSource = {
  id: number; employee_id: number; conversation_id: number; name: string; version: number; finding_id?: number;
  effort_observations: (AnnualWorkload & {
    scope: string; effort_type: string; frequency: EffortRange; duration: EffortRange; calculation_reason?: string;
  })[];
};
type Clarification = { id: number; status: string; missing_evidence: string[]; why_it_matters: string[]; unknowns: string[] };
export type Relationship = {
  source_ids: number[]; classification?: string; kind?: string; rationale?: string;
  missing_evidence?: string[];
  clarification_request?: Clarification | null;
  current_clarification_request?: Clarification | null;
};
export type Proposal = {
  id: number; title: string; rank: number | null; score: number; priority: string; confidence: string;
  disposition: string; disposition_reason: string; process_cluster_revision_number: number; source_ids: number[];
  assessment: {
    risks: string[]; unknowns: string[]; deep_dive_objectives: string[]; observed_workload?: AnnualWorkload;
    possible_released_effort?: { annual_hours_upper_bound: number; basis: string };
    evidence_sources: { task_source_id: number; reported_fields: string[]; conflicting_fields: string[] }[];
    potential_overlap_cluster_ids: number[];
  };
};
export type ReviewTask = {
  id: string; title: string; status: string; source_ids: number[]; proposal_ids: number[]; origin_task_ids: string[];
  notes: string[]; decision_reason?: string; replacement_reason?: string; participant_reason?: string;
  participant_ids: number[]; gaps: string[]; effective_effort: AnnualWorkload;
  effort_assumptions: Record<string, {
    effort_type: string; reason: string; frequency?: EffortRange; duration?: EffortRange; calculation_reason?: string;
  }>;
};
export type ReviewParticipant = { id: number; name: string | null; discovery_consent_recorded: boolean };
export type SelectionReview = {
  run: SelectionRun; version: number; latest_version: number; status: string; latest_status: string;
  history: { version: number; action: string; reason: string; status: string; consultant_user_id: number; created_at: string }[];
  proposals: Proposal[]; sources: TaskSource[]; relationships: Relationship[]; eligible_participants: ReviewParticipant[];
  snapshot: {
    tasks: ReviewTask[]; selected_order: string[];
    sampling: { planned_interviews: number; available_slots: number | null; gaps: string[] };
    relationship_overrides: Record<string, { source_ids: number[]; classification: string; reason: string }>;
    final_selection?: { provisional: boolean };
  };
};
export type ReviewCommand = {
  action: string; task_id?: string; task_ids?: string[]; source_id?: number; source_ids?: number[];
  title?: string; children?: { title: string; source_ids: number[] }[]; participant_ids?: number[];
  classification?: string; slots?: number | null; effort_type?: string; frequency?: EffortRange; duration?: EffortRange;
};
