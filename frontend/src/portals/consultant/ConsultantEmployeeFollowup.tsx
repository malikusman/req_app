import { useEffect, useState, type FormEvent } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import { ChatMessageList, type ChatMessageItem } from '../../components/motion';
import { PageHeader, Card, Textarea, Button, Skeleton, EmptyState } from '../../components/ui';

export function ConsultantEmployeeFollowup() {
  const { companyId, employeeId } = useParams();
  const token = useConsultantToken();
  const [employeeName, setEmployeeName] = useState<string | null>(null);
  const [threads, setThreads] = useState<
    {
      id: number;
      body: string;
      status: string;
      sent_at: string | null;
      replies: { body: string; received_at: string }[];
    }[]
  >([]);
  const [body, setBody] = useState('');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');

  const load = () => {
    if (!token || !companyId || !employeeId) return Promise.resolve();
    return api.consultantFollowupThread(token, Number(companyId), Number(employeeId)).then((d) => {
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
      await api.sendConsultantFollowup(token, Number(companyId), Number(employeeId), body.trim());
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
        // sent_at is null while the outreach is still queued for company admin
        // approval — the API exposes no created_at, so fall back to "now" then.
        timestamp: t.sent_at ?? new Date().toISOString(),
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
          { label: 'Dashboard', href: '/consultant/dashboard' },
          { label: 'Company', href: `/consultant/companies/${companyId}` },
          { label: 'Inbox', href: '/consultant/inbox' },
          { label: displayName },
        ]}
      />

      {error && <p className="text-sm text-destructive">{error}</p>}

      {threads.length === 0 ? (
        <EmptyState title="No thread yet" description="Send a follow-up message to start the conversation." />
      ) : (
        threads.map((t) => (
          <Card key={t.id} title={`Thread · ${t.status}`}>
            <ChatMessageList messages={threadMessages(t)} className="max-h-[400px]" />
          </Card>
        ))
      )}

      {/* Kept as an explicit escape hatch, not the way to ask a question. Questions
          are drafted by the agent from what you state you need, in the report
          workspace — that is what lets the system tell when a need is settled. This
          box exists for everything else: acknowledging an answer, closing a loop. */}
      <Card title="Send a direct message">
        <form onSubmit={send} className="space-y-4">
          <p className="m-0 text-sm text-muted-foreground">
            For a direct note to {displayName} — a thank-you, or closing a loop. To{' '}
            <strong>ask something</strong>, open the report workspace and say what you need to know
            under the Discovery handover: the agent drafts the question and tracks whether your
            answer actually arrived.
          </p>
          <Textarea
            rows={4}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="A short note — not a question…"
          />
          <Button type="submit" disabled={!body.trim() || sending} loading={sending}>
            Send via WhatsApp
          </Button>
        </form>
      </Card>

      {companyId && (
        <Link to={`/consultant/companies/${companyId}`} className="text-sm font-medium text-accent hover:underline">
          ← Back to company
        </Link>
      )}
    </div>
  );
}
