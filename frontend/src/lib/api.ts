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

async function fetchPreviewBlob(token: string, path: string) {
  const res = await fetch(`${API_URL}${path}${path.includes('?') ? '&' : '?'}inline=1`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error('Preview failed');
  return URL.createObjectURL(await res.blob());
}

export const api = {
  publicDemoRequest: (payload: {
    name: string;
    email: string;
    company_name: string;
    role?: string;
    notes?: string;
    website?: string;
  }) =>
    request<{ ok: boolean }>('/api/v1/public/demo_requests', {
      method: 'POST',
      body: JSON.stringify(payload),
    }),

  publicCompanyRegistration: (payload: {
    company_name: string;
    display_name?: string;
    admin_name: string;
    admin_email: string;
    admin_phone?: string;
    role_title?: string;
    notes?: string;
    website?: string;
    website_url?: string;
    engagement_mode?: string;
    company_profile?: CompanyProfile;
    known_systems?: string[];
  }) =>
    request<{ ok: boolean; registration?: { id: number; status: string } }>(
      '/api/v1/public/company_registrations',
      { method: 'POST', body: JSON.stringify(payload) }
    ),

  publicConsultantApplication: (payload: {
    name: string;
    email: string;
    headline?: string;
    expertise_summary?: string;
    notes?: string;
    website?: string;
  }) =>
    request<{ ok: boolean; application?: { id: number; status: string } }>(
      '/api/v1/public/consultant_applications',
      { method: 'POST', body: JSON.stringify(payload) }
    ),

  requestPasswordReset: (portal: string, email: string) =>
    request<{ ok: boolean }>('/api/v1/public/password_resets', {
      method: 'POST',
      body: JSON.stringify({ portal, email }),
    }),

  verifyPasswordReset: (token: string) =>
    request<{ ok: boolean; portal: string; email: string; name?: string }>(
      `/api/v1/public/password_resets/verify?token=${encodeURIComponent(token)}`
    ),

  confirmPasswordReset: (token: string, password: string, password_confirmation: string) =>
    request<{ ok: boolean }>('/api/v1/public/password_resets/confirm', {
      method: 'PUT',
      body: JSON.stringify({ token, password, password_confirmation }),
    }),

  platformRegistrations: (token: string, status?: string) =>
    request<{
      company_registrations: CompanyRegistrationRow[];
      consultant_applications: ConsultantApplicationRow[];
    }>(
      `/api/v1/platform/registrations${status ? `?status=${encodeURIComponent(status)}` : ''}`,
      {},
      token
    ),

  approveCompanyRegistration: (token: string, id: number, review_note?: string) =>
    request<{ company_registration: CompanyRegistrationRow }>(
      `/api/v1/platform/registrations/companies/${id}/approve`,
      { method: 'POST', body: JSON.stringify({ review_note }) },
      token
    ),

  rejectCompanyRegistration: (token: string, id: number, review_note?: string) =>
    request<{ company_registration: CompanyRegistrationRow }>(
      `/api/v1/platform/registrations/companies/${id}/reject`,
      { method: 'POST', body: JSON.stringify({ review_note }) },
      token
    ),

  approveConsultantApplication: (token: string, id: number, review_note?: string) =>
    request<{ consultant_application: ConsultantApplicationRow }>(
      `/api/v1/platform/registrations/consultants/${id}/approve`,
      { method: 'POST', body: JSON.stringify({ review_note }) },
      token
    ),

  rejectConsultantApplication: (token: string, id: number, review_note?: string) =>
    request<{ consultant_application: ConsultantApplicationRow }>(
      `/api/v1/platform/registrations/consultants/${id}/reject`,
      { method: 'POST', body: JSON.stringify({ review_note }) },
      token
    ),

  platformLogin: (email: string, password: string) =>
    request<{ token: string; user: { id: number; email: string; name: string; role: string } }>(
      '/api/v1/auth/platform/login',
      { method: 'POST', body: JSON.stringify({ email, password }) }
    ),

  consultantLogin: (email: string, password: string) =>
    request<{ token: string; user: { id: number; email: string; name: string } }>(
      '/api/v1/auth/consultant/login',
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

  resetPlatformCompanyAdminPassword: (token: string, companyId: number, password: string) =>
    request<{ ok: boolean; email: string }>(
      `/api/v1/platform/companies/${companyId}/reset_admin_password`,
      { method: 'POST', body: JSON.stringify({ password }) },
      token
    ),

  companyMe: (token: string) =>
    request<{
      user: CompanyUser;
      company: CompanyDetail;
      impersonating?: boolean;
      usage: { conversations_used: number; conversation_limit: number | null; remaining: number | null; limit_reached: boolean };
    }>('/api/v1/company/me', {}, token),

  updateCompanyMe: (
    token: string,
    payload: { name?: string; phone?: string | null }
  ) =>
    request<{ ok: boolean; user: CompanyUser }>(
      '/api/v1/company/me',
      { method: 'PATCH', body: JSON.stringify(payload) },
      token
    ),

  companyDashboard: (token: string) =>
    request<CompanyDashboardPayload>('/api/v1/company/dashboard', {}, token),

  companyOnboarding: (token: string) =>
    request<{
      step: number;
      portal_onboarding_completed_at?: string | null;
      questionnaire_completed_at?: string | null;
      questionnaire_answers?: Record<string, string | string[]>;
      completion_percent?: number;
      section_status?: Record<string, { touched: boolean; complete: boolean }>;
      company: {
        display_name: string;
        locale: string;
        engagement_mode?: string;
        company_profile?: CompanyProfile;
        known_systems?: string[];
        website_url?: string | null;
      };
      invited_count: number;
    }>('/api/v1/company/onboarding', {}, token),

  updateOnboardingProfile: (
    token: string,
    payload: {
      display_name?: string;
      locale?: string;
      engagement_mode?: string;
      company_profile?: CompanyProfile;
      known_systems?: string[];
      website_url?: string | null;
    }
  ) =>
    request<{
      ok: boolean;
      step?: number;
      engagement_mode?: string;
      company_profile?: CompanyProfile;
      website_url?: string | null;
    }>(
      '/api/v1/company/onboarding/profile',
      {
        method: 'PATCH',
        body: JSON.stringify(payload),
      },
      token
    ),

  updateOnboardingQuestionnaire: (
    token: string,
    payload: {
      questionnaire_answers: Record<string, string | string[] | undefined>;
      questionnaire_step?: number;
    }
  ) =>
    request<{
      ok: boolean;
      questionnaire_answers: Record<string, string | string[]>;
      questionnaire_step: number;
      questionnaire_completed_at?: string | null;
      completion_percent: number;
      section_status?: Record<string, { touched: boolean; complete: boolean }>;
    }>('/api/v1/company/onboarding/questionnaire', { method: 'PATCH', body: JSON.stringify(payload) }, token),

  completeOnboarding: (token: string, payload?: { mark_questionnaire_complete?: boolean }) =>
    request<{ ok: boolean; redirect_to?: string; completion_percent?: number }>(
      '/api/v1/company/onboarding/complete',
      { method: 'POST', body: JSON.stringify(payload || {}) },
      token
    ),

  companyEmployees: (token: string) =>
    request<{ employees: Employee[] }>('/api/v1/company/employees', {}, token),

  employeeValuePreference: (token: string, employeeId: number) =>
    request<{
      employee_value_preference: EmployeeValuePreference;
      latest_digest: EmployeeValueDigest | null;
    }>(`/api/v1/company/employees/${employeeId}/value_preference`, {}, token),

  updateEmployeeValuePreference: (
    token: string,
    employeeId: number,
    payload: {
      email_opt_in?: boolean;
      frequency?: string;
      locale?: string;
      interests?: string[];
    }
  ) =>
    request<{
      employee_value_preference: EmployeeValuePreference;
      latest_digest: EmployeeValueDigest | null;
    }>(
      `/api/v1/company/employees/${employeeId}/value_preference`,
      { method: 'PATCH', body: JSON.stringify({ employee_value_preference: payload }) },
      token
    ),

  generateEmployeeValueDigest: (token: string, employeeId: number, periodKey?: string) =>
    request<{ digest: EmployeeValueDigest }>(
      `/api/v1/company/employees/${employeeId}/value_preference/generate_digest`,
      { method: 'POST', body: JSON.stringify(periodKey ? { period_key: periodKey } : {}) },
      token
    ),

  sendEmployeeValueDigest: (token: string, employeeId: number, periodKey?: string) =>
    request<{ digest: EmployeeValueDigest; message?: string }>(
      `/api/v1/company/employees/${employeeId}/value_preference/send_digest`,
      { method: 'POST', body: JSON.stringify(periodKey ? { period_key: periodKey } : {}) },
      token
    ),

  inviteEmployee: (
    token: string,
    phone_e164: string,
    display_name?: string,
    department?: string,
    email?: string,
    preferred_channel?: 'whatsapp' | 'web' | 'both'
  ) =>
    request<{ employee: Employee; discover_url?: string }>(
      '/api/v1/company/employees',
      {
        method: 'POST',
        body: JSON.stringify({ phone_e164, display_name, department, email, preferred_channel }),
      },
      token
    ),

  bulkInviteEmployees: (
    token: string,
    employees: { phone_e164: string; display_name?: string; department?: string; email?: string }[]
  ) =>
    request<{ employees: Employee[] }>(
      '/api/v1/company/employees/bulk_create',
      { method: 'POST', body: JSON.stringify({ employees }) },
      token
    ),

  nudgeEmployee: async (token: string, employeeId: number) => {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    };
    const res = await fetch(`${API_URL}/api/v1/company/employees/${employeeId}/nudge`, {
      method: 'POST',
      headers,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const body = data as ApiError & { retry_after_hours?: number };
      if (res.status === 429 && body.retry_after_hours != null) {
        throw new Error(`Nudge cooldown active — try again in ~${Math.ceil(body.retry_after_hours)}h`);
      }
      throw new Error(body.error || res.statusText);
    }
    return data as { ok: boolean; message: string; nudge: EmployeeNudge };
  },

  companyConversations: (token: string) =>
    request<{ conversations: CompanyConversation[] }>('/api/v1/company/conversations', {}, token),

  companyConversation: (token: string, conversationId: number) =>
    request<{
      conversation: CompanyConversation;
      discovery_provenance: DiscoveryProvenanceEntry[];
      messages: CompanyConversationMessage[];
      media_attachments: MediaAttachment[];
    }>(
      `/api/v1/company/conversations/${conversationId}`,
      {},
      token
    ),

  companyMediaAttachments: (token: string) =>
    request<{ media_attachments: MediaAttachment[] }>('/api/v1/company/media_attachments', {}, token),

  fetchMediaBlob: async (token: string, downloadUrl: string) => {
    let path = downloadUrl;
    if (downloadUrl.startsWith('http://') || downloadUrl.startsWith('https://')) {
      try {
        const parsed = new URL(downloadUrl);
        path = `${parsed.pathname}${parsed.search}`;
      } catch {
        path = downloadUrl;
      }
    }
    if (!path.startsWith('/')) path = `/${path}`;

    const url = `${API_URL}${path}`;
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      const detail = res.status === 404 ? 'Media not found' : res.status === 401 ? 'Unauthorized' : `HTTP ${res.status}`;
      throw new Error(`Media download failed (${detail})`);
    }
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

  updateCompanyDocument: (
    token: string,
    id: number,
    payload: { consultant_visible?: boolean; department?: string | null }
  ) =>
    request<{ document: CompanyDocument }>(
      `/api/v1/company/documents/${id}`,
      { method: 'PATCH', body: JSON.stringify(payload) },
      token
    ),

  replaceCompanyDocument: async (token: string, id: number, file: File) => {
    const form = new FormData();
    form.append('file', file);
    const res = await fetch(`${API_URL}/api/v1/company/documents/${id}/replace`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: form,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error((data as ApiError).error || res.statusText);
    return data as { document: CompanyDocument };
  },

  deleteCompanyDocument: (token: string, id: number) =>
    request<void>(`/api/v1/company/documents/${id}`, { method: 'DELETE' }, token),

  downloadCompanyDocument: async (token: string, id: number, filename: string) => {
    const res = await fetch(`${API_URL}/api/v1/company/documents/${id}/download`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) throw new Error('Download failed');
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  },

  consultantDocuments: (token: string, companyId: number) =>
    request<{ documents: CompanyDocument[] }>(`/api/v1/consultant/companies/${companyId}/documents`, {}, token),

  consultantDocument: (token: string, companyId: number, id: number) =>
    request<{ document: CompanyDocument }>(`/api/v1/consultant/companies/${companyId}/documents/${id}`, {}, token),

  downloadConsultantDocument: async (token: string, companyId: number, id: number, filename: string) => {
    const res = await fetch(`${API_URL}/api/v1/consultant/companies/${companyId}/documents/${id}/download`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) throw new Error('Download failed');
    const blob = await res.blob();
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    a.click();
    URL.revokeObjectURL(url);
  },

  companyOutreaches: (token: string) =>
    request<{ outreaches: Array<Record<string, unknown>> }>('/api/v1/company/outreaches', {}, token),

  consultantOutreaches: (token: string, companyId: number) =>
    request<{ outreaches: Array<Record<string, unknown>> }>(
      `/api/v1/consultant/companies/${companyId}/outreaches`,
      {},
      token
    ),

  createConsultantOutreach: (
    token: string,
    companyId: number,
    payload: {
      body: string;
      purpose?: string;
      channel?: string;
      recipient_type?: string;
      recipient_id?: number;
      employee_id?: number;
      report_id?: number;
      reason?: string;
      section_key?: string;
    }
  ) =>
    request<{ outreach: Record<string, unknown> }>(
      `/api/v1/consultant/companies/${companyId}/outreaches`,
      { method: 'POST', body: JSON.stringify(payload) },
      token
    ),

  approveOutreach: (token: string, id: number, payload: { note?: string; edited_body?: string; employee_id?: number } = {}) =>
    request<{ outreach: Record<string, unknown> }>(
      `/api/v1/company/outreaches/${id}/approve`,
      { method: 'POST', body: JSON.stringify(payload) },
      token
    ),

  declineOutreach: (token: string, id: number, payload: { note?: string } = {}) =>
    request<{ outreach: Record<string, unknown> }>(
      `/api/v1/company/outreaches/${id}/decline`,
      { method: 'POST', body: JSON.stringify(payload) },
      token
    ),

  answerOutreach: (token: string, id: number, payload: { body: string; channel?: string }) =>
    request<{ outreach: Record<string, unknown>; reply: Record<string, unknown> }>(
      `/api/v1/company/outreaches/${id}/answer`,
      { method: 'POST', body: JSON.stringify(payload) },
      token
    ),

  consultantReportFindings: (token: string, companyId: number, reportId: number) =>
    request<{ findings: Array<Record<string, unknown>> }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/review/findings`,
      {},
      token
    ),

  createConsultantReportFinding: (
    token: string,
    companyId: number,
    reportId: number,
    payload: Record<string, unknown>
  ) =>
    request<{ finding: Record<string, unknown> }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/review/findings`,
      { method: 'POST', body: JSON.stringify({ finding: payload }) },
      token
    ),

  platformCatalogCandidates: (
    token: string,
    opts?: {
      reviewStatus?: string;
      analysisStatus?: string;
      entityType?: string;
      catalogSourceId?: number;
      page?: number;
      perPage?: number;
    }
  ) => {
    const params = new URLSearchParams();
    if (opts?.reviewStatus) params.set('review_status', opts.reviewStatus);
    if (opts?.analysisStatus) params.set('analysis_status', opts.analysisStatus);
    if (opts?.entityType) params.set('entity_type', opts.entityType);
    if (opts?.catalogSourceId) params.set('catalog_source_id', String(opts.catalogSourceId));
    if (opts?.page) params.set('page', String(opts.page));
    if (opts?.perPage) params.set('per_page', String(opts.perPage));
    const qs = params.toString();
    return request<{
      catalog_candidates: Array<Record<string, unknown>>;
      pagination: { page: number; per_page: number; total: number };
    }>(`/api/v1/platform/catalog/candidates${qs ? `?${qs}` : ''}`, {}, token);
  },

  platformCatalogCandidate: (token: string, id: number) =>
    request<{ catalog_candidate: Record<string, unknown> }>(
      `/api/v1/platform/catalog/candidates/${id}`,
      {},
      token
    ),

  platformCatalogSources: (token: string) =>
    request<{ catalog_sources: Array<Record<string, unknown>>; sync_interval_hours?: number }>(
      '/api/v1/platform/catalog/sources',
      {},
      token
    ),

  createPlatformCatalogSource: (token: string, payload: Record<string, unknown>) =>
    request<{ catalog_source: Record<string, unknown> }>(
      '/api/v1/platform/catalog/sources',
      { method: 'POST', body: JSON.stringify({ catalog_source: payload }) },
      token
    ),

  updatePlatformCatalogSource: (token: string, id: number, payload: Record<string, unknown>) =>
    request<{ catalog_source: Record<string, unknown> }>(
      `/api/v1/platform/catalog/sources/${id}`,
      { method: 'PATCH', body: JSON.stringify({ catalog_source: payload }) },
      token
    ),

  syncPlatformCatalogSource: (token: string, id: number) =>
    request<{ catalog_source: Record<string, unknown>; catalog_sync_run: Record<string, unknown> }>(
      `/api/v1/platform/catalog/sources/${id}/sync`,
      { method: 'POST' },
      token
    ),

  syncAllCatalogSources: (token: string) =>
    request<{ status: string }>('/api/v1/platform/catalog/sync', { method: 'POST' }, token),

  seedRecommendedCatalogSources: (token: string) =>
    request<{ catalog_sources: Array<Record<string, unknown>>; created_or_updated: number }>(
      '/api/v1/platform/catalog/sources/seed_recommended',
      { method: 'POST' },
      token
    ),

  consultantCatalog: (token: string, companyId: number) =>
    request<{
      matches: Array<Record<string, unknown>>;
      endorsements: Array<Record<string, unknown>>;
      last_matched_at?: string | null;
      note?: string;
    }>(`/api/v1/consultant/companies/${companyId}/catalog`, {}, token),

  consultantAvailableCatalog: (token: string, companyId: number, q?: string) =>
    request<{ solutions: SolutionCatalogEntry[] }>(
      `/api/v1/consultant/companies/${companyId}/catalog/available${q ? `?q=${encodeURIComponent(q)}` : ''}`,
      {},
      token
    ),

  consultantAddCatalogProduct: (
    token: string,
    companyId: number,
    payload: { solution_catalog_entry_id: number; why_it_fits?: string }
  ) =>
    request<{ match: Record<string, unknown> }>(
      `/api/v1/consultant/companies/${companyId}/catalog/add`,
      { method: 'POST', body: JSON.stringify(payload) },
      token
    ),

  endorseConsultantCatalogMatch: (
    token: string,
    companyId: number,
    matchId: number,
    payload: { disposition: string; rationale?: string; report_id?: number; publishable?: boolean; source_url?: string }
  ) =>
    request<{ endorsement: Record<string, unknown> }>(
      `/api/v1/consultant/companies/${companyId}/catalog/${matchId}/endorse`,
      { method: 'POST', body: JSON.stringify(payload) },
      token
    ),

  approveCatalogCandidate: (token: string, id: number, payload: { review_note?: string; attributes?: Record<string, unknown> } = {}) =>
    request<{ catalog_candidate: Record<string, unknown> }>(
      `/api/v1/platform/catalog/candidates/${id}/approve`,
      { method: 'POST', body: JSON.stringify(payload) },
      token
    ),

  rejectCatalogCandidate: (token: string, id: number, payload: { review_note?: string } = {}) =>
    request<{ catalog_candidate: Record<string, unknown> }>(
      `/api/v1/platform/catalog/candidates/${id}/reject`,
      { method: 'POST', body: JSON.stringify(payload) },
      token
    ),

  uploadDocument: async (token: string, file: File, opts?: { department?: string; consultant_visible?: boolean }) => {
    const form = new FormData();
    form.append('file', file);
    if (opts?.department) form.append('department', opts.department);
    if (opts?.consultant_visible === false) form.append('consultant_visible', 'false');

    const res = await fetch(`${API_URL}/api/v1/company/documents`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}` },
      body: form,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error((data as ApiError).error || res.statusText);
    return data as { document: CompanyDocument };
  },

  startDocumentAnalysis: (
    token: string,
    payload?: { run_kind?: string; document_ids?: number[] }
  ) =>
    request<{ run: DocumentAnalysisRun }>(
      '/api/v1/company/document_analysis_runs',
      { method: 'POST', body: JSON.stringify(payload || {}) },
      token
    ),

  documentAnalysisRuns: (token: string) =>
    request<{
      runs: DocumentAnalysisRun[];
      awaiting_analysis_count: number;
      profile_stale: boolean;
      active_run: DocumentAnalysisRun | null;
    }>('/api/v1/company/document_analysis_runs', {}, token),

  documentAnalysisRun: (token: string, id: number) =>
    request<{ run: DocumentAnalysisRun; events: DocumentAnalysisEvent[] }>(
      `/api/v1/company/document_analysis_runs/${id}`,
      {},
      token
    ),

  companyKnowledgeEntries: (token: string) =>
    request<{ knowledge_entries: CompanyKnowledgeEntry[] }>('/api/v1/company/knowledge_entries', {}, token),

  companyClarificationQuestions: (token: string) =>
    request<{ clarification_questions: CompanyClarificationQuestion[] }>(
      '/api/v1/company/clarification_questions',
      {},
      token
    ),

  answerClarificationQuestion: (token: string, id: number, answer: string) =>
    request<{ clarification_question: CompanyClarificationQuestion }>(
      `/api/v1/company/clarification_questions/${id}/answer`,
      { method: 'POST', body: JSON.stringify({ answer }) },
      token
    ),

  consultantDocumentAnalysis: (token: string, companyId: number) =>
    request<{
      company_id: number;
      latest_run: DocumentAnalysisRun | null;
      events: DocumentAnalysisEvent[];
      knowledge_entries: CompanyKnowledgeEntry[];
      clarification_questions: CompanyClarificationQuestion[];
    }>(`/api/v1/consultant/companies/${companyId}/document_analysis`, {}, token),

  dismissClarificationQuestion: (token: string, companyId: number, id: number) =>
    request<{ clarification_question: CompanyClarificationQuestion }>(
      `/api/v1/consultant/companies/${companyId}/clarification_questions/${id}/dismiss`,
      { method: 'POST', body: JSON.stringify({}) },
      token
    ),

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
    request<{
      conversation: CompanyConversation;
      discovery_provenance: DiscoveryProvenanceEntry[];
      messages: CompanyConversationMessage[];
      media_attachments: MediaAttachment[];
    }>(
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

  previewPlatformReport: (token: string, companyId: number, reportId: number) =>
    fetchPreviewBlob(token, `/api/v1/platform/companies/${companyId}/reports/${reportId}/download`),

  previewConsultantReport: (token: string, companyId: number, reportId: number) =>
    fetchPreviewBlob(token, `/api/v1/consultant/companies/${companyId}/reports/${reportId}/download`),

  // Live HTML render WITH the consultant's pending section edits + findings applied.
  previewConsultantReportDraft: (token: string, companyId: number, reportId: number) =>
    fetchPreviewBlob(token, `/api/v1/consultant/companies/${companyId}/reports/${reportId}/preview`),

  previewPlatformReportDraft: (token: string, companyId: number, reportId: number) =>
    fetchPreviewBlob(token, `/api/v1/platform/companies/${companyId}/reports/${reportId}/preview`),

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
    request<{ employee: Employee }>(
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

  platformCompanySystems: (token: string, companyId: number) =>
    request<{ company_systems: CompanySystemRow[] }>(
      `/api/v1/platform/companies/${companyId}/company_systems`,
      {},
      token
    ),

  createPlatformCompanySystem: (token: string, companyId: number, payload: Partial<CompanySystemRow>) =>
    request<{ company_system: CompanySystemRow }>(
      `/api/v1/platform/companies/${companyId}/company_systems`,
      { method: 'POST', body: JSON.stringify({ company_system: payload }) },
      token
    ),

  updatePlatformCompanySystem: (token: string, companyId: number, id: number, payload: Partial<CompanySystemRow>) =>
    request<{ company_system: CompanySystemRow }>(
      `/api/v1/platform/companies/${companyId}/company_systems/${id}`,
      { method: 'PATCH', body: JSON.stringify({ company_system: payload }) },
      token
    ),

  inferPlatformCompanySystems: (token: string, companyId: number) =>
    request<{ inferred: number; company_systems: CompanySystemRow[] }>(
      `/api/v1/platform/companies/${companyId}/company_systems/infer`,
      { method: 'POST' },
      token
    ),

  platformAgenticIdeas: (token: string, companyId: number) =>
    request<{ agentic_ideas: AgenticIdea[] }>(
      `/api/v1/platform/companies/${companyId}/agentic_ideas`,
      {},
      token
    ),

  createPlatformAgenticIdea: (token: string, companyId: number, payload: Partial<AgenticIdea>) =>
    request<{ agentic_idea: AgenticIdea }>(
      `/api/v1/platform/companies/${companyId}/agentic_ideas`,
      { method: 'POST', body: JSON.stringify({ agentic_idea: payload }) },
      token
    ),

  updatePlatformAgenticIdea: (token: string, companyId: number, id: number, payload: Partial<AgenticIdea>) =>
    request<{ agentic_idea: AgenticIdea }>(
      `/api/v1/platform/companies/${companyId}/agentic_ideas/${id}`,
      { method: 'PATCH', body: JSON.stringify({ agentic_idea: payload }) },
      token
    ),

  publishPlatformAgenticIdea: (token: string, companyId: number, id: number) =>
    request<{ agentic_idea: AgenticIdea }>(
      `/api/v1/platform/companies/${companyId}/agentic_ideas/${id}/publish`,
      { method: 'POST' },
      token
    ),

  archivePlatformAgenticIdea: (token: string, companyId: number, id: number) =>
    request<{ agentic_idea: AgenticIdea }>(
      `/api/v1/platform/companies/${companyId}/agentic_ideas/${id}/archive`,
      { method: 'POST' },
      token
    ),

  synthesizePlatformAgenticIdeas: (token: string, companyId: number) =>
    request<{ agentic_ideas: AgenticIdea[]; synthesized: number }>(
      `/api/v1/platform/companies/${companyId}/agentic_ideas/synthesize`,
      { method: 'POST' },
      token
    ),

  consultantAgenticIdeas: (token: string, companyId: number) =>
    request<{ agentic_ideas: AgenticIdea[] }>(
      `/api/v1/consultant/companies/${companyId}/agentic_ideas`,
      {},
      token
    ),

  createConsultantAgenticIdea: (token: string, companyId: number, payload: Partial<AgenticIdea>) =>
    request<{ agentic_idea: AgenticIdea }>(
      `/api/v1/consultant/companies/${companyId}/agentic_ideas`,
      { method: 'POST', body: JSON.stringify({ agentic_idea: payload }) },
      token
    ),

  updateConsultantAgenticIdea: (token: string, companyId: number, id: number, payload: Partial<AgenticIdea>) =>
    request<{ agentic_idea: AgenticIdea }>(
      `/api/v1/consultant/companies/${companyId}/agentic_ideas/${id}`,
      { method: 'PATCH', body: JSON.stringify({ agentic_idea: payload }) },
      token
    ),

  publishConsultantAgenticIdea: (token: string, companyId: number, id: number) =>
    request<{ agentic_idea: AgenticIdea }>(
      `/api/v1/consultant/companies/${companyId}/agentic_ideas/${id}/publish`,
      { method: 'POST' },
      token
    ),

  companyAgenticIdeas: (token: string) =>
    request<{ agentic_ideas: AgenticIdea[] }>('/api/v1/company/agentic_ideas', {}, token),

  companyReports: (token: string) =>
    request<{
      reports: Report[];
      intelligence_updated_at?: string | null;
      report_stale?: boolean;
      latest_ready_generated_at?: string | null;
    }>('/api/v1/company/reports', {}, token),

  generateReport: (token: string) =>
    request<{ report: Report }>('/api/v1/company/reports', { method: 'POST' }, token),

  // Inline blob → object URL for an in-portal report viewer.
  previewCompanyReport: (token: string, id: number) =>
    fetchPreviewBlob(token, `/api/v1/company/reports/${id}/download`),

  shareReport: (token: string, id: number, days: number) =>
    request<{ share_token: string; share_url: string; expires_at: string }>(
      `/api/v1/company/reports/${id}/share`,
      { method: 'POST', body: JSON.stringify({ days }) },
      token
    ),

  revokeReportShare: (token: string, id: number) =>
    request<Report>(`/api/v1/company/reports/${id}/revoke_share`, { method: 'POST' }, token),

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
    request<{
      settings: Record<string, unknown>;
      company: {
        display_name: string;
        locale: string;
        website_url?: string | null;
        company_profile?: CompanyProfile;
        known_systems?: string[];
      };
    }>(
      '/api/v1/company/settings/organization',
      {},
      token
    ),

  updateCompanySettings: (
    token: string,
    payload: {
      display_name?: string;
      locale?: string;
      website_url?: string | null;
      engagement_mode?: string;
      department_targets?: Record<string, number>;
      company_profile?: CompanyProfile;
      known_systems?: string[];
      consultant_can_contact_employees?: boolean;
    }
  ) =>
    request<{ ok: boolean; settings?: Record<string, unknown>; company_profile?: CompanyProfile; website_url?: string | null }>(
      '/api/v1/company/settings/organization',
      { method: 'PATCH', body: JSON.stringify(payload) },
      token
    ),

  refreshCompanyWebResearch: (token: string) =>
    request<{ ok: boolean; queued?: boolean }>('/api/v1/company/settings/organization/web_research', { method: 'POST' }, token),

  companySettingsSecurity: (token: string) =>
    request<{ security_snapshot: Record<string, unknown> }>(
      '/api/v1/company/settings/security',
      {},
      token
    ),

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

  platformDashboard: (token: string) => request<PlatformDashboardPayload>('/api/v1/platform/dashboard', {}, token),

  platformPendingReports: (token: string) =>
    request<{ reports: PlatformApprovalRow[] }>('/api/v1/platform/reports/pending', {}, token),

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

  platformConsultants: (token: string) => request<{ consultants: ConsultantUser[] }>('/api/v1/platform/consultants', {}, token),

  platformConsultant: (token: string, id: number) =>
    request<{ consultant: ConsultantUser }>(`/api/v1/platform/consultants/${id}`, {}, token),

  platformConsultantCvUrl: async (token: string, id: number) => {
    const res = await fetch(`${API_URL}/api/v1/platform/consultants/${id}/cv`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) throw new Error(res.status === 404 ? 'No CV on file' : 'Could not load CV');
    return URL.createObjectURL(await res.blob());
  },

  createPlatformConsultant: (token: string, payload: { email: string; name: string; password: string }) =>
    request<{ consultant: ConsultantUser }>('/api/v1/platform/consultants', { method: 'POST', body: JSON.stringify({ consultant: payload }) }, token),

  companyConsultantAssignments: (token: string, companyId: number) =>
    request<{ assignments: ConsultantAssignment[]; active_count: number }>(
      `/api/v1/platform/companies/${companyId}/consultant_assignments`,
      {},
      token
    ),

  assignConsultant: (token: string, companyId: number, consultantUserId: number) =>
    request<{ assignment: ConsultantAssignment }>(
      `/api/v1/platform/companies/${companyId}/consultant_assignments`,
      { method: 'POST', body: JSON.stringify({ consultant_user_id: consultantUserId }) },
      token
    ),

  removeConsultantAssignment: (token: string, companyId: number, assignmentId: number) =>
    request<void>(`/api/v1/platform/companies/${companyId}/consultant_assignments/${assignmentId}`, { method: 'DELETE' }, token),

  consultantProfile: (token: string) =>
    request<{
      ok: boolean;
      user: { id: number; email: string; name: string };
      profile: ConsultantProfile;
      questionnaire_answers?: Record<string, unknown>;
      questionnaire_step?: number;
      questionnaire_completed_at?: string | null;
      completion_percent?: number;
      section_status?: Record<string, { touched: boolean; complete: boolean }>;
    }>('/api/v1/consultant/profile', {}, token),

  updateConsultantProfile: (
    token: string,
    payload: Partial<ConsultantProfilePayload> & { name?: string; email?: string; password?: string; publish?: boolean }
  ) =>
    request<{ ok: boolean; user: { id: number; email: string; name: string }; profile: ConsultantProfile }>(
      '/api/v1/consultant/profile',
      { method: 'PATCH', body: JSON.stringify(payload) },
      token
    ),

  updateConsultantQuestionnaire: (
    token: string,
    payload: {
      questionnaire_answers: Record<string, unknown>;
      questionnaire_step?: number;
    }
  ) =>
    request<{
      ok: boolean;
      user: { id: number; email: string; name: string };
      profile: ConsultantProfile;
      questionnaire_answers: Record<string, unknown>;
      questionnaire_step: number;
      completion_percent: number;
      section_status?: Record<string, { touched: boolean; complete: boolean }>;
    }>('/api/v1/consultant/profile/questionnaire', { method: 'PATCH', body: JSON.stringify(payload) }, token),

  uploadConsultantAvatar: async (token: string, file: File) => {
    const headers: Record<string, string> = {};
    if (token) headers['Authorization'] = `Bearer ${token}`;
    const body = new FormData();
    body.append('file', file);
    const res = await fetch(`${API_URL}/api/v1/consultant/profile/avatar`, { method: 'POST', headers, body });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = (data as ApiError).error || res.statusText;
      throw new Error(err);
    }
    return data as {
      ok: boolean;
      user: { id: number; email: string; name: string };
      profile: ConsultantProfile;
      completion_percent?: number;
    };
  },

  /** Avatar endpoint requires Authorization — use blob URL for <img>, not raw avatar_url. */
  fetchConsultantAvatarPreview: async (token: string, avatarUrl: string) => {
    const path = avatarUrl.startsWith('http') ? avatarUrl : `${API_URL}${avatarUrl}`;
    const res = await fetch(path, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) throw new Error('Could not load photo');
    return URL.createObjectURL(await res.blob());
  },

  uploadConsultantCv: async (token: string, file: File) => {
    const headers: Record<string, string> = {};
    if (token) headers['Authorization'] = `Bearer ${token}`;
    const body = new FormData();
    body.append('file', file);
    const res = await fetch(`${API_URL}/api/v1/consultant/profile/cv`, { method: 'POST', headers, body });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      const err = (data as ApiError).error || res.statusText;
      throw new Error(err);
    }
    return data as {
      ok: boolean;
      user: { id: number; email: string; name: string };
      profile: ConsultantProfile;
      completion_percent?: number;
    };
  },

  companyExpertConsultants: (token: string) =>
    request<{ expert_consultants: ConsultantPublicCard[] }>('/api/v1/company/expert_consultants', {}, token),

  consultantDashboard: (token: string) => request<ConsultantDashboardPayload>('/api/v1/consultant/dashboard', {}, token),

  consultantCompany: (token: string, id: number) => request<{ company: ConsultantCompanyDetail }>(`/api/v1/consultant/companies/${id}`, {}, token),

  consultantEmployees: (token: string, companyId: number) =>
    request<{ employees: Employee[] }>(`/api/v1/consultant/companies/${companyId}/employees`, {}, token),

  consultantReportWorkspace: (token: string, companyId: number, reportId: number) =>
    request<ConsultantReportWorkspacePayload>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/workspace`,
      {},
      token
    ),

  // --- Discovery handover: the consultant amends it and states what they need ---

  amendDiscoveryPackage: (
    token: string,
    packageId: number,
    payload: { recommendation?: string; recommendation_rationale?: string }
  ) =>
    request<{ discovery_package: DiscoveryPackage }>(
      `/api/v1/consultant/discovery_packages/${packageId}`,
      { method: 'PATCH', body: JSON.stringify(payload) },
      token
    ),

  createDiscoveryPackageItem: (
    token: string,
    packageId: number,
    payload: { kind: 'issue' | 'solution'; title?: string; body: string; impact?: string }
  ) =>
    request<{ item: DiscoveryPackageItem }>(
      `/api/v1/consultant/discovery_packages/${packageId}/items`,
      { method: 'POST', body: JSON.stringify(payload) },
      token
    ),

  updateDiscoveryPackageItem: (
    token: string,
    packageId: number,
    itemId: number,
    payload: { title?: string; body?: string; impact?: string; status?: string }
  ) =>
    request<{ item: DiscoveryPackageItem }>(
      `/api/v1/consultant/discovery_packages/${packageId}/items/${itemId}`,
      { method: 'PATCH', body: JSON.stringify(payload) },
      token
    ),

  /** States what the consultant needs to know. The agent drafts the questions. */
  createConsultantRequirement: (token: string, packageId: number, statement: string) =>
    request<{ requirement: ConsultantRequirement }>(
      `/api/v1/consultant/discovery_packages/${packageId}/requirements`,
      { method: 'POST', body: JSON.stringify({ statement }) },
      token
    ),

  updateConsultantRequirement: (
    token: string,
    packageId: number,
    requirementId: number,
    status: 'satisfied' | 'withdrawn'
  ) =>
    request<{ requirement: ConsultantRequirement }>(
      `/api/v1/consultant/discovery_packages/${packageId}/requirements/${requirementId}`,
      { method: 'PATCH', body: JSON.stringify({ status }) },
      token
    ),

  /** Reorder or skip a drafted question — its text is the agent's to write. */
  updateDiscoveryFollowupQuestion: (
    token: string,
    packageId: number,
    questionId: number,
    payload: { queue_position?: number; status?: 'drafted' | 'queued' | 'skipped' }
  ) =>
    request<{ question: DiscoveryFollowupQuestion }>(
      `/api/v1/consultant/discovery_packages/${packageId}/followup_questions/${questionId}`,
      { method: 'PATCH', body: JSON.stringify(payload) },
      token
    ),

  sendDiscoveryFollowupQuestion: (token: string, packageId: number, questionId: number) =>
    request<{ question: DiscoveryFollowupQuestion }>(
      `/api/v1/consultant/discovery_packages/${packageId}/followup_questions/${questionId}/send`,
      { method: 'POST' },
      token
    ),

  updateConsultantReportReview: (
    token: string,
    companyId: number,
    reportId: number,
    payload: {
      status?: string;
      overall_note?: string;
      opportunity_amount?: number | null;
      opportunity_unit?: string | null;
      opportunity_basis?: string | null;
    },
  ) =>
    request<ReportReviewPayload>(`/api/v1/consultant/companies/${companyId}/reports/${reportId}/review`, { method: 'PATCH', body: JSON.stringify(payload) }, token),

  submitConsultantReportReview: (token: string, companyId: number, reportId: number) =>
    request<ReportReviewPayload>(`/api/v1/consultant/companies/${companyId}/reports/${reportId}/review/submit`, { method: 'POST' }, token),

  updateSectionState: (token: string, companyId: number, reportId: number, sectionKey: string, status: string) =>
    request<{ section_state: { section_key: string; status: string } }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/review/section_states/${sectionKey}`,
      { method: 'PATCH', body: JSON.stringify({ status }) },
      token
    ),

  consultantSectionOverrides: (token: string, companyId: number, reportId: number) =>
    request<{ built_in_sections: string[]; overrides: ReportSectionOverride[] }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/section_overrides`,
      {},
      token
    ),

  createConsultantSectionOverride: (
    token: string,
    companyId: number,
    reportId: number,
    payload: SectionOverrideInput
  ) =>
    request<{ override: ReportSectionOverride }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/section_overrides`,
      { method: 'POST', body: JSON.stringify({ section_override: payload }) },
      token
    ),

  updateConsultantSectionOverride: (
    token: string,
    companyId: number,
    reportId: number,
    id: number,
    payload: SectionOverrideInput
  ) =>
    request<{ override: ReportSectionOverride }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/section_overrides/${id}`,
      { method: 'PATCH', body: JSON.stringify({ section_override: payload }) },
      token
    ),

  deleteConsultantSectionOverride: (token: string, companyId: number, reportId: number, id: number) =>
    request<void>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/section_overrides/${id}`,
      { method: 'DELETE' },
      token
    ),

  addReviewComment: (token: string, companyId: number, reportId: number, comment: { section_key: string; body: string }) =>
    request<{ comment: ReviewCommentPayload }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/review/comments`,
      { method: 'POST', body: JSON.stringify({ comment }) },
      token
    ),

  updateReviewComment: (
    token: string,
    companyId: number,
    reportId: number,
    commentId: number,
    comment: { body?: string; resolved?: boolean }
  ) =>
    request<{ comment: ReviewCommentPayload }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/review/comments/${commentId}`,
      { method: 'PATCH', body: JSON.stringify({ comment }) },
      token
    ),

  deleteReviewComment: (token: string, companyId: number, reportId: number, commentId: number) =>
    request<void>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/review/comments/${commentId}`,
      { method: 'DELETE' },
      token
    ),

  consultantReviewSync: (token: string, companyId: number, reportId: number, since?: string) => {
    const qs = new URLSearchParams({ report_id: String(reportId) });
    if (since) qs.set('since', since);
    return request<ConsultantReviewSyncPayload>(
      `/api/v1/consultant/companies/${companyId}/review_sync?${qs}`,
      {},
      token
    );
  },

  consultantConversations: (token: string, companyId: number) =>
    request<{
      conversations: {
        id: number;
        employee_id: number;
        employee_name: string | null;
        status: string;
        question_count: number;
        last_activity_at: string | null;
      }[];
    }>(
      `/api/v1/consultant/companies/${companyId}/conversations`,
      {},
      token
    ),

  consultantSignals: (token: string, companyId: number) =>
    request<{ signals: CompanySignal[] }>(`/api/v1/consultant/companies/${companyId}/signals`, {}, token),

  consultantPatterns: (token: string, companyId: number) =>
    request<{ patterns: CompanyPattern[] }>(`/api/v1/consultant/companies/${companyId}/patterns`, {}, token),

  consultantRecommendations: (token: string, companyId: number) =>
    request<{ recommendations: Recommendation[] }>(`/api/v1/consultant/companies/${companyId}/recommendations`, {}, token),

  consultantFollowups: (token: string) =>
    request<{ followups: ConsultantFollowupRow[] }>('/api/v1/consultant/followups', {}, token),

  consultantNotifications: (token: string, params?: { page?: number; per_page?: number }) => {
    const search = new URLSearchParams();
    if (params?.page) search.set('page', String(params.page));
    if (params?.per_page) search.set('per_page', String(params.per_page));
    const qs = search.toString();
    return request<{ notifications: AppNotification[]; unread_count: number; page: number; per_page: number }>(
      `/api/v1/consultant/notifications${qs ? `?${qs}` : ''}`,
      {},
      token
    );
  },

  markConsultantNotificationRead: (token: string, id: number) =>
    request<{ notification: AppNotification }>(`/api/v1/consultant/notifications/${id}`, { method: 'PATCH' }, token),

  markAllConsultantNotificationsRead: (token: string) =>
    request<{ ok: boolean; unread_count: number }>('/api/v1/consultant/notifications/mark_all_read', { method: 'POST' }, token),

  consultantConversation: (token: string, companyId: number, conversationId: number) =>
    request<{
      conversation: { id: number; employee_id: number; status: string; discovery_state?: DiscoveryState };
      discovery_provenance: DiscoveryProvenanceEntry[];
      messages: CompanyConversationMessage[];
      media_attachments: MediaAttachment[];
    }>(
      `/api/v1/consultant/companies/${companyId}/conversations/${conversationId}`,
      {},
      token
    ),

  consultantFollowupThread: (token: string, companyId: number, employeeId: number) =>
    request<{
      employee: { id: number; display_name: string | null };
      threads: {
        id: number;
        body: string;
        status: string;
        sent_at: string | null;
        replies: { body: string; received_at: string }[];
      }[];
    }>(`/api/v1/consultant/companies/${companyId}/employees/${employeeId}/followup`, {}, token),

  sendConsultantFollowup: (token: string, companyId: number, employeeId: number, body: string, reportId?: number) =>
    request<{ info_request: { id: number } }>(
      `/api/v1/consultant/companies/${companyId}/employees/${employeeId}/followup`,
      { method: 'POST', body: JSON.stringify({ body, report_id: reportId }) },
      token
    ),

  consultantChatMessages: (token: string, companyId: number) =>
    request<{ messages: { id: number; body: string; sender_name: string; created_at: string; mine: boolean }[] }>(
      `/api/v1/consultant/companies/${companyId}/chat_messages`,
      {},
      token
    ),

  sendConsultantChat: (token: string, companyId: number, body: string) =>
    request<{ message: { id: number } }>(
      `/api/v1/consultant/companies/${companyId}/chat_messages`,
      { method: 'POST', body: JSON.stringify({ body }) },
      token
    ),

  createReviewDiscussion: (
    token: string,
    companyId: number,
    reportId: number,
    payload: {
      target_type: 'consultant' | 'employee';
      target_consultant_user_id?: number;
      employee_id?: number;
      conversation_id?: number;
      anchor_type: 'message' | 'finding' | 'section';
      anchor_id: string;
      body: string;
      message_id?: number;
    }
  ) =>
    request<{ discussion: ReviewDiscussion }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/discussions`,
      { method: 'POST', body: JSON.stringify(payload) },
      token
    ),

  consultantDiscussions: (token: string, companyId: number, reportId: number) =>
    request<{ discussions: ReviewDiscussion[] }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/discussions`,
      {},
      token
    ),

  replyReviewDiscussion: (token: string, companyId: number, reportId: number, discussionId: number, body: string) =>
    request<{ discussion: ReviewDiscussion }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/discussions/${discussionId}/reply`,
      { method: 'POST', body: JSON.stringify({ body }) },
      token
    ),

  resolveReviewDiscussion: (token: string, companyId: number, reportId: number, discussionId: number) =>
    request<{ discussion: ReviewDiscussion }>(
      `/api/v1/consultant/companies/${companyId}/reports/${reportId}/discussions/${discussionId}/resolve`,
      { method: 'PATCH' },
      token
    ),
};

export interface ConsultantProfileCompleteness {
  percent: number;
  complete: boolean;
  missing: string[];
  checks: Record<string, boolean>;
  questionnaire_percent?: number;
}

export interface ConsultantExperience {
  id?: number;
  organization: string;
  title: string;
  start_year: number;
  end_year?: number | null;
  summary?: string | null;
  sort_order?: number;
}

export interface ConsultantProfile {
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
  cv_url?: string | null;
  has_cv?: boolean;
  verification_signals?: boolean;
  experiences: ConsultantExperience[];
  completeness: ConsultantProfileCompleteness;
  suggested_expertise_tags: string[];
}

export interface ConsultantProfilePayload {
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
  experiences?: ConsultantExperience[];
}

export interface ConsultantPublicCard {
  id: number;
  name: string;
  headline: string | null;
  bio?: string | null;
  avatar_url: string | null;
  expertise_tags: string[];
  industries: string[];
  years_experience: number | null;
  languages: string[];
  location: string | null;
  linkedin_url: string | null;
  profile_status: string;
  platform_verified: boolean;
  experiences?: ConsultantExperience[];
}

export interface ConsultantUser {
  id: number;
  email: string;
  name: string;
  status: string;
  profile_status?: string;
  profile_completeness_percent?: number;
  headline?: string | null;
  expertise_tags?: string[];
  avatar_url?: string | null;
  has_cv?: boolean;
  profile?: ConsultantProfile;
  public_card?: ConsultantPublicCard;
  assignments?: { company_id: number; company_name: string }[];
}

export interface ConsultantAssignment {
  id: number;
  status: string;
  assigned_at: string;
  consultant_user: ConsultantUser;
}

export interface ConsultantCompanySummary {
  id: number;
  name: string;
  report_readiness_score: number;
  completed_count: number;
  invited_count: number;
}

export interface ConsultantCompanyDetail extends ConsultantCompanySummary {
  participation: {
    invited?: number;
    started?: number;
    completed?: number;
    completion_rate?: number;
  } & Record<string, unknown>;
  completion_rate?: number;
  ready_documents?: number;
  latest_report: { id: number; version: number; status: string } | null;
  my_review_status: string | null;
  co_consultant_count: number;
  review_pending?: boolean;
  company_admins?: { id: number; name: string; email: string }[];
  website_url?: string | null;
  company_profile?: CompanyProfile;
  company_systems?: { name: string; category?: string; source?: string; confidence?: number }[];
  web_research?: { id: number; title: string; content: string; url?: string; fetched_at?: string; confidence?: number }[];
  questionnaire_summary?: {
    industry?: string;
    size_band?: string;
    business_goals?: string | string[];
    org_departments?: string[];
    systems?: string[];
  };
}

export interface ConsultantReportDetail {
  id: number;
  version: number;
  status: string;
  report_snapshot: Record<string, unknown>;
  generated_at: string | null;
  storage_key?: boolean;
}

export interface ReviewCommentPayload {
  id: number;
  section_key: string;
  body: string;
  resolved: boolean;
  consultant_user_id: number;
  consultant_name?: string;
  created_at?: string;
}

export type SectionOverrideAction = 'hide' | 'edit' | 'add';

export interface ReportSectionOverride {
  id: number;
  action: SectionOverrideAction;
  section_key: string | null;
  anchor_section: string | null;
  title: string | null;
  body: string | null;
  position: number;
  published: boolean;
  consultant_name: string | null;
  editable: boolean;
}

export interface SectionOverrideInput {
  action: SectionOverrideAction;
  section_key?: string | null;
  anchor_section?: string | null;
  title?: string | null;
  body?: string | null;
  position?: number;
  published?: boolean;
}

export interface ConsultantReviewSyncPayload {
  synced_at: string;
  reviews: { consultant_user_id: number; status: string; submitted_at: string | null }[];
  comments: { id: number; section_key: string; body: string; consultant_user_id: number; updated_at: string }[];
  section_states: { consultant_user_id: number; section_key: string; status: string }[];
}

export interface ReportReviewPayload {
  review: {
    id: number;
    status: string;
    overall_note: string | null;
    opportunity_amount: number | null;
    opportunity_unit: string | null;
    opportunity_basis: string | null;
    submitted_at: string | null;
    section_states: { section_key: string; status: string }[];
    comments: ReviewCommentPayload[];
  };
  co_consultant_reviews: {
    consultant_user_id?: number;
    consultant_name: string;
    status: string;
    activity?: 'not_started' | 'discussing' | 'reviewing' | 'submitted';
    activity_detail?: string;
    chat_message_count?: number;
    comment_count?: number;
    sections_touched?: number;
    last_active_at?: string | null;
    section_states: { section_key: string; status: string }[];
    comments: { section_key: string; body: string }[];
  }[];
}

/** What Discovery hands the consultant when an interview finishes. */
export interface DiscoveryPackageItem {
  id: number;
  kind: 'issue' | 'solution';
  title: string | null;
  body: string;
  impact: 'low' | 'medium' | 'high' | null;
  origin: 'agent' | 'consultant';
  status: 'proposed' | 'accepted' | 'amended' | 'rejected';
  linked_item_id: number | null;
  ordinal: number;
}

export interface DiscoveryFollowupQuestion {
  id: number;
  body: string;
  rationale: string | null;
  status: 'drafted' | 'queued' | 'sent' | 'answered' | 'skipped' | 'superseded';
  queue_position: number;
  /** The interview parked this thread rather than drilling into it. */
  from_parked_aside: boolean;
  consultant_requirement_id: number | null;
  sent_at: string | null;
  answered_at: string | null;
}

export interface ConsultantRequirement {
  id: number;
  /** The consultant's own words. Never sent to the employee verbatim. */
  statement: string;
  status: 'open' | 'questions_drafted' | 'partially_satisfied' | 'satisfied' | 'withdrawn';
  max_questions: number;
  questions_asked: number;
  budget_remaining: number;
  /** What the agent thinks is still unanswered — why this is still open. */
  missing_aspects: string[];
  satisfaction_basis: 'agent_judged' | 'consultant_manual' | null;
  satisfied_at: string | null;
  consultant_name: string | null;
  created_at: string;
  question_ids: number[];
}

export interface DiscoveryPackage {
  id: number;
  version: number;
  status: 'generating' | 'ready' | 'consultant_reviewed' | 'failed' | 'superseded';
  recommendation: string | null;
  recommendation_rationale: string | null;
  confidence: number | null;
  generated_by: string | null;
  /** Assembled without a model: no solutions, and deliberately low confidence. */
  built_without_model: boolean;
  generated_at: string | null;
  error_message: string | null;
  issues: DiscoveryPackageItem[];
  solutions: DiscoveryPackageItem[];
  followup_questions: DiscoveryFollowupQuestion[];
  requirements: ConsultantRequirement[];
  /** How many more questions this employee can be asked, across all requirements. */
  followup_budget_remaining: number;
}

export interface ConsultantWorkspaceConversation {
  id: number;
  employee_id: number;
  employee_name: string | null;
  department: string | null;
  status: string;
  question_count: number;
  last_activity_at: string | null;
  discovery_state: DiscoveryState;
  discovery_package: DiscoveryPackage | null;
  discovery_provenance: DiscoveryProvenanceEntry[];
  messages: CompanyConversationMessage[];
  media_attachments: MediaAttachment[];
}

export interface ReviewDiscussion {
  id: number;
  parent_id: number | null;
  target_type: 'consultant' | 'employee';
  target_consultant_user_id: number | null;
  target_consultant_name: string | null;
  employee_id: number | null;
  conversation_id: number | null;
  anchor_type: 'message' | 'finding' | 'section';
  anchor_id: string;
  body: string;
  status: 'open' | 'resolved';
  author_consultant_user_id: number;
  author_name: string;
  created_at: string;
  replies: ReviewDiscussion[];
}

export interface ConsultantReportWorkspacePayload {
  company: { id: number; name: string };
  report: ConsultantReportDetail;
  review: ReportReviewPayload['review'];
  co_consultant_reviews: ReportReviewPayload['co_consultant_reviews'];
  discussions: ReviewDiscussion[];
  conversations: ConsultantWorkspaceConversation[];
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
  subscriptions: {
    by_status: Record<string, number>;
    active_trials?: number;
    trials_expiring_7d: number;
    at_conversation_limit: number;
  };
  discovery: { active_conversations: number; completed_employees: number; conversations_last_24h: number };
  multimodal?: {
    ready_attachments: number;
    processing_attachments: number;
    failed_attachments: number;
    attachments_last_24h: number;
    companies_with_multimodal_enabled: number;
    companies_with_media_indexing_enabled: number;
  };
  reports: { ready: number; awaiting_approval?: number; generating: number; failed: number };
  impersonations: { active_sessions: number; last_24h: number };
}

export interface PlatformApprovalRow {
  report: { id: number; version: number; generated_at: string | null };
  company: { id: number; name: string };
  has_consultant: boolean;
  blocked_needs_info: boolean;
}

export interface PlatformDashboardPayload {
  monitoring: PlatformMonitoring;
  system: PlatformSystemHealth;
  trials_expiring_soon: PlatformTrialRow[];
  reports_awaiting_approval: PlatformApprovalRow[];
}

export interface CompanyDashboardPayload {
  user: CompanyUser;
  company: {
    id: number;
    name: string;
    display_name: string | null;
    locale?: string;
    portal_onboarding_completed_at: string | null;
    report_readiness_score: number;
    completed_count: number;
    invited_count: number;
    onboarding_complete: boolean;
    engagement_mode?: string;
    docs_first_phase?: boolean;
  };
  snapshot: IntelligenceSnapshot;
  report_readiness_score: number;
  report_readiness_breakdown: Record<string, number>;
  engagement_mode?: string;
  docs_first_phase?: boolean;
  questionnaire_completed_at?: string | null;
  questionnaire_completion_percent?: number;
  usage: { conversations_used: number; conversation_limit: number | null; remaining: number | null; limit_reached: boolean };
  latest_report: Report | null;
  opportunity_estimate: {
    amount: number;
    unit: string | null;
    basis: string | null;
    consultant_name: string | null;
    report_version: number;
  } | null;
  employees_summary: {
    stalled_count: number;
    in_progress_count: number;
    can_nudge_count: number;
    stalled_employees: {
      id: number;
      display_name: string | null;
      department: string | null;
      last_active_at: string | null;
      can_nudge: boolean;
    }[];
  };
  intel_counts?: {
    total_documents: number;
    ready_documents: number;
    open_clarifications: number;
    signal_count: number;
    pattern_count: number;
    recommendation_count: number;
    systems_count: number;
  };
  impersonating: boolean;
  impersonation_expires_at: string | null;
  integrations?: {
    openai_configured: boolean;
    stripe_configured: boolean;
    gotenberg_ok: boolean;
    mocks_allowed: boolean;
  };
}

export interface ConsultantDashboardPayload {
  profile: { profile_completeness_percent: number; profile_status: string };
  stats: {
    assigned_companies: number;
    avg_readiness: number;
    total_completed: number;
    total_invited: number;
    pending_reviews: number;
    open_followups: number;
    total_ready_documents?: number;
  };
  attention_items: {
    company_id: number;
    company_name: string;
    report_id: number;
    report_version: number;
    review_status: string | null;
  }[];
  recent_followups: ConsultantFollowupRow[];
  companies: ConsultantCompanyDetail[];
  unread_count: number;
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

export interface CompanyProfile {
  industry?: string;
  sub_industry?: string;
  size_band?: string;
  region?: string;
  country?: string;
  annual_revenue_band?: string;
  business_goals?: string | string[];
  org_departments?: string[];
}

export interface IntelligenceSnapshot {
  participation: { invited: number; started: number; completed: number; completion_rate: number };
  department_coverage: { department: string; completed: number; target: number }[];
  top_pain_points: { id: number; label: string; strength: number; departments: string[]; signal_type: string }[];
  signal_count?: number;
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
  consultant_progress?: { consultant_name: string; status: string; submitted_at?: string | null }[];
  consultant_feedback?: {
    consultant_name: string;
    status: string;
    submitted_at?: string | null;
    overall_note?: string | null;
    comments: { id: number; section_key: string; body: string }[];
  }[];
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
  catalog_matches: { name: string; vendor?: string; url?: string; partnership_tier?: string; score?: number }[];
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
  first_party?: boolean;
  entity_type?: string;
  slug?: string | null;
  use_cases?: string[];
  capabilities?: string[];
  required_systems?: string[];
  industries?: string[];
  departments?: string[];
  published_at?: string | null;
}

export interface CompanySystemRow {
  id: number;
  name: string;
  category: string;
  source: string;
  confidence: number;
  active: boolean;
  notes?: string | null;
}

export interface AgenticIdea {
  id: number;
  company_id: number;
  title: string;
  summary?: string | null;
  system_fit?: string | null;
  value_time?: string | null;
  value_efficiency?: string | null;
  value_cost?: string | null;
  approx_timeline?: string | null;
  estimated_cost?: string | null;
  confidence: number;
  status: string;
  source: string;
  catalog_name?: string | null;
  solution_catalog_entry_id?: number | null;
  published_at?: string | null;
  created_at?: string;
  updated_at?: string;
}

export interface CompanyDocument {
  id: number;
  filename: string;
  department: string | null;
  document_type?: string | null;
  sensitivity?: string | null;
  consultant_visible?: boolean;
  source: string;
  status: string;
  content_type: string | null;
  byte_size: number;
  insights_preview: { summary?: string; workflows?: string[]; friction_points?: string[]; chunk_count?: number };
  processing_error: string | null;
  created_at: string;
  updated_at: string;
}

export interface DocumentAnalysisRun {
  id: number;
  run_kind: string;
  status: string;
  phase?: string | null;
  model_tier?: string | null;
  document_ids?: number[];
  summary?: Record<string, unknown>;
  counters?: Record<string, unknown>;
  error_message?: string | null;
  started_at?: string | null;
  finished_at?: string | null;
  created_at: string;
}

export interface DocumentAnalysisEvent {
  id: number;
  agent_name: string;
  event_type: string;
  phase?: string | null;
  message?: string | null;
  payload?: Record<string, unknown>;
  created_at: string;
}

export interface CompanyKnowledgeEntry {
  id: number;
  entry_type: string;
  title: string;
  content: string;
  confidence: number;
  department?: string | null;
  status: string;
  source_document_ids?: number[];
  analysis_run_id?: number | null;
  created_at: string;
  updated_at?: string;
}

export interface CompanyClarificationQuestion {
  id: number;
  body: string;
  status: string;
  answer?: string | null;
  answer_source?: string | null;
  citations?: unknown[];
  answered_at?: string | null;
  dismissed_at?: string | null;
  analysis_run_id?: number | null;
  created_at: string;
  updated_at?: string;
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
  approval_status?: string;
  subscription: { plan: string; status: string; trial_ends_at: string | null } | null;
  created_at: string;
}

export interface CompanyRegistrationRow {
  id: number;
  status: string;
  company_name: string;
  admin_name: string;
  admin_email: string;
  admin_phone?: string | null;
  role_title?: string | null;
  notes?: string | null;
  review_note?: string | null;
  company_id: number;
  company_approval_status?: string;
  admin_user_status?: string;
  company_profile?: CompanyProfile;
  engagement_mode?: string;
  created_at: string;
  reviewed_at?: string | null;
}

export interface ConsultantApplicationRow {
  id: number;
  status: string;
  name: string;
  email: string;
  headline?: string | null;
  expertise_summary?: string | null;
  application_notes?: string | null;
  approved_at?: string | null;
  rejected_at?: string | null;
  created_at: string;
}

export interface CompanyDetail extends Company {
  settings: Record<string, unknown>;
  intelligence_snapshot: Record<string, unknown>;
  report_readiness_breakdown: Record<string, unknown>;
  onboarding_complete: boolean;
  completed_count?: number;
  invited_count?: number;
  company_profile?: Record<string, unknown>;
  questionnaire_answers?: Record<string, unknown>;
  questionnaire_step?: number;
  questionnaire_completed_at?: string | null;
  questionnaire_completion_percent?: number;
  company_users?: { id: number; email: string; name: string; role: string; status: string }[];
}

export interface CompanyUser {
  id: number;
  email: string;
  name: string;
  phone?: string | null;
  role: string;
  onboarding_completed_at: string | null;
}

export interface EmployeeNudge {
  id: number;
  channel: string;
  delivery_status: string;
  whatsapp_status: string | null;
  email_status: string | null;
  error_message: string | null;
  sent_at: string;
}

export interface EmployeeValuePreference {
  employee_id: number;
  email_opt_in: boolean;
  frequency: string;
  locale: string;
  interests: string[];
  unsubscribed_at: string | null;
  subscribed: boolean;
}

export interface EmployeeValueDigest {
  id: number;
  employee_id: number;
  period_key: string;
  status: string;
  delivery_status?: string | null;
  generated_at?: string | null;
  sent_at?: string | null;
  headline?: string | null;
  content?: Record<string, unknown>;
}

export interface Employee {
  id: number;
  phone_e164: string;
  email: string | null;
  preferred_channel?: string;
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
  can_nudge?: boolean;
  stalled?: boolean;
  invitation_status?: string;
  latest_nudge?: EmployeeNudge | null;
  recent_nudges?: EmployeeNudge[];
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

/** One thing the interview set out to learn, and how clearly it was answered. */
export interface DiscoverySlot {
  value: string;
  confidence: number;
  turn: number;
}

/** An aside the interview captured and moved on from, rather than drilling into. */
export interface DiscoveryParkedItem {
  note: string;
  turn: number;
  area: string;
}

export type DiscoveryCloseReason =
  | 'dossier_complete'
  | 'stalled'
  | 'ceiling'
  | 'employee_ended';

export interface DiscoveryState {
  profile: Record<string, unknown>;
  role_areas: { name: string }[];
  /** Keyed by slot name, or "slot::area" for per-area slots. */
  slots: Record<string, DiscoverySlot>;
  parked: DiscoveryParkedItem[];
  close_reason: DiscoveryCloseReason | null;
  stall_turns: number;
  shared_findings: { agent: string; finding: string; confidence: number; turn: number }[];
  conversation_summary: string | null;
  last_routing_decision:
    | { action: string; agent: string | null; reason: string; slot?: string | null; area?: string | null }
    | null;
}

export interface DiscoveryProvenanceEntry {
  message_id: number;
  agent_id: string | null;
  routing_decision: { action: string; agent: string | null; reason: string } | null;
  is_discovery_question: boolean;
  created_at: string;
  body_preview: string;
}

export interface CompanyConversationMessage {
  id: number;
  direction: string;
  message_type?: string;
  body: string;
  is_discovery_question?: boolean;
  consultant_followup?: boolean;
  agent_id?: string;
  routing_decision?: { action: string; agent: string | null; reason: string };
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

export interface ConsultantFollowupRow {
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
