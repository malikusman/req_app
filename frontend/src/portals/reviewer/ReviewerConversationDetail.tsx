import { useEffect, useState, type FormEvent } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { ChatMessageList, type ChatMessageItem } from '../../components/motion';
import { PageHeader, Card, Textarea, Button, Skeleton } from '../../components/ui';

export function ReviewerConversationDetail() {
  const { companyId, conversationId } = useParams();
  const token = useReviewerToken();
  const [messages, setMessages] = useState<ChatMessageItem[]>([]);
  const [employeeId, setEmployeeId] = useState<number | null>(null);
  const [followupBody, setFollowupBody] = useState('');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);

  const load = () => {
    if (!token || !companyId || !conversationId) return;
    api.reviewerConversation(token, Number(companyId), Number(conversationId)).then((d) => {
      setMessages(
        d.messages.map((m) => ({
          id: m.id,
          direction: m.direction === 'outbound' ? 'outbound' : 'inbound',
          body: m.reviewer_followup ? `[Follow-up] ${m.body}` : m.body,
          timestamp: m.created_at,
        }))
      );
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
    setSending(true);
    try {
      await api.sendReviewerFollowup(token, Number(companyId), employeeId, followupBody.trim());
      setFollowupBody('');
      load();
    } finally {
      setSending(false);
    }
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
        <ChatMessageList messages={messages} className="max-h-[480px]" showTyping={sending} />
      </Card>

      {employeeId && (
        <Card title="WhatsApp follow-up">
          <form onSubmit={sendFollowup} className="space-y-4">
            <Textarea rows={4} value={followupBody} onChange={(e) => setFollowupBody(e.target.value)} />
            <Button type="submit" disabled={!followupBody.trim() || sending} loading={sending}>
              Send follow-up
            </Button>
          </form>
        </Card>
      )}
    </div>
  );
}
