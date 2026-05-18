const API_URL = import.meta.env.VITE_API_URL || '';

export type ApiError = { error?: string; errors?: string[] };

async function request<T>(
  path: string,
  options: RequestInit = {},
  token?: string | null
): Promise<T> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
    ...(options.headers as Record<string, string>),
  };
  if (token) headers['Authorization'] = `Bearer ${token}`;

  const res = await fetch(`${API_URL}${path}`, { ...options, headers });
  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    const err = (data as ApiError).error || (data as ApiError).errors?.join(', ') || res.statusText;
    throw new Error(err);
  }
  return data as T;
}

export const api = {
  platformLogin: (email: string, password: string) =>
    request<{ token: string; user: { id: number; email: string; name: string; role: string } }>(
      '/api/v1/auth/platform/login',
      { method: 'POST', body: JSON.stringify({ email, password }) }
    ),

  reviewerLogin: (email: string, password: string) =>
    request<{ token: string; user: { id: number; email: string; name: string } }>(
      '/api/v1/auth/reviewer/login',
      { method: 'POST', body: JSON.stringify({ email, password }) }
    ),

  companyLogin: (email: string, password: string) =>
    request<{
      token: string;
      user: { id: number; email: string; name: string; role: string; onboarding_completed_at: string | null };
      company: {
        id: number;
        name: string;
        display_name: string | null;
        locale: string;
        portal_onboarding_completed_at: string | null;
      };
    }>('/api/v1/auth/company/login', { method: 'POST', body: JSON.stringify({ email, password }) }),

  platformCompanies: (token: string) =>
    request<{ companies: Company[] }>('/api/v1/platform/companies', {}, token),

  createPlatformCompany: (
    token: string,
    payload: { name: string; display_name?: string; company_admin: { email: string; name: string; password: string } }
  ) =>
    request<{ company: Company }>(
      '/api/v1/platform/companies',
      { method: 'POST', body: JSON.stringify({ company: { name: payload.name, display_name: payload.display_name }, company_admin: payload.company_admin }) },
      token
    ),

  companyMe: (token: string) =>
    request<{ user: CompanyUser; company: CompanyDetail }>('/api/v1/company/me', {}, token),

  companyOnboarding: (token: string) =>
    request<{ step: number; company: { display_name: string; locale: string }; invited_count: number }>(
      '/api/v1/company/onboarding',
      {},
      token
    ),

  updateOnboardingProfile: (token: string, display_name: string, locale: string) =>
    request<{ ok: boolean; step: number }>(
      '/api/v1/company/onboarding/profile',
      { method: 'PATCH', body: JSON.stringify({ display_name, locale }) },
      token
    ),

  completeOnboarding: (token: string) =>
    request<{ ok: boolean }>('/api/v1/company/onboarding/complete', { method: 'POST' }, token),

  companyEmployees: (token: string) =>
    request<{ employees: Employee[] }>('/api/v1/company/employees', {}, token),

  inviteEmployee: (token: string, phone_e164: string, display_name?: string, department?: string) =>
    request<{ employee: Employee; access_code: string }>(
      '/api/v1/company/employees',
      { method: 'POST', body: JSON.stringify({ phone_e164, display_name, department }) },
      token
    ),

  bulkInviteEmployees: (token: string, employees: { phone_e164: string; display_name?: string; department?: string }[]) =>
    request<{ employees: (Employee & { access_code: string })[] }>(
      '/api/v1/company/employees/bulk_create',
      { method: 'POST', body: JSON.stringify({ employees }) },
      token
    ),

  nudgeEmployee: (token: string, employeeId: number) =>
    request<{ ok: boolean; message: string }>(
      `/api/v1/company/employees/${employeeId}/nudge`,
      { method: 'POST' },
      token
    ),

  platformPlaybooks: (token: string) =>
    request<{ playbooks: Playbook[] }>('/api/v1/platform/playbooks', {}, token),

  createPlaybook: (
    token: string,
    payload: { department: string; prompt_block: string; notes?: string }
  ) =>
    request<{ playbook: Playbook }>(
      '/api/v1/platform/playbooks',
      { method: 'POST', body: JSON.stringify({ playbook: payload }) },
      token
    ),

  activatePlaybook: (token: string, id: number) =>
    request<{ playbook: Playbook }>(`/api/v1/platform/playbooks/${id}/activate`, { method: 'POST' }, token),

  companyDocuments: (token: string) =>
    request<{ documents: CompanyDocument[] }>('/api/v1/company/documents', {}, token),

  uploadDocument: async (token: string, file: File, department?: string) => {
    const form = new FormData();
    form.append('file', file);
    if (department) form.append('department', department);

    const res = await fetch(`${API_URL}/api/v1/company/documents`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: form,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error((data as ApiError).error || res.statusText);
    return data as { document: CompanyDocument };
  },

  intelligenceSnapshot: (token: string) =>
    request<{ snapshot: IntelligenceSnapshot; report_readiness_score: number; report_readiness_breakdown: Record<string, number> }>(
      '/api/v1/company/intelligence/snapshot',
      {},
      token
    ),

  intelligenceTimeline: (token: string) =>
    request<{ events: TimelineEvent[] }>('/api/v1/company/intelligence/timeline', {}, token),

  discoveryQuestions: (token: string) =>
    request<{ questions: DiscoveryQuestion[] }>('/api/v1/company/discovery_questions', {}, token),

  discoveryQuestionFeedback: (token: string, messageId: number, feedback: string, note?: string) =>
    request<{ feedback: { message_id: number; feedback: string; note?: string } }>(
      `/api/v1/company/discovery_questions/${messageId}/feedback`,
      { method: 'POST', body: JSON.stringify({ feedback, note }) },
      token
    ),

  companyRecommendations: (token: string) =>
    request<{ recommendations: Recommendation[] }>('/api/v1/company/recommendations', {}, token),

  recommendationFeedback: (token: string, id: number, feedback: string, note?: string) =>
    request<{ recommendation: Recommendation }>(
      `/api/v1/company/recommendations/${id}/feedback`,
      { method: 'PATCH', body: JSON.stringify({ feedback, note }) },
      token
    ),

  updateEmployeePhone: (token: string, employeeId: number, phone_e164: string) =>
    request<{ employee: Employee; access_code: string }>(
      `/api/v1/company/employees/${employeeId}/phone`,
      { method: 'PATCH', body: JSON.stringify({ phone_e164 }) },
      token
    ),

  platformSolutions: (token: string) =>
    request<{ solutions: SolutionCatalogEntry[] }>('/api/v1/platform/solutions', {}, token),

  createSolution: (token: string, payload: Partial<SolutionCatalogEntry>) =>
    request<{ solution: SolutionCatalogEntry }>(
      '/api/v1/platform/solutions',
      { method: 'POST', body: JSON.stringify({ solution: payload }) },
      token
    ),

  updateSolution: (token: string, id: number, payload: Partial<SolutionCatalogEntry>) =>
    request<{ solution: SolutionCatalogEntry }>(
      `/api/v1/platform/solutions/${id}`,
      { method: 'PATCH', body: JSON.stringify({ solution: payload }) },
      token
    ),

  companyReports: (token: string) => request<{ reports: Report[] }>('/api/v1/company/reports', {}, token),

  generateReport: (token: string) =>
    request<{ report: Report }>('/api/v1/company/reports', { method: 'POST' }, token),

  shareReport: (token: string, id: number, days: number) =>
    request<{ share_token: string; share_url: string; expires_at: string }>(
      `/api/v1/company/reports/${id}/share`,
      { method: 'POST', body: JSON.stringify({ days }) },
      token
    ),

  downloadReport: async (token: string, id: number) => {
    const res = await fetch(`${API_URL}/api/v1/company/reports/${id}/download`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) throw new Error('Download failed');
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `discovery-report-${id}.pdf`;
    a.click();
    URL.revokeObjectURL(url);
  },

  platformSystem: (token: string) => request<PlatformSystemHealth>('/api/v1/platform/system', {}, token),

  companySettingsOrganization: (token: string) =>
    request<{ settings: Record<string, unknown>; company: { display_name: string; locale: string } }>(
      '/api/v1/company/settings/organization',
      {},
      token
    ),

  updateCompanySettings: (token: string, payload: { display_name?: string; locale?: string; department_targets?: Record<string, number> }) =>
    request<{ ok: boolean }>('/api/v1/company/settings/organization', { method: 'PATCH', body: JSON.stringify(payload) }, token),

  companySettingsSecurity: (token: string) =>
    request<{ security_snapshot: Record<string, unknown>; active_access_codes: number; pin_rotated_at: string | null }>(
      '/api/v1/company/settings/security',
      {},
      token
    ),

  rotateAccessCodes: (token: string) =>
    request<{ ok: boolean; codes_rotated: number }>('/api/v1/company/settings/security/rotate_codes', { method: 'POST' }, token),

  companyNotifications: (token: string, page = 1) =>
    request<{ notifications: AppNotification[]; unread_count: number; page: number; per_page: number }>(
      `/api/v1/company/notifications?page=${page}`,
      {},
      token
    ),

  markNotificationRead: (token: string, id: number) =>
    request<{ notification: AppNotification }>(`/api/v1/company/notifications/${id}`, { method: 'PATCH' }, token),

  markAllNotificationsRead: (token: string) =>
    request<{ ok: boolean; unread_count: number }>('/api/v1/company/notifications/mark_all_read', { method: 'POST' }, token),

  companyBilling: (token: string) => request<BillingSnapshot>('/api/v1/company/billing', {}, token),

  startBillingCheckout: (token: string, plan: string) =>
    request<{ checkout_url: string; mock: boolean }>('/api/v1/company/billing/checkout', { method: 'POST', body: JSON.stringify({ plan }) }, token),

  impersonateCompany: (token: string, companyId: number) =>
    request<ImpersonationResponse>(`/api/v1/platform/companies/${companyId}/impersonate`, { method: 'POST' }, token),

  platformMonitoring: (token: string) => request<PlatformMonitoring>('/api/v1/platform/monitoring', {}, token),

  platformReviewers: (token: string) => request<{ reviewers: ReviewerUser[] }>('/api/v1/platform/reviewers', {}, token),

  createPlatformReviewer: (token: string, payload: { email: string; name: string; password: string }) =>
    request<{ reviewer: ReviewerUser }>('/api/v1/platform/reviewers', { method: 'POST', body: JSON.stringify({ reviewer: payload }) }, token),

  companyReviewerAssignments: (token: string, companyId: number) =>
    request<{ assignments: ReviewerAssignment[]; active_count: number }>(
      `/api/v1/platform/companies/${companyId}/reviewer_assignments`,
      {},
      token
    ),

  assignReviewer: (token: string, companyId: number, reviewerUserId: number) =>
    request<{ assignment: ReviewerAssignment }>(
      `/api/v1/platform/companies/${companyId}/reviewer_assignments`,
      { method: 'POST', body: JSON.stringify({ reviewer_user_id: reviewerUserId }) },
      token
    ),

  removeReviewerAssignment: (token: string, companyId: number, assignmentId: number) =>
    request<void>(`/api/v1/platform/companies/${companyId}/reviewer_assignments/${assignmentId}`, { method: 'DELETE' }, token),

  reviewerMe: (token: string) => request<{ user: { id: number; email: string; name: string }; assignments: { company_id: number; company_name: string }[] }>('/api/v1/reviewer/me', {}, token),

  reviewerCompanies: (token: string) => request<{ companies: ReviewerCompanySummary[] }>('/api/v1/reviewer/companies', {}, token),

  reviewerCompany: (token: string, id: number) => request<{ company: ReviewerCompanyDetail }>(`/api/v1/reviewer/companies/${id}`, {}, token),

  reviewerReport: (token: string, companyId: number, reportId: number) =>
    request<{ report: ReviewerReportDetail }>(`/api/v1/reviewer/companies/${companyId}/reports/${reportId}`, {}, token),

  reviewerReportReview: (token: string, companyId: number, reportId: number) =>
    request<ReportReviewPayload>(`/api/v1/reviewer/companies/${companyId}/reports/${reportId}/review`, {}, token),

  updateReviewerReportReview: (token: string, companyId: number, reportId: number, payload: { status?: string; overall_note?: string }) =>
    request<ReportReviewPayload>(`/api/v1/reviewer/companies/${companyId}/reports/${reportId}/review`, { method: 'PATCH', body: JSON.stringify(payload) }, token),

  submitReviewerReportReview: (token: string, companyId: number, reportId: number) =>
    request<ReportReviewPayload>(`/api/v1/reviewer/companies/${companyId}/reports/${reportId}/review/submit`, { method: 'POST' }, token),

  updateSectionState: (token: string, companyId: number, reportId: number, sectionKey: string, status: string) =>
    request<{ section_state: { section_key: string; status: string } }>(
      `/api/v1/reviewer/companies/${companyId}/reports/${reportId}/review/section_states/${sectionKey}`,
      { method: 'PATCH', body: JSON.stringify({ status }) },
      token
    ),

  addReviewComment: (token: string, companyId: number, reportId: number, comment: { section_key: string; body: string }) =>
    request<{ comment: { id: number } }>(
      `/api/v1/reviewer/companies/${companyId}/reports/${reportId}/review/comments`,
      { method: 'POST', body: JSON.stringify({ comment }) },
      token
    ),

  reviewerConversations: (token: string, companyId: number) =>
    request<{ conversations: { id: number; employee_id: number; employee_name: string | null; status: string }[] }>(
      `/api/v1/reviewer/companies/${companyId}/conversations`,
      {},
      token
    ),

  reviewerConversation: (token: string, companyId: number, conversationId: number) =>
    request<{ conversation: { id: number; employee_id: number; status: string }; messages: { id: number; direction: string; body: string; reviewer_followup: boolean; created_at: string }[] }>(
      `/api/v1/reviewer/companies/${companyId}/conversations/${conversationId}`,
      {},
      token
    ),

  reviewerFollowupThread: (token: string, companyId: number, employeeId: number) =>
    request<{ threads: { id: number; body: string; status: string; replies: { body: string; received_at: string }[] }[] }>(
      `/api/v1/reviewer/companies/${companyId}/employees/${employeeId}/followup`,
      {},
      token
    ),

  sendReviewerFollowup: (token: string, companyId: number, employeeId: number, body: string, reportId?: number) =>
    request<{ info_request: { id: number } }>(
      `/api/v1/reviewer/companies/${companyId}/employees/${employeeId}/followup`,
      { method: 'POST', body: JSON.stringify({ body, report_id: reportId }) },
      token
    ),

  reviewerChatMessages: (token: string, companyId: number) =>
    request<{ messages: { id: number; body: string; sender_name: string; created_at: string; mine: boolean }[] }>(
      `/api/v1/reviewer/companies/${companyId}/chat_messages`,
      {},
      token
    ),

  sendReviewerChat: (token: string, companyId: number, body: string) =>
    request<{ message: { id: number } }>(
      `/api/v1/reviewer/companies/${companyId}/chat_messages`,
      { method: 'POST', body: JSON.stringify({ body }) },
      token
    ),
};

export interface ReviewerUser {
  id: number;
  email: string;
  name: string;
  status: string;
}

export interface ReviewerAssignment {
  id: number;
  status: string;
  assigned_at: string;
  reviewer_user: { id: number; name: string; email: string };
}

export interface ReviewerCompanySummary {
  id: number;
  name: string;
  report_readiness_score: number;
  completed_count: number;
  invited_count: number;
}

export interface ReviewerCompanyDetail extends ReviewerCompanySummary {
  participation: Record<string, unknown>;
  latest_report: { id: number; version: number; status: string } | null;
  my_review_status: string | null;
  co_reviewer_count: number;
}

export interface ReviewerReportDetail {
  id: number;
  version: number;
  status: string;
  report_snapshot: Record<string, unknown>;
  generated_at: string | null;
}

export interface ReportReviewPayload {
  review: {
    id: number;
    status: string;
    overall_note: string | null;
    submitted_at: string | null;
    section_states: { section_key: string; status: string }[];
    comments: { id: number; section_key: string; body: string; reviewer_name: string }[];
  };
  co_reviewer_reviews: {
    reviewer_name: string;
    status: string;
    section_states: { section_key: string; status: string }[];
    comments: { section_key: string; body: string }[];
  }[];
}

export interface AppNotification {
  id: number;
  notification_type: string;
  title: string;
  body: string;
  action_url: string | null;
  metadata: Record<string, unknown>;
  read_at: string | null;
  created_at: string;
}

export interface BillingSnapshot {
  subscription: {
    plan: string;
    status: string;
    trial_ends_at: string | null;
    current_period_ends_at: string | null;
    stripe_customer_id: boolean;
  } | null;
  usage: { conversations_used: number; conversation_limit: number | null; remaining: number | null; limit_reached: boolean };
  plans: { id: string; conversations: number; amount_cents: number }[];
  stripe_configured: boolean;
}

export interface ImpersonationResponse {
  token: string;
  expires_at: string;
  company: { id: number; name: string; display_name: string | null; portal_onboarding_completed_at: string | null };
  user: { id: number; email: string; name: string; role: string };
}

export interface PlatformMonitoring {
  companies: { total: number; onboarded: number; avg_readiness: number };
  subscriptions: { by_status: Record<string, number>; trials_expiring_7d: number; at_conversation_limit: number };
  discovery: { active_conversations: number; completed_employees: number; conversations_last_24h: number };
  reports: { ready: number; generating: number; failed: number };
  impersonations: { active_sessions: number; last_24h: number };
}

export interface Report {
  id: number;
  version: number;
  status: string;
  visibility: string;
  generated_at: string | null;
  share_active: boolean;
  share_token_expires_at: string | null;
  access_count: number;
  last_accessed_at: string | null;
  delta_summary: string | null;
  share_url?: string;
  error_message: string | null;
}

export interface PlatformSystemHealth {
  services: Record<string, { status: string; detail?: unknown }>;
  whatsapp_delivery: {
    last_24h: Record<string, number>;
    template_sent: number;
    template_failed: number;
    api_errors: number;
    failure_rate: number;
  };
}

export interface IntelligenceSnapshot {
  participation: { invited: number; started: number; completed: number; completion_rate: number };
  department_coverage: { department: string; completed: number; target: number }[];
  top_pain_points: { id: number; label: string; strength: number; departments: string[]; signal_type: string }[];
  emerging_patterns: { id: number; title: string; confidence: number; departments: string[] }[];
  report_readiness_score: number;
  report_ready: boolean;
  recommendation_count: number;
  recent_timeline: { type: string; title: string; summary?: string; occurred_at: string }[];
}

export interface TimelineEvent {
  id: number;
  event_type: string;
  title: string;
  summary: string | null;
  occurred_at: string;
}

export interface DiscoveryQuestion {
  id: number;
  body: string;
  created_at: string;
  employee: { id: number; display_name: string | null; department: string | null };
  feedback: string | null;
  feedback_note: string | null;
}

export interface Recommendation {
  id: number;
  title: string;
  description: string | null;
  implementation_outline: string | null;
  priority: string;
  catalog_matches: { name: string; vendor?: string; url?: string; partnership_tier?: string }[];
  company_feedback: string;
  company_feedback_note: string | null;
}

export interface SolutionCatalogEntry {
  id: number;
  name: string;
  vendor: string | null;
  category: string;
  description: string | null;
  website_url: string | null;
  tags: string[];
  match_keywords: string[];
  active: boolean;
  partnership_tier: string;
}

export interface CompanyDocument {
  id: number;
  filename: string;
  department: string | null;
  source: string;
  status: string;
  content_type: string | null;
  byte_size: number;
  insights_preview: { summary?: string; workflows?: string[]; friction_points?: string[]; chunk_count?: number };
  processing_error: string | null;
  created_at: string;
  updated_at: string;
}

export interface Playbook {
  id: number;
  department: string;
  version: number;
  prompt_block: string;
  active: boolean;
  notes: string | null;
  activated_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Company {
  id: number;
  name: string;
  slug: string;
  display_name: string | null;
  locale: string;
  report_readiness_score: number;
  portal_onboarding_completed_at: string | null;
  subscription: { plan: string; status: string; trial_ends_at: string | null } | null;
  created_at: string;
}

export interface CompanyDetail extends Company {
  settings: Record<string, unknown>;
  intelligence_snapshot: Record<string, unknown>;
  report_readiness_breakdown: Record<string, unknown>;
  onboarding_complete: boolean;
  completed_count?: number;
  invited_count?: number;
}

export interface CompanyUser {
  id: number;
  email: string;
  name: string;
  role: string;
  onboarding_completed_at: string | null;
}

export interface Employee {
  id: number;
  phone_e164: string;
  display_name: string | null;
  department: string | null;
  participation_status: string;
  onboarding_step: string;
  preferred_language: string | null;
  invited_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  last_active_at: string | null;
  last_nudged_at: string | null;
  consent_given_at?: string | null;
  access_code?: string;
  can_nudge?: boolean;
  stalled?: boolean;
  invitation_status?: string;
}
