import { useCallback, useEffect, useRef, useState, type FormEvent } from 'react';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { ChatMessageList, type ChatMessageItem } from '../../components/motion';
import { Textarea, Button } from '../../components/ui';

export function ReviewerCoReviewerChatPanel({
  companyId,
  active,
  onMessagesLoaded,
}: {
  companyId: number;
  active: boolean;
  onMessagesLoaded?: (latestId: number | null) => void;
}) {
  const token = useReviewerToken();
  const [messages, setMessages] = useState<ChatMessageItem[]>([]);
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const onMessagesLoadedRef = useRef(onMessagesLoaded);

  useEffect(() => {
    onMessagesLoadedRef.current = onMessagesLoaded;
  }, [onMessagesLoaded]);

  const load = useCallback(async () => {
    if (!token || !companyId) return;
    try {
      const data = await api.reviewerChatMessages(token, companyId);
      const latestId = data.messages.length > 0 ? data.messages[data.messages.length - 1].id : null;
      setMessages(
        data.messages.map((m) => ({
          id: m.id,
          direction: m.mine ? 'outbound' : 'inbound',
          body: m.body,
          timestamp: m.created_at,
          meta: <p className="text-xs text-text-secondary">{m.sender_name}</p>,
        }))
      );
      onMessagesLoadedRef.current?.(latestId);
      setError('');
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to load chat');
    } finally {
      setLoading(false);
    }
  }, [token, companyId]);

  useEffect(() => {
    if (!token || !companyId) return;
    void load();
  }, [token, companyId, load]);

  useEffect(() => {
    if (!active || !token || !companyId) return;
    const interval = setInterval(() => {
      void load();
    }, 8000);
    return () => clearInterval(interval);
  }, [active, token, companyId, load]);

  const send = async (e: FormEvent) => {
    e.preventDefault();
    if (!token || !companyId || !body.trim()) return;
    setSending(true);
    try {
      await api.sendReviewerChat(token, companyId, body.trim());
      setBody('');
      await load();
    } finally {
      setSending(false);
    }
  };

  if (loading && messages.length === 0) {
    return <p className="text-sm text-muted-foreground">Loading chat…</p>;
  }

  return (
    <div className="flex h-full min-h-0 flex-col">
      {error && <p className="mb-3 text-sm text-destructive">{error}</p>}
      <ChatMessageList messages={messages} className="min-h-0 flex-1" showTyping={sending} />
      <form onSubmit={send} className="mt-4 shrink-0 space-y-3 border-t border-border pt-4">
        <Textarea
          rows={3}
          value={body}
          onChange={(e) => setBody(e.target.value)}
          placeholder="Message co-reviewers…"
        />
        <Button type="submit" disabled={!body.trim() || sending} loading={sending} className="w-full">
          Send
        </Button>
      </form>
    </div>
  );
}
