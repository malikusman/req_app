import { useAuth, endImpersonation } from '../lib/auth';

export function ImpersonationBanner() {
  const { session, setSession } = useAuth();

  if (session?.portal !== 'company' || !session.impersonating) return null;

  return (
    <div
      style={{
        background: '#fef3c7',
        color: '#92400e',
        padding: '0.5rem 1rem',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        borderBottom: '1px solid #fcd34d',
      }}
    >
      <span>
        Impersonating <strong>{session.company.name}</strong> as {session.user.name}
      </span>
      <button type="button" className="btn btn-secondary" onClick={() => endImpersonation(setSession)}>
        Exit to platform
      </button>
    </div>
  );
}
