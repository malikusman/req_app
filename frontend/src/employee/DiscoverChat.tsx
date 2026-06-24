import { useCallback, useEffect, useMemo, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { ChatMessageList, type ChatMessageItem } from '../components/motion';
import { Button, Card, Input } from '../components/ui';
import {
  clearDiscoverToken,
  discoverApi,
  getStoredDiscoverToken,
  type DiscoverState,
} from './discoverApi';

export function DiscoverChat() {
  const { token = '' } = useParams();
  const navigate = useNavigate();
  const jwt = getStoredDiscoverToken();
  const [messages, setMessages] = useState<ChatMessageItem[]>([]);
  const [state, setState] = useState<DiscoverState | null>(null);
  const [draft, setDraft] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);

  const load = useCallback(async () => {
    if (!jwt) return;
    const data = await discoverApi.messages(jwt);
    setMessages(
      data.messages.map((m) => ({
        id: m.id,
        direction: m.direction,
        body: m.body,
        timestamp: m.created_at,
      }))
    );
    setState(data.state);
  }, [jwt]);

  useEffect(() => {
    if (!jwt) {
      navigate(`/discover/${token}`, { replace: true });
      return;
    }

    load()
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load chat'))
      .finally(() => setLoading(false));
  }, [jwt, load, navigate, token]);

  const send = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!jwt || !draft.trim()) return;
    setError('');
    setSending(true);
    const text = draft.trim();
    setDraft('');
    try {
      const data = await discoverApi.sendMessage(jwt, text);
      setMessages(
        data.messages.map((m) => ({
          id: m.id,
          direction: m.direction,
          body: m.body,
          timestamp: m.created_at,
        }))
      );
      setState(data.state);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to send message');
      setDraft(text);
    } finally {
      setSending(false);
    }
  };

  const statusLabel = useMemo(() => {
    if (!state) return null;
    if (state.completed) return 'Interview complete — thank you!';
    if (state.conversation_status === 'discovery') return 'Discovery in progress';
    if (state.conversation_status === 'profiling') return 'Getting to know your role';
    if (state.onboarding_step === 'awaiting_consent') return 'Please review consent and reply YES to continue';
    return 'Getting started';
  }, [state]);

  if (loading) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-background">
        <p className="text-muted-foreground">Loading chat…</p>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <header className="border-b border-border px-4 py-3">
        <div className="mx-auto flex max-w-2xl items-center justify-between gap-3">
          <div>
            <h1 className="text-lg font-semibold text-foreground">Discovery interview</h1>
            {statusLabel && <p className="text-sm text-muted-foreground">{statusLabel}</p>}
          </div>
          <Button
            variant="ghost"
            size="sm"
            onClick={() => {
              clearDiscoverToken();
              navigate(`/discover/${token}`, { replace: true });
            }}
          >
            Sign out
          </Button>
        </div>
      </header>

      <main className="mx-auto flex w-full max-w-2xl flex-1 flex-col px-4 py-4">
        {error && <p className="mb-3 rounded-md bg-destructive/10 px-3 py-2 text-sm text-destructive">{error}</p>}

        <Card className="flex min-h-0 flex-1 flex-col p-4">
          <ChatMessageList
            messages={messages}
            className="min-h-[50vh] flex-1"
            showTyping={sending}
          />

          {!state?.completed && (
            <form onSubmit={send} className="mt-4 flex gap-2 border-t border-border pt-4">
              <Input
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                placeholder="Type your reply…"
                disabled={sending}
                className="flex-1"
              />
              <Button type="submit" disabled={sending || !draft.trim()}>
                Send
              </Button>
            </form>
          )}
        </Card>
      </main>
    </div>
  );
}
