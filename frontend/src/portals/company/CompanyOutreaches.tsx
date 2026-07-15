import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, Textarea, EmptyState } from '../../components/ui';
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

export function CompanyOutreaches() {
  const token = useCompanyToken();
  const isNarrow = useMediaQuery('(max-width: 1023px)');
  const [outreaches, setOutreaches] = useState<Outreach[]>([]);
  const [selected, setSelected] = useState<Outreach | null>(null);
  const [note, setNote] = useState('');
  const [answer, setAnswer] = useState('');
  const [loading, setLoading] = useState(true);
  const [actingId, setActingId] = useState<number | null>(null);
  const [error, setError] = useState('');

  const load = () => {
    if (!token) return;
    api
      .companyOutreaches(token)
      .then((d) => {
        const list = d.outreaches as Outreach[];
        setOutreaches(list);
        setSelected((prev) => (prev ? list.find((o) => o.id === prev.id) || null : null));
      })
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const act = async (id: number, action: 'approve' | 'decline') => {
    if (!token) return;
    setActingId(id);
    setError('');
    try {
      if (action === 'approve') await api.approveOutreach(token, id, { note });
      else await api.declineOutreach(token, id, { note });
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

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reviewer clarifications"
        description="Approve or decline reviewer requests, then answer portal clarifications and review employee replies."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <Card title="Admin note (optional)">
        <Textarea
          rows={3}
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Optional note for the audit trail when approving or declining"
        />
      </Card>

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
              render: (o: Outreach) => <Badge variant={statusVariant(o.status)}>{o.status}</Badge>,
            },
            {
              key: 'actions',
              header: '',
              render: (o: Outreach) =>
                o.status === 'pending_admin_approval' ? (
                  <div className="flex flex-wrap gap-2" onClick={(e) => e.stopPropagation()}>
                    <Button size="sm" loading={actingId === o.id} onClick={() => act(o.id, 'approve')}>
                      Approve
                    </Button>
                    <Button size="sm" variant="secondary" loading={actingId === o.id} onClick={() => act(o.id, 'decline')}>
                      Decline
                    </Button>
                  </div>
                ) : (
                  <span className="text-xs text-muted-foreground">{o.channel}</span>
                ),
            },
          ]}
          rows={outreaches}
          emptyState={
            <EmptyState
              title="No clarification requests"
              description="Reviewer follow-ups requiring approval will appear here."
            />
          }
        />

        <Card className="hidden lg:block" title="Thread">
          {!selected ? (
            <p className="text-sm text-text-secondary">Select a clarification to see replies and answer.</p>
          ) : (
            <div className="space-y-4 text-sm">
              <div>
                <div className="mb-1 flex items-center gap-2">
                  <Badge variant={statusVariant(selected.status)}>{selected.status}</Badge>
                  <span className="text-xs text-text-secondary">{selected.channel}</span>
                </div>
                <div className="font-medium">{selected.reviewer_name || 'Reviewer'}</div>
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
                    label="Admin answer"
                    rows={4}
                    value={answer}
                    onChange={(e) => setAnswer(e.target.value)}
                    placeholder="Answer this clarification for the reviewer…"
                  />
                  <Button size="sm" loading={actingId === selected.id} disabled={!answer.trim()} onClick={submitAnswer}>
                    Submit answer & close
                  </Button>
                </div>
              ) : (
                <p className="text-xs text-text-secondary">
                  {selected.status === 'pending_admin_approval'
                    ? 'Approve this request before employees are contacted.'
                    : selected.status === 'closed'
                      ? 'This clarification is closed.'
                      : 'Answering is not available for this status.'}
                </p>
              )}
            </div>
          )}
        </Card>

        <Sheet open={Boolean(selected) && isNarrow} onOpenChange={(open) => !open && setSelected(null)}>
          <SheetContent side="bottom" className="max-h-[85dvh] overflow-y-auto">
            <SheetHeader>
              <SheetTitle>Clarification thread</SheetTitle>
            </SheetHeader>
            {selected ? (
              <div className="mt-4 space-y-4 text-sm">
                <div>
                  <div className="mb-1 flex flex-wrap items-center gap-2">
                    <Badge variant={statusVariant(selected.status)}>{selected.status}</Badge>
                    <span className="text-xs text-text-secondary">{selected.channel}</span>
                  </div>
                  <div className="font-medium">{selected.reviewer_name || 'Reviewer'}</div>
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
                      label="Admin answer"
                      rows={4}
                      value={answer}
                      onChange={(e) => setAnswer(e.target.value)}
                      placeholder="Answer this clarification for the reviewer…"
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
    </div>
  );
}
