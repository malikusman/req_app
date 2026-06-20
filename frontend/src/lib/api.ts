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

  platformCompany: (token: string, companyId: number) =>
    request<{ company: CompanyDetail }>(`/api/v1/platform/companies/${companyId}`, {}, token),

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
    request<{
      user: CompanyUser;
      company: CompanyDetail;
      impersonating?: boolean;
      usage: { conversations_used: number; conversation_limit: number | null; remaining: number | null; limit_reached: boolean };
    }>('/api/v1/company/me', {}, token),

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

  companyConversations: (token: string) =>
    request<{ conversations: CompanyConversation[] }>('/api/v1/company/conversations', {}, token),

  companyConversation: (token: string, conversationId: number) =>
    request<{ conversation: CompanyConversation; messages: CompanyConversationMessage[]; media_attachments: MediaAttachment[] }>(
      `/api/v1/company/conversations/${conversationId}`,
      {},
      token
    ),

  companyMediaAttachments: (token: string) =>
    request<{ media_attachments: MediaAttachment[] }>('/api/v1/company/media_attachments', {}, token),

  reviewerMediaAttachments: (token: string, companyId: number) =>
    request<{ media_attachments: MediaAttachment[] }>(
      `/api/v1/reviewer/companies/${companyId}/media_attachments`,
      {},
      token
    ),

  fetchMediaBlob: async (token: string, downloadUrl: string) => {
    const url = downloadUrl.startsWith('http') ? downloadUrl : `${API_URL}${downloadUrl}`;
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) throw new Error('Media download failed');
    const blob = await res.blob();
    return URL.createObjectURL(blob);
  },

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

  intelligenceSignals: (token: string) =>
    request<{ signals: CompanySignal[] }>('/api/v1/company/intelligence/signals', {}, token),

  intelligencePatterns: (token: string) =>
    request<{ patterns: CompanyPattern[] }>('/api/v1/company/intelligence/patterns', {}, token),

  platformCompanyReports: (token: string, companyId: number) =>
    request<{ reports: PlatformReport[] }>(`/api/v1/platform/companies/${companyId}/reports`, {}, token),

  platformCompanyConversations: (token: string, companyId: number) =>
    request<{ conversations: CompanyConversation[] }>(
      `/api/v1/platform/companies/${companyId}/conversations`,
      {},
      token
    ),

  platformCompanyConversation: (token: string, companyId: number, conversationId: number) =>
    request<{ conversation: CompanyConversation; messages: CompanyConversationMessage[]; media_attachments: MediaAttachment[] }>(
      `/api/v1/platform/companies/${companyId}/conversations/${conversationId}`,
      {},
      token
    ),

  platformCompanyIntelligenceSnapshot: (token: string, companyId: number) =>
    request<{ snapshot: IntelligenceSnapshot; report_readiness_score: number; report_readiness_breakdown: Record<string, number> }>(
      `/api/v1/platform/companies/${companyId}/intelligence/snapshot`,
      {},
      token
    ),

  platformCompanyIntelligenceSignals: (token: string, companyId: number) =>
    request<{ signals: CompanySignal[] }>(`/api/v1/platform/companies/${companyId}/intelligence/signals`, {}, token),

  platformCompanyIntelligencePatterns: (token: string, companyId: number) =>
    request<{ patterns: CompanyPattern[] }>(`/api/v1/platform/companies/${companyId}/intelligence/patterns`, {}, token),

  platformCompanyIntelligenceRecommendations: (token: string, companyId: number) =>
    request<{ recommendations: Recommendation[] }>(`/api/v1/platform/companies/${companyId}/intelligence/recommendations`, {}, token),

  platformCompanyIntelligenceTimeline: (token: string, companyId: number) =>
    request<{ events: TimelineEvent[] }>(`/api/v1/platform/companies/${companyId}/intelligence/timeline`, {}, token),

  approvePlatformReport: (token: string, companyId: number, reportId: number) =>
    request<{ report: PlatformReport }>(
      `/api/v1/platform/companies/${companyId}/reports/${reportId}/approve`,
      { method: 'POST' },
      token
    ),

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

  platformTrials: (token: string) =>
    request<{ trials: PlatformTrialRow[] }>('/api/v1/platform/trials', {}, token),

  extendPlatformTrial: (token: string, companyId: number, days: number) =>
    request<{ ok: boolean }>(`/api/v1/platform/trials/${companyId}/extend`, {
      method: 'POST',
      body: JSON.stringify({ days }),
    }, token),

  platformAuditLogs: (token: string, params?: { company_id?: number; action?: string; page?: number }) => {
    const search = new URLSearchParams();
    if (params?.company_id) search.set('company_id', String(params.company_id));
    if (params?.action) search.set('action', params.action);
    if (params?.page) search.set('page', String(params.page));
    const qs = search.toString();
    return request<{ audit_logs: PlatformAuditLogEntry[]; pagination: { page: number; per_page: number; total: number } }>(
      `/api/v1/platform/audit_logs${qs ? `?${qs}` : ''}`,
      {},
      token
    );
  },

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

  reviewerMe: (token: string) =>
    request<{
      user: { id: number; email: string; name: string };
      profile: ReviewerProfile;
      profile_completeness_percent: number;
      assignments: { company_id: number; company_name: string }[];
    }>('/api/v1/reviewer/me', {}, token),

  reviewerProfile: (token: string) =>
    request<{ ok: boolean; user: { id: number; email: string; name: string }; profile: ReviewerProfile }>(
      '/api/v1/reviewer/profile',
      {},
      token
    ),

  updateReviewerProfile: (
    token: string,
    payload: Partial<ReviewerProfilePayload> & { name?: string; email?: string; password?: string; publish?: boolean }
  ) =>
    request<{ ok: boolean; user: { id: number; email: string; name: string }; profile: ReviewerProfile }>(
      '/api/v1/reviewer/profile',
      { method: 'PATCH', body: JSON.stringify(payload) },
      token
    ),

  uploadReviewerAvatar: async (token: string, file: File) => {
    const headers: Record<string, string> = {};
    if (token) headers['Authorization'] = `Bearer ${token}`;
    const body = new FormData();
    body.append('file', file);
    const res = await fetch(`${API_URL}/api/v1/reviewer/profile/avatar`, { method: 'POST', headers, body });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = (data as ApiError).error || res.statusText;
      throw new Error(err);
    }
    return data as { ok: boolean; user: { id: number; email: string; name: string }; profile: ReviewerProfile };
  },

  companyExpertReviewers: (token: string) =>
    request<{ expert_reviewers: ReviewerPublicCard[] }>('/api/v1/company/expert_reviewers', {}, token),

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

  reviewerFollowups: (token: string) =>
    request<{ followups: ReviewerFollowupRow[] }>('/api/v1/reviewer/followups', {}, token),

  reviewerNotifications: (token: string, params?: { page?: number; per_page?: number }) => {
    const search = new URLSearchParams();
    if (params?.page) search.set('page', String(params.page));
    if (params?.per_page) search.set('per_page', String(params.per_page));
    const qs = search.toString();
    return request<{ notifications: AppNotification[]; unread_count: number; page: number; per_page: number }>(
      `/api/v1/reviewer/notifications${qs ? `?${qs}` : ''}`,
      {},
      token
    );
  },

  markReviewerNotificationRead: (token: string, id: number) =>
    request<{ notification: AppNotification }>(`/api/v1/reviewer/notifications/${id}`, { method: 'PATCH' }, token),

  markAllReviewerNotificationsRead: (token: string) =>
    request<{ ok: boolean; unread_count: number }>('/api/v1/reviewer/notifications/mark_all_read', { method: 'POST' }, token),

  reviewerConversation: (token: string, companyId: number, conversationId: number) =>
    request<{
      conversation: { id: number; employee_id: number; status: string };
      messages: CompanyConversationMessage[];
      media_attachments: MediaAttachment[];
    }>(
      `/api/v1/reviewer/companies/${companyId}/conversations/${conversationId}`,
      {},
      token
    ),

  reviewerFollowupThread: (token: string, companyId: number, employeeId: number) =>
    request<{
      employee: { id: number; display_name: string | null };
      threads: { id: number; body: string; status: string; replies: { body: string; received_at: string }[] }[];
    }>(`/api/v1/reviewer/companies/${companyId}/employees/${employeeId}/followup`, {}, token),

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

export interface ReviewerProfileCompleteness {
  percent: number;
  complete: boolean;
  missing: string[];
  checks: Record<string, boolean>;
}

export interface ReviewerExperience {
  id?: number;
  organization: string;
  title: string;
  start_year: number;
  end_year?: number | null;
  summary?: string | null;
  sort_order?: number;
}

export interface ReviewerProfile {
  headline: string | null;
  bio: string | null;
  linkedin_url: string | null;
  website_url: string | null;
  location: string | null;
  timezone: string | null;
  languages: string[];
  expertise_tags: string[];
  industries: string[];
  years_experience: number | null;
  credentials: { label: string; issuer?: string; year?: number }[];
  profile_status: 'draft' | 'published';
  profile_completed_at: string | null;
  platform_verified_at: string | null;
  avatar_url: string | null;
  experiences: ReviewerExperience[];
  completeness: ReviewerProfileCompleteness;
  suggested_expertise_tags: string[];
}

export interface ReviewerProfilePayload {
  headline?: string;
  bio?: string;
  linkedin_url?: string;
  website_url?: string;
  location?: string;
  timezone?: string;
  languages?: string[];
  expertise_tags?: string[];
  industries?: string[];
  years_experience?: number | null;
  credentials?: { label: string; issuer?: string; year?: number }[];
  experiences?: ReviewerExperience[];
}

export interface ReviewerPublicCard {
  id: number;
  name: string;
  headline: string | null;
  avatar_url: string | null;
  expertise_tags: string[];
  industries: string[];
  years_experience: number | null;
  languages: string[];
  location: string | null;
  linkedin_url: string | null;
  profile_status: string;
  platform_verified: boolean;
}

export interface ReviewerUser {
  id: number;
  email: string;
  name: string;
  status: string;
  profile_status?: string;
  profile_completeness_percent?: number;
  headline?: string | null;
  expertise_tags?: string[];
  avatar_url?: string | null;
  profile?: ReviewerProfile;
  public_card?: ReviewerPublicCard;
}

export interface ReviewerAssignment {
  id: number;
  status: string;
  assigned_at: string;
  reviewer_user: ReviewerUser;
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

export interface PlatformTrialRow {
  company: {
    id: number;
    name: string;
    report_readiness_score: number;
    completed_count?: number;
    invited_count?: number;
  };
  subscription: {
    trial_ends_at?: string;
    days_remaining: number;
    plan?: string;
    status?: string;
  };
}

export interface Report {
  id: number;
  version: number;
  status: string;
  visibility: string;
  review_workflow_status?: string;
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

export interface CompanySignal {
  id: number;
  label: string;
  signal_type: string;
  strength: number;
  departments: string[];
  evidence_count: number;
  multimodal_evidence?: MultimodalEvidence[];
  status: string;
  first_seen_at: string | null;
  last_updated_at: string | null;
}

export interface MultimodalEvidence {
  source: string;
  id: number;
  attachment_type: string;
  conversation_id?: number;
  excerpt?: string;
  confidence?: number | null;
}

export interface CompanyPattern {
  id: number;
  title: string;
  description: string | null;
  confidence: number;
  departments: string[];
  status: string;
  linked_signal_ids: number[];
  first_seen_at: string | null;
  last_updated_at: string | null;
}

export interface PlatformReport extends Report {
  review_workflow_status?: string;
  reviews_completed_at?: string | null;
  reviewer_progress?: { reviewer_name: string; status: string }[];
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

export interface CompanyConversation {
  id: number;
  employee_id: number;
  employee_name: string | null;
  department: string | null;
  status: string;
  question_count?: number;
  last_activity_at: string | null;
  discovery_state?: DiscoveryState;
}

export interface DiscoveryAgentQueueEntry {
  id: string;
  priority: number;
  question_budget: number;
  reason: string;
}

export interface DiscoveryAgentState {
  questions_asked: number;
  question_budget: number;
  status: string;
  open_threads?: { topic: string; depth: number; needs_followup: boolean }[];
}

export interface DiscoveryState {
  profile: Record<string, unknown>;
  agent_queue: DiscoveryAgentQueueEntry[];
  skipped_agents: { id: string; reason: string }[];
  agent_states: Record<string, DiscoveryAgentState>;
  active_agent_id: string | null;
  coverage: { topics_required?: string[]; topics_covered?: string[] };
  shared_findings: { agent: string; finding: string; confidence: number; turn: number }[];
  conversation_summary: string | null;
  last_routing_decision: { action: string; agent: string | null; reason: string } | null;
}

export interface CompanyConversationMessage {
  id: number;
  direction: string;
  message_type?: string;
  body: string;
  is_discovery_question?: boolean;
  reviewer_followup?: boolean;
  media_attachment?: MediaAttachment;
  created_at: string;
}

export interface MediaAttachment {
  id: number;
  message_id: number;
  attachment_type: 'audio' | 'image' | 'document';
  mime_type: string | null;
  status: string;
  caption: string | null;
  confidence: number | null;
  duration_ms: number | null;
  language: string | null;
  structured_insights: Record<string, unknown>;
  processing_error: string | null;
  document_id: number | null;
  filename: string;
  download_url: string | null;
  created_at: string;
  updated_at: string;
  employee_name?: string | null;
  conversation_id?: number;
}

export interface PlatformAuditLogEntry {
  id: number;
  actor: string;
  action: string;
  target: string;
  created_at: string;
  ip: string | null;
}

export interface ReviewerFollowupRow {
  id: number;
  company_id: number;
  company_name: string;
  employee_id: number;
  employee_name: string | null;
  status: string;
  last_message: string;
  updated_at: string;
  sent_at: string | null;
}
