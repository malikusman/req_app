import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { Button, Card, Textarea } from '../../components/ui';

const API_URL = import.meta.env.VITE_API_URL || '';

type OutreachPreview = {
  id: number;
  company_name: string;
  body: string;
  status: string;
  can_reply: boolean;
};

export function OutreachReplyPage() {
  const { token = '' } = useParams();
  const [outreach, setOutreach] = useState<OutreachPreview | null>(null);
  const [body, setBody] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    fetch(`${API_URL}/api/v1/public/outreach/${encodeURIComponent(token)}`)
      .then(async (res) => {
        const data = await res.json().catch(() => ({}));
        if (!res.ok) throw new Error(data.error || 'Clarification link is invalid or expired.');
        setOutreach(data.outreach as OutreachPreview);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load'))
      .finally(() => setLoading(false));
  }, [token]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!token || !body.trim()) return;
    setError('');
    setSubmitting(true);
    try {
      const res = await fetch(`${API_URL}/api/v1/public/outreach/${encodeURIComponent(token)}/reply`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ body: body.trim() }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(data.error || 'Could not send reply');
      setSubmitted(true);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not send reply');
    } finally {
      setSubmitting(false);
    }
  };

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4">
        <p className="text-muted-foreground">Loading clarification…</p>
      </div>
    );
  }

  if (submitted) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background px-4 py-10">
        <Card className="w-full max-w-lg space-y-3 p-6 text-center">
          <h1 className="text-xl font-semibold text-foreground">Reply received</h1>
          <p className="text-sm text-muted-foreground">
            Thanks — your clarification was sent to the reviewer team for {outreach?.company_name || 'your company'}.
          </p>
        </Card>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4 py-10">
      <Card className="w-full max-w-lg space-y-6 p-6">
        <div className="space-y-2">
          <p className="text-sm uppercase tracking-wide text-muted-foreground">Clarification reply</p>
          <h1 className="text-2xl font-semibold text-foreground">{outreach?.company_name || 'Worktruth'}</h1>
          <p className="text-sm text-muted-foreground">
            A reviewer asked for more detail. Your reply is recorded securely via this link.
          </p>
        </div>

        {error && <p className="rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">{error}</p>}

        {outreach && (
          <div className="rounded-md border border-border bg-muted/30 p-3 text-sm">
            <div className="mb-1 text-xs uppercase tracking-wide text-muted-foreground">Request</div>
            <p className="m-0 whitespace-pre-wrap text-foreground">{outreach.body}</p>
          </div>
        )}

        {outreach?.can_reply === false ? (
          <p className="text-sm text-muted-foreground">This clarification is closed and no longer accepts replies.</p>
        ) : (
          <form onSubmit={submit} className="space-y-4">
            <Textarea
              label="Your reply"
              rows={6}
              value={body}
              onChange={(e: React.ChangeEvent<HTMLTextAreaElement>) => setBody(e.target.value)}
              placeholder="Share the details the reviewer asked for…"
              required
            />
            <Button type="submit" loading={submitting} disabled={!body.trim()}>
              Send reply
            </Button>
          </form>
        )}
      </Card>
    </div>
  );
}
