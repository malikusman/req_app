import { useEffect, useState, type FormEvent } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';

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
    <div>
      <Link to={`/reviewer/companies/${companyId}`}>← Company</Link>
      <h1>Co-reviewer chat</h1>
      <div className="card" style={{ maxHeight: 360, overflow: 'auto', marginBottom: '1rem' }}>
        {messages.map((m) => (
          <div key={m.id} style={{ marginBottom: '0.75rem', textAlign: m.mine ? 'right' : 'left' }}>
            <small style={{ color: '#64748b' }}>
              {m.sender_name} · {new Date(m.created_at).toLocaleString()}
            </small>
            <div>{m.body}</div>
          </div>
        ))}
      </div>
      <form onSubmit={send} className="card">
        <textarea rows={2} style={{ width: '100%' }} value={body} onChange={(e) => setBody(e.target.value)} />
        <button type="submit" className="btn btn-primary" style={{ marginTop: '0.5rem' }}>
          Send
        </button>
      </form>
    </div>
  );
}
