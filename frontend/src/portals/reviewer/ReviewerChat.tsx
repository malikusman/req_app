import { useEffect, useState, type FormEvent } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, ChatBubble, Textarea, Button } from '../../components/ui';

export function ReviewerChat() {
  const { companyId } = useParams();
  const token = useReviewerToken();
  const [messages, setMessages] = useState<
    { id: number; body: string; sender_name: string; created_at: string; mine: boolean }[]
  >([]);
  const [body, setBody] = useState('');

  const load = () => {
    if (!token || !companyId) return;
    api.reviewerChatMessages(token, Number(companyId)).then((d) => setMessages(d.messages));
  };

  useEffect(() => {
    load();
    const t = setInterval(load, 8000);
    return () => clearInterval(t);
  }, [token, companyId]);

  const send = async (e: FormEvent) => {
    e.preventDefault();
    if (!token || !companyId || !body.trim()) return;
    await api.sendReviewerChat(token, Number(companyId), body.trim());
    setBody('');
    load();
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
        <div className="max-h-[400px] space-y-4 overflow-y-auto pr-2">
          {messages.map((m) => (
            <div key={m.id}>
              <p className="mb-1 text-xs text-text-secondary">{m.sender_name}</p>
              <ChatBubble direction={m.mine ? 'outbound' : 'inbound'} body={m.body} timestamp={m.created_at} />
            </div>
          ))}
        </div>
      </Card>

      <Card>
        <form onSubmit={send} className="space-y-4">
          <Textarea rows={3} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Message co-reviewers…" />
          <Button type="submit" disabled={!body.trim()}>
            Send
          </Button>
        </form>
      </Card>
    </div>
  );
}
