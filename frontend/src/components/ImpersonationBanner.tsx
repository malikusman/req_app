import { useAuth, endImpersonation } from '../lib/auth';
import { Button } from './ui';

export function ImpersonationBanner() {
  const { session, setSession } = useAuth();

  if (session?.portal !== 'company' || !session.impersonating) return null;

  return (
    <div className="flex items-center justify-between border-b border-amber-300 bg-amber-50 px-4 py-2 text-sm text-amber-900">
      <span>
        Impersonating <strong>{session.company.name}</strong> as {session.user.name}
      </span>
      <Button variant="secondary" size="sm" onClick={() => endImpersonation(setSession)}>
        Exit to platform
      </Button>
    </div>
  );
}
