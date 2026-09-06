import { createContext, useContext, useState, useCallback, type ReactNode } from 'react';

export type Portal = 'platform' | 'company' | 'consultant';

type PlatformSession = {
  portal: 'platform';
  token: string;
  user: { id: number; email: string; name: string; role: string };
};

export type CompanySession = {
  portal: 'company';
  token: string;
  user: { id: number; email: string; name: string; role: string; onboarding_completed_at: string | null };
  company: { id: number; name: string; display_name?: string | null; portal_onboarding_completed_at: string | null };
  impersonating?: boolean;
};

export type ConsultantSession = {
  portal: 'consultant';
  token: string;
  user: { id: number; email: string; name: string };
};

type Session = PlatformSession | CompanySession | ConsultantSession | null;

const AuthContext = createContext<{
  session: Session;
  setSession: (s: Session) => void;
  logout: () => void;
} | null>(null);

const STORAGE_KEY = 'req_app_session';
const PLATFORM_BACKUP_KEY = 'req_platform_session_backup';

/**
 * Sessions stored before the Reviewer -> Consultant rename carry
 * `portal: 'reviewer'`. Without this the portal never matches, and an already
 * signed-in consultant lands in a broken shell rather than being logged out
 * cleanly. Migrate on read and persist the corrected shape.
 *
 * Remove once no stored session predates the rename.
 */
function migrateStoredSession(parsed: unknown): Session {
  if (!parsed || typeof parsed !== 'object') return null;
  // The stored value is whatever an older build wrote, so read it as a loose
  // record rather than asserting it already matches the current Session union.
  const stored = parsed as Record<string, unknown>;
  if (stored.portal !== 'reviewer') return parsed as Session;

  const migrated = { ...stored, portal: 'consultant' } as unknown as ConsultantSession;
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(migrated));
  } catch {
    // A read-only store still lets this session work for the current tab.
  }
  return migrated;
}

function loadSession(): Session {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    return raw ? migrateStoredSession(JSON.parse(raw)) : null;
  } catch {
    return null;
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [session, setSessionState] = useState<Session>(loadSession);

  const setSession = useCallback((s: Session) => {
    if (s) localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
    else localStorage.removeItem(STORAGE_KEY);
    setSessionState(s);
  }, []);

  const logout = useCallback(() => setSession(null), [setSession]);

  return (
    <AuthContext.Provider value={{ session, setSession, logout }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}

export function usePlatformToken() {
  const { session } = useAuth();
  return session?.portal === 'platform' ? session.token : null;
}

export function useCompanyToken() {
  const { session } = useAuth();
  return session?.portal === 'company' ? session.token : null;
}

export function useConsultantToken() {
  const { session } = useAuth();
  return session?.portal === 'consultant' ? session.token : null;
}

export function startImpersonation(
  setSession: (s: Session) => void,
  platformSession: PlatformSession,
  impersonation: {
    token: string;
    user: CompanySession['user'];
    company: CompanySession['company'];
  }
) {
  localStorage.setItem(PLATFORM_BACKUP_KEY, JSON.stringify(platformSession));
  setSession({
    portal: 'company',
    token: impersonation.token,
    user: impersonation.user,
    company: impersonation.company,
    impersonating: true,
  });
}

export function endImpersonation(setSession: (s: Session) => void) {
  const raw = localStorage.getItem(PLATFORM_BACKUP_KEY);
  localStorage.removeItem(PLATFORM_BACKUP_KEY);
  if (raw) {
    setSession(JSON.parse(raw) as PlatformSession);
    return;
  }
  setSession(null);
}
