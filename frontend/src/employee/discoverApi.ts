const API_URL = import.meta.env.VITE_API_URL || '';

export type DiscoverSession = {
  company_name: string;
  employee_name: string | null;
  expires_at: string;
  requires_verification: boolean;
};

export type DiscoverMessage = {
  id: number;
  direction: 'inbound' | 'outbound';
  message_type: string;
  body: string;
  is_discovery_question: boolean;
  created_at: string;
};

export type DiscoverState = {
  onboarding_step: string;
  participation_status: string;
  conversation_status: string;
  question_count: number;
  completed: boolean;
};

export type DiscoverVerifyResponse = {
  token: string;
  expires_at: string;
  employee: { id: number; display_name: string | null; onboarding_step: string; participation_status: string };
  conversation: { id: number; status: string; question_count: number };
  messages: DiscoverMessage[];
};

const STORAGE_KEY = 'req_discover_token';

export function getStoredDiscoverToken(): string | null {
  return sessionStorage.getItem(STORAGE_KEY);
}

export function storeDiscoverToken(token: string) {
  sessionStorage.setItem(STORAGE_KEY, token);
}

export function clearDiscoverToken() {
  sessionStorage.removeItem(STORAGE_KEY);
}

async function discoverRequest<T>(path: string, options: RequestInit = {}, token?: string | null): Promise<T> {
  const headers: Record<string, string> = {
    ...(options.headers as Record<string, string>),
  };
  const isFormData = typeof FormData !== 'undefined' && options.body instanceof FormData;
  if (!isFormData) {
    headers['Content-Type'] = 'application/json';
  }
  if (token) headers.Authorization = `Bearer ${token}`;

  const res = await fetch(`${API_URL}${path}`, { ...options, headers });
  const data = await res.json().catch(() => ({}));

  if (!res.ok) {
    const err = (data as { error?: string }).error || res.statusText;
    throw new Error(err);
  }
  return data as T;
}

export const discoverApi = {
  session: (linkToken: string) =>
    discoverRequest<DiscoverSession>(`/api/v1/public/discover/sessions/${encodeURIComponent(linkToken)}`),

  verify: (linkToken: string) =>
    discoverRequest<DiscoverVerifyResponse>(
      `/api/v1/public/discover/sessions/${encodeURIComponent(linkToken)}/verify`,
      { method: 'POST', body: JSON.stringify({}) }
    ),

  start: (linkToken: string) =>
    discoverRequest<DiscoverVerifyResponse>(
      `/api/v1/public/discover/sessions/${encodeURIComponent(linkToken)}/verify`,
      { method: 'POST', body: JSON.stringify({}) }
    ),

  messages: (jwt: string) =>
    discoverRequest<{ messages: DiscoverMessage[]; state: DiscoverState }>(
      '/api/v1/public/discover/messages',
      {},
      jwt
    ),

  sendMessage: (jwt: string, body: string) =>
    discoverRequest<{ messages: DiscoverMessage[]; state: DiscoverState }>(
      '/api/v1/public/discover/messages',
      { method: 'POST', body: JSON.stringify({ body }) },
      jwt
    ),

  sendAttachment: (jwt: string, file: File, caption?: string) => {
    const form = new FormData();
    form.append('file', file);
    if (caption?.trim()) form.append('caption', caption.trim());
    return discoverRequest<{ messages: DiscoverMessage[]; state: DiscoverState }>(
      '/api/v1/public/discover/attachments',
      { method: 'POST', body: form },
      jwt
    );
  },
};
