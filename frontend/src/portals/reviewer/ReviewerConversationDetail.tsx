import { useEffect, useState, type FormEvent } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, ChatBubble, Textarea, Button, Skeleton } from '../../components/ui';

export function ReviewerConversationDetail() {
  const { companyId, conversationId } = useParams();
  const token = useReviewerToken();
  const [messages, setMessages] = useState<
    { id: number; direction: string; body: string; reviewer_followup: boolean; created_at: string }[]
  >([]);
  const [employeeId, setEmployeeId] = useState<number | null>(null);
  const [followupBody, setFollowupBody] = useState('');
  const [loading, setLoading] = useState(true);

  const load = () => {
    if (!token || !companyId || !conversationId) return;
    api.reviewerConversation(token, Number(companyId), Number(conversationId)).then((d) => {
      setMessages(d.messages);
      setEmployeeId(d.conversation.employee_id ?? null);
    });
  };

  useEffect(() => {
    load();
    setLoading(false);
  }, [token, companyId, conversationId]);

  const sendFollowup = async (e: FormEvent) => {
    e.preventDefault();
    if (!token || !companyId || !employeeId || !followupBody.trim()) return;
    await api.sendReviewerFollowup(token, Number(companyId), employeeId, followupBody.trim());
    setFollowupBody('');
    load();
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Conversation"
        breadcrumbs={[
          { label: 'Company', href: `/reviewer/companies/${companyId}` },
          { label: 'Conversations', href: `/reviewer/companies/${companyId}/conversations` },
          { label: 'Transcript' },
        ]}
      />

      <Card>
        <div className="max-h-[480px] space-y-4 overflow-y-auto pr-2">
          {messages.map((m) => (
            <ChatBubble
              key={m.id}
              direction={m.direction === 'outbound' ? 'outbound' : 'inbound'}
              body={m.reviewer_followup ? `[Follow-up] ${m.body}` : m.body}
              timestamp={m.created_at}
            />
          ))}
        </div>
      </Card>

      {employeeId && (
        <Card title="WhatsApp follow-up">
          <form onSubmit={sendFollowup} className="space-y-4">
            <Textarea rows={4} value={followupBody} onChange={(e) => setFollowupBody(e.target.value)} />
            <Button type="submit" disabled={!followupBody.trim()}>
              Send follow-up
            </Button>
          </form>
        </Card>
      )}
    </div>
  );
}
