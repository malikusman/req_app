import { useEffect, useState, type FormEvent } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';

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

  if (loading) return <p>Loading…</p>;

  return (
    <div>
      <Link to={`/reviewer/companies/${companyId}/conversations`}>← Conversations</Link>
      <h1>Conversation</h1>
      <div className="card" style={{ maxHeight: 400, overflow: 'auto', marginBottom: '1rem' }}>
        {messages.map((m) => (
          <div
            key={m.id}
            style={{
              marginBottom: '0.75rem',
              textAlign: m.direction === 'outbound' ? 'right' : 'left',
              opacity: m.reviewer_followup ? 0.85 : 1,
            }}
          >
            <small style={{ color: '#64748b' }}>
              {m.direction}
              {m.reviewer_followup ? ' · reviewer follow-up' : ''} · {new Date(m.created_at).toLocaleString()}
            </small>
            <div>{m.body}</div>
          </div>
        ))}
      </div>
      {employeeId && (
        <form onSubmit={sendFollowup} className="card">
          <h3 style={{ marginTop: 0 }}>WhatsApp follow-up</h3>
          <textarea rows={3} style={{ width: '100%' }} value={followupBody} onChange={(e) => setFollowupBody(e.target.value)} />
          <button type="submit" className="btn btn-primary" style={{ marginTop: '0.5rem' }}>
            Send follow-up
          </button>
        </form>
      )}
    </div>
  );
}
