import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { MessageSquare } from 'lucide-react';
import { PageHeader, Card, DataTable, Badge, Button, Textarea, EmptyState, Modal } from '../../components/ui';
import { label } from '../../lib/labels';
import { Sheet, SheetContent, SheetHeader, SheetTitle } from '@/components/shadcn/sheet';
import { useMediaQuery } from '../../lib/useMediaQuery';

type Reply = {
  id: number;
  channel: string;
  body: string;
  received_at: string;
};

type Outreach = {
  id: number;
  status: string;
  purpose: string;
  channel: string;
  body: string;
  edited_body?: string | null;
  reason?: string;
  employee_id?: number;
  recipient_type?: string;
  recipient_name?: string | null;
  reviewer_name?: string;
  created_at: string;
  replies?: Reply[];
};

function statusVariant(status: string): 'info' | 'success' | 'warning' | 'error' | 'neutral' {
  if (status === 'pending_admin_approval') return 'info';
  if (status === 'sent' || status === 'replied') return 'success';
  if (status === 'closed') return 'neutral';
  if (status === 'declined' || status === 'failed') return 'error';
  return 'warning';
}

type PendingAction = { id: number; action: 'approve' | 'decline'; label: string };

export function CompanyOutreaches() {
  const token = useCompanyToken();
  const isNarrow = useMediaQuery('(max-width: 1023px)');
  const [outreaches, setOutreaches] = useState<Outreach[]>([]);
  const [selected, setSelected] = useState<Outreach | null>(null);
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [note, setNote] = useState('');
  const [answer, setAnswer] = useState('');
  const [loading, setLoading] = useState(true);
  const [actingId, setActingId] = useState<number | null>(null);
  const [error, setError] = useState('');
  const [loadError, setLoadError] = useState('');

  const load = () => {
    if (!token) return;
    setLoadError('');
    api
      .companyOutreaches(token)
      .then((d) => {
        const list = d.outreaches as Outreach[];
        setOutreaches(list);
        setSelected((prev) => (prev ? list.find((o) => o.id === prev.id) || null : null));
      })
      .catch(() => setLoadError('Could not load reviewer questions.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const openAction = (o: Outreach, action: 'approve' | 'decline') => {
    setPending({
      id: o.id,
      action,
      label: (o.edited_body || o.body).slice(0, 80) + ((o.edited_body || o.body).length > 80 ? '…' : ''),
    });
    setNote('');
    setError('');
  };

  const closeModal = () => {
    if (actingId != null) return;
    setPending(null);
    setNote('');
  };

  const confirmAction = async () => {
    if (!token || !pending) return;
    setActingId(pending.id);
    setError('');
    try {
      if (pending.action === 'approve') await api.approveOutreach(token, pending.id, { note: note || undefined });
      else await api.declineOutreach(token, pending.id, { note: note || undefined });
      setPending(null);
      setNote('');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Action failed');
    } finally {
      setActingId(null);
    }
  };

  const submitAnswer = async () => {
    if (!token || !selected || !answer.trim()) return;
    setActingId(selected.id);
    setError('');
    try {
      await api.answerOutreach(token, selected.id, { body: answer.trim() });
      setAnswer('');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Answer failed');
    } finally {
      setActingId(null);
    }
  };

  const canAnswer = selected && ['sent', 'replied', 'approved', 'queued'].includes(selected.status);

  const needsInput = outreaches.filter(
    (o) => o.status === 'pending_admin_approval' || (o.recipient_type === 'company_admin' && o.status === 'sent')
  ).length;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reviewer questions"
        description="Questions from your expert reviewer that sharpen your report."
      />

      {needsInput > 0 && (
        <div className="rounded-button border border-border bg-accent-muted px-4 py-3 text-sm text-foreground">
          {needsInput} {needsInput === 1 ? 'question needs' : 'questions need'} your input.
        </div>
      )}

      {error && !pending && <p className="text-sm text-status-error">{error}</p>}

      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      <div className="grid gap-4 lg:grid-cols-[1fr_360px]">
        <DataTable
          loading={loading}
          onRowClick={setSelected}
          columns={[
            {
              key: 'reviewer',
              header: 'Reviewer',
              render: (o: Outreach) => o.reviewer_name || '—',
            },
            {
              key: 'recipient',
              header: 'To',
              render: (o: Outreach) =>
                o.recipient_type === 'company_admin'
                  ? o.recipient_name || 'Company admin'
                  : o.recipient_name || (o.employee_id ? `Employee #${o.employee_id}` : '—'),
            },
            {
              key: 'body',
              header: 'Request',
              render: (o: Outreach) => (
                <span className="text-sm">
                  {(o.edited_body || o.body).slice(0, 120)}
                  {(o.edited_body || o.body).length > 120 ? '…' : ''}
                </span>
              ),
            },
            {
              key: 'status',
              header: 'Status',
              render: (o: Outreach) => <Badge variant={statusVariant(o.status)}>{label("outreachStatus", o.status)}</Badge>,
            },
            {
              key: 'actions',
              header: '',
              render: (o: Outreach) =>
                o.status === 'pending_admin_approval' ? (
                  <div className="flex flex-wrap gap-2" onClick={(e) => e.stopPropagation()}>
                    <Button size="sm" onClick={() => openAction(o, 'approve')}>
                      Approve
                    </Button>
                    <Button size="sm" variant="secondary" onClick={() => openAction(o, 'decline')}>
                      Decline
                    </Button>
                  </div>
                ) : o.recipient_type === 'company_admin' && o.status === 'sent' ? (
                  <span className="text-xs font-medium text-accent">Answer</span>
                ) : (
                  <span className="text-xs text-muted-foreground">{o.channel}</span>
                ),
            },
          ]}
          rows={outreaches}
          emptyState={
            <EmptyState
              icon={MessageSquare}
              title="No questions yet"
              description="When your reviewer needs something to sharpen your report, their question shows up here for you to answer."
            />
          }
        />

        <Card className="hidden lg:block" title="Thread">
          {!selected ? (
            <p className="text-sm text-text-secondary">Pick a question to read the thread and reply.</p>
          ) : (
            <div className="space-y-4 text-sm">
              <div>
                <div className="mb-1 flex items-center gap-2">
                  <Badge variant={statusVariant(selected.status)}>{label("outreachStatus", selected.status)}</Badge>
                  <span className="text-xs text-text-secondary">{selected.channel}</span>
                </div>
                <div className="font-medium">{selected.reviewer_name || 'Reviewer'}</div>
                {selected.recipient_name && (
                  <p className="mt-1 text-xs text-text-secondary">
                    To: {selected.recipient_name}
                    {selected.recipient_type === 'company_admin' ? ' (company admin)' : ''}
                  </p>
                )}
                <p className="mt-2 whitespace-pre-wrap text-text-primary">{selected.edited_body || selected.body}</p>
                {selected.reason && (
                  <p className="mt-2 text-xs text-text-secondary">Reason: {selected.reason}</p>
                )}
              </div>

              <div>
                <div className="mb-1 text-xs uppercase tracking-wide text-text-secondary">Replies</div>
                {(selected.replies || []).length === 0 ? (
                  <p className="text-xs text-text-secondary">No replies yet.</p>
                ) : (
                  <ul className="max-h-48 space-y-2 overflow-auto">
                    {(selected.replies || []).map((r) => (
                      <li key={r.id} className="rounded-md border border-border p-2 text-xs">
                        <div className="mb-1 text-text-secondary">
                          {r.channel} · {new Date(r.received_at).toLocaleString()}
                        </div>
                        <div className="whitespace-pre-wrap">{r.body}</div>
                      </li>
                    ))}
                  </ul>
                )}
              </div>

              {canAnswer ? (
                <div className="space-y-2">
                  <Textarea
                    label={selected.recipient_type === 'company_admin' ? 'Your answer' : 'Admin answer'}
                    rows={4}
                    value={answer}
                    onChange={(e) => setAnswer(e.target.value)}
                    placeholder="Answer this question for the reviewer…"
                  />
                  <Button size="sm" loading={actingId === selected.id} disabled={!answer.trim()} onClick={submitAnswer}>
                    Submit answer & close
                  </Button>
                </div>
              ) : (
                <p className="text-xs text-text-secondary">
                  {selected.status === 'pending_admin_approval'
                    ? 'Approve this request before your team is contacted.'
                    : selected.status === 'closed'
                      ? 'This question is closed.'
                      : 'You can’t answer a question with this status.'}
                </p>
              )}
            </div>
          )}
        </Card>

        <Sheet open={Boolean(selected) && isNarrow} onOpenChange={(open) => !open && setSelected(null)}>
          <SheetContent side="bottom" className="max-h-[85dvh] overflow-y-auto">
            <SheetHeader>
              <SheetTitle>Question thread</SheetTitle>
            </SheetHeader>
            {selected ? (
              <div className="mt-4 space-y-4 text-sm">
                <div>
                  <div className="mb-1 flex flex-wrap items-center gap-2">
                    <Badge variant={statusVariant(selected.status)}>{label("outreachStatus", selected.status)}</Badge>
                    <span className="text-xs text-text-secondary">{selected.channel}</span>
                  </div>
                  <div className="font-medium">{selected.reviewer_name || 'Reviewer'}</div>
                  {selected.recipient_name && (
                    <p className="mt-1 text-xs text-text-secondary">
                      To: {selected.recipient_name}
                      {selected.recipient_type === 'company_admin' ? ' (company admin)' : ''}
                    </p>
                  )}
                  <p className="mt-2 whitespace-pre-wrap text-text-primary">{selected.edited_body || selected.body}</p>
                </div>
                <div>
                  <div className="mb-1 text-xs uppercase tracking-wide text-text-secondary">Replies</div>
                  {(selected.replies || []).length === 0 ? (
                    <p className="text-xs text-text-secondary">No replies yet.</p>
                  ) : (
                    <ul className="max-h-48 space-y-2 overflow-auto">
                      {(selected.replies || []).map((r) => (
                        <li key={r.id} className="rounded-md border border-border p-2 text-xs">
                          <div className="mb-1 text-text-secondary">
                            {r.channel} · {new Date(r.received_at).toLocaleString()}
                          </div>
                          <div className="whitespace-pre-wrap">{r.body}</div>
                        </li>
                      ))}
                    </ul>
                  )}
                </div>
                {canAnswer ? (
                  <div className="space-y-2">
                    <Textarea
                      label={selected.recipient_type === 'company_admin' ? 'Your answer' : 'Admin answer'}
                      rows={4}
                      value={answer}
                      onChange={(e) => setAnswer(e.target.value)}
                      placeholder="Answer this question for the reviewer…"
                    />
                    <Button size="sm" loading={actingId === selected.id} disabled={!answer.trim()} onClick={submitAnswer}>
                      Submit answer & close
                    </Button>
                  </div>
                ) : null}
              </div>
            ) : null}
          </SheetContent>
        </Sheet>
      </div>

      <Modal
        open={Boolean(pending)}
        onClose={closeModal}
        title={pending?.action === 'approve' ? 'Approve request' : 'Decline request'}
        footer={
          <>
            <Button variant="secondary" onClick={closeModal} disabled={actingId != null}>
              Cancel
            </Button>
            <Button
              variant={pending?.action === 'decline' ? 'danger' : 'primary'}
              onClick={confirmAction}
              loading={actingId === pending?.id}
            >
              {pending?.action === 'approve' ? 'Approve' : 'Decline'}
            </Button>
          </>
        }
      >
        {pending ? (
          <div className="space-y-4">
            <p className="m-0 text-sm text-text-secondary">
              {pending.action === 'approve' ? 'Approve' : 'Decline'} this request: <strong>{pending.label}</strong>
            </p>
            {error ? <p className="m-0 text-sm text-status-error">{error}</p> : null}
            <Textarea
              label="Admin note (optional)"
              rows={3}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Optional note for the audit trail"
            />
          </div>
        ) : null}
      </Modal>
    </div>
  );
}
