import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Button, Card } from '../components/ui';
import {
  discoverApi,
  getStoredDiscoverToken,
  storeDiscoverToken,
  type DiscoverSession,
} from './discoverApi';

export function DiscoverLanding() {
  const { token = '' } = useParams();
  const navigate = useNavigate();
  const [session, setSession] = useState<DiscoverSession | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);

  useEffect(() => {
    if (!token) return;
    const existing = getStoredDiscoverToken();
    if (existing) {
      navigate(`/discover/${token}/chat`, { replace: true });
      return;
    }

    discoverApi
      .session(token)
      .then(setSession)
      .catch(() => setError('This discovery link is invalid or has expired.'))
      .finally(() => setLoading(false));
  }, [token, navigate]);

  const start = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token) return;
    setError('');
    setSubmitting(true);
    try {
      const res = await discoverApi.start(token);
      storeDiscoverToken(res.token);
      navigate(`/discover/${token}/chat`, { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start interview');
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <p className="text-muted-foreground">Loading…</p>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4 py-10">
      <Card className="w-full max-w-md space-y-6 p-6">
        <div className="space-y-2 text-center">
          <p className="text-sm uppercase tracking-wide text-muted-foreground">Workflow discovery</p>
          <h1 className="text-2xl font-semibold text-foreground">
            {session?.company_name || 'Your company'}
          </h1>
          {session?.employee_name && (
            <p className="text-muted-foreground">Hi {session.employee_name}, continue to start your interview.</p>
          )}
        </div>

        {error && <p className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">{error}</p>}

        <form onSubmit={start} className="space-y-4">
          <Button type="submit" className="w-full" disabled={submitting || !!error && !session}>
            {submitting ? 'Starting…' : 'Continue to interview'}
          </Button>
        </form>

        {session?.expires_at && (
          <p className="text-center text-xs text-muted-foreground">
            Link expires {new Date(session.expires_at).toLocaleDateString()}
          </p>
        )}
      </Card>
    </div>
  );
}
