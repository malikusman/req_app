const API_URL = import.meta.env.VITE_API_URL || '';

export type DiscoverSession = {
  company_name: string;
  employee_name: string | null;
  expires_at: string;
  requires_verification: boolean;
};

export type DiscoverTrack =
  | 'onboarding'
  | 'profiling'
  | 'discovery'
  | 'companion'
  | 'consultant_followup';

export type DiscoverMessage = {
  id: number;
  direction: 'inbound' | 'outbound';
  message_type: string;
  body: string;
  is_discovery_question: boolean;
  /** Which thread the turn belongs to. Absent on responses from an older server. */
  track?: DiscoverTrack;
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

const STORAGE_KEY = 'req_discover_session';

/**
 * The interview session, kept against the invite link it belongs to.
 *
 * This was sessionStorage, which dies with the tab — and the server refuses to
 * verify an invite link twice ("This link was already used"). So an employee who
 * closed the tab mid-interview was locked out until an admin issued a new
 * invite, which is the opposite of the "answer when you have a moment" this is
 * sold as. localStorage survives that; the link stays single-use, so nothing
 * about who can start an interview changes.
 *
 * Keyed by link because localStorage is shared across tabs: without it, a second
 * employee opening their own invite on the same browser would be redirected
 * straight into the FIRST employee's conversation. Sign out still clears it, and
 * the JWT carries its own expiry.
 */
type StoredSession = { link: string; token: string };

function readSession(): StoredSession | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as StoredSession;
    return parsed?.link && parsed?.token ? parsed : null;
  } catch {
    // Private mode, cleared storage, or a value from an older shape.
    return null;
  }
}

export function getStoredDiscoverToken(link?: string): string | null {
  const session = readSession();
  if (!session) return null;
  if (link && session.link !== link) return null;
  return session.token;
}

export function storeDiscoverToken(link: string, token: string) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ link, token }));
  } catch {
    // Storage unavailable: the interview still works for this page load.
  }
}

export function clearDiscoverToken() {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {
    // Nothing to do — there is no session to forget.
  }
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
