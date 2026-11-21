import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Bot, Keyboard } from 'lucide-react';
import { Button, Card } from '../components/ui';
import { setReadAloudPreferred } from './useReadAloud';
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
  const [submitting, setSubmitting] = useState<'avatar' | 'text' | null>(null);
  // Scoped to this link: a colleague's session on the same browser must not drop
  // this person into that conversation. A returning employee chooses again.
  const resumable = Boolean(token && getStoredDiscoverToken(token));

  useEffect(() => {
    if (!token) return;
    discoverApi
      .session(token)
      .then(setSession)
      .catch(() => { if (!resumable) setError('This discovery link is invalid or has expired.'); })
      .finally(() => setLoading(false));
  }, [token, resumable]);

  // Both options run the same interview (Employee Discovery V2): the avatar adds a
  // face, a voice and automatic turn-taking; typing stays available either way.
  const start = async (mode: 'avatar' | 'text') => {
    if (!token) return;
    setError('');
    setSubmitting(mode);
    try {
      if (!getStoredDiscoverToken(token)) {
        const res = await discoverApi.start(token);
        storeDiscoverToken(token, res.token);
      }
      setReadAloudPreferred(false);
      navigate(`/discover/${token}/${mode === 'avatar' ? 'avatar' : 'chat'}`, { replace: true });
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not start interview');
    } finally {
      setSubmitting(null);
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

        <div className="space-y-3">
          <Button
            type="button"
            className="w-full"
            icon={<Bot className="h-4 w-4" />}
            disabled={!!submitting || (!!error && !session)}
            onClick={() => void start('avatar')}
            data-testid="start-avatar"
          >
            {submitting === 'avatar' ? 'Starting…' : 'Start with AI Avatar'}
          </Button>
          <Button
            type="button"
            variant="secondary"
            className="w-full"
            icon={<Keyboard className="h-4 w-4" />}
            disabled={!!submitting || (!!error && !session)}
            onClick={() => void start('text')}
          >
            {submitting === 'text' ? 'Starting…' : 'Start Text Interview'}
          </Button>
          <p className="m-0 text-center text-xs text-muted-foreground">
            With the AI avatar you talk naturally: it asks the questions out loud and listens to your answers. You can
            pause, or switch to typing, at any point. Your answers are saved as you go.
          </p>
        </div>

        {session?.expires_at && (
          <p className="text-center text-xs text-muted-foreground">
            Link expires {new Date(session.expires_at).toLocaleDateString()}
          </p>
        )}
      </Card>
    </div>
  );
}
