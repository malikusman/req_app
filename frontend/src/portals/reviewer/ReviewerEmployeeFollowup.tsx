import { useEffect, useState, type FormEvent } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { ChatMessageList, type ChatMessageItem } from '../../components/motion';
import { PageHeader, Card, Textarea, Button, Skeleton, EmptyState } from '../../components/ui';

export function ReviewerEmployeeFollowup() {
  const { companyId, employeeId } = useParams();
  const token = useReviewerToken();
  const [employeeName, setEmployeeName] = useState<string | null>(null);
  const [threads, setThreads] = useState<
    { id: number; body: string; status: string; replies: { body: string; received_at: string }[] }[]
  >([]);
  const [body, setBody] = useState('');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');

  const load = () => {
    if (!token || !companyId || !employeeId) return Promise.resolve();
    return api.reviewerFollowupThread(token, Number(companyId), Number(employeeId)).then((d) => {
      setEmployeeName(d.employee.display_name);
      setThreads(d.threads);
    });
  };

  useEffect(() => {
    if (!token || !companyId || !employeeId) return;
    setLoading(true);
    setError('');
    load()
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load thread'))
      .finally(() => setLoading(false));
  }, [token, companyId, employeeId]);

  const send = async (e: FormEvent) => {
    e.preventDefault();
    if (!token || !companyId || !employeeId || !body.trim()) return;
    setSending(true);
    try {
      await api.sendReviewerFollowup(token, Number(companyId), Number(employeeId), body.trim());
      setBody('');
      await load();
    } finally {
      setSending(false);
    }
  };

  function threadMessages(t: (typeof threads)[number]): ChatMessageItem[] {
    const items: ChatMessageItem[] = [
      {
        id: `out-${t.id}`,
        direction: 'outbound',
        body: t.body,
        timestamp: new Date().toISOString(),
      },
    ];
    t.replies.forEach((r, i) => {
      items.push({
        id: `in-${t.id}-${i}`,
        direction: 'inbound',
        body: r.body,
        timestamp: r.received_at,
      });
    });
    return items;
  }

  const displayName = employeeName || `Employee #${employeeId}`;

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
        title={displayName}
        description="WhatsApp follow-up thread"
        breadcrumbs={[
          { label: 'Follow-ups', href: '/reviewer/followups' },
          { label: displayName },
        ]}
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      {threads.length === 0 ? (
        <EmptyState title="No thread yet" description="Send a follow-up message to start the conversation." />
      ) : (
        threads.map((t) => (
          <Card key={t.id} title={`Thread · ${t.status}`}>
            <ChatMessageList messages={threadMessages(t)} className="max-h-[400px]" />
          </Card>
        ))
      )}

      <Card title="Send follow-up">
        <form onSubmit={send} className="space-y-4">
          <Textarea rows={4} value={body} onChange={(e) => setBody(e.target.value)} placeholder="Your message…" />
          <Button type="submit" disabled={!body.trim() || sending} loading={sending}>
            Send via WhatsApp
          </Button>
        </form>
      </Card>

      {companyId && (
        <Link to={`/reviewer/companies/${companyId}`} className="text-sm font-medium text-accent hover:underline">
          ← Back to company
        </Link>
      )}
    </div>
  );
}
