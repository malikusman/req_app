import { useEffect, useState, type FormEvent } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { ChatMessageList, type ChatMessageItem } from '../../components/motion';
import { PageHeader, Card, Textarea, Button } from '../../components/ui';

export function ReviewerChat() {
  const { companyId } = useParams();
  const token = useReviewerToken();
  const [messages, setMessages] = useState<ChatMessageItem[]>([]);
  const [body, setBody] = useState('');
  const [sending, setSending] = useState(false);

  const load = () => {
    if (!token || !companyId) return;
    api.reviewerChatMessages(token, Number(companyId)).then((d) =>
      setMessages(
        d.messages.map((m) => ({
          id: m.id,
          direction: m.mine ? 'outbound' : 'inbound',
          body: m.body,
          timestamp: m.created_at,
          meta: <p className="text-xs text-text-secondary">{m.sender_name}</p>,
        }))
      )
    );
  };

  useEffect(() => {
    load();
    const t = setInterval(load, 8000);
    return () => clearInterval(t);
  }, [token, companyId]);

  const send = async (e: FormEvent) => {
    e.preventDefault();
    if (!token || !companyId || !body.trim()) return;
    setSending(true);
    try {
      await api.sendReviewerChat(token, Number(companyId), body.trim());
      setBody('');
      load();
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Co-reviewer chat"
        description="Private channel with co-reviewers on this assignment."
        breadcrumbs={[
          { label: 'Company', href: `/reviewer/companies/${companyId}` },
          { label: 'Chat' },
        ]}
      />

      <Card>
        <ChatMessageList messages={messages} className="max-h-[400px]" showTyping={sending} />
      </Card>

      <Card>
        <form onSubmit={send} className="space-y-4">
          <Textarea rows={3} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Message co-reviewers…" />
          <Button type="submit" disabled={!body.trim() || sending} loading={sending}>
            Send
          </Button>
        </form>
      </Card>
    </div>
  );
}
