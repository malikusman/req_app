import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, Textarea, EmptyState } from '../../components/ui';

type Outreach = {
  id: number;
  status: string;
  purpose: string;
  channel: string;
  body: string;
  reason?: string;
  employee_id?: number;
  reviewer_name?: string;
  created_at: string;
};

export function CompanyOutreaches() {
  const token = useCompanyToken();
  const [outreaches, setOutreaches] = useState<Outreach[]>([]);
  const [note, setNote] = useState('');
  const [loading, setLoading] = useState(true);
  const [actingId, setActingId] = useState<number | null>(null);

  const load = () => {
    if (!token) return;
    api
      .companyOutreaches(token)
      .then((d) => setOutreaches(d.outreaches))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const act = async (id: number, action: 'approve' | 'decline') => {
    if (!token) return;
    setActingId(id);
    try {
      if (action === 'approve') await api.approveOutreach(token, id, { note });
      else await api.declineOutreach(token, id, { note });
      setNote('');
      load();
    } finally {
      setActingId(null);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Reviewer clarifications"
        description="Approve or decline reviewer requests before employees are contacted."
      />
      <Card title="Admin note (optional)">
        <Textarea rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Optional note for the audit trail" />
      </Card>
      <DataTable
        loading={loading}
        columns={[
          {
            key: 'reviewer',
            header: 'Reviewer',
            render: (o: Outreach) => o.reviewer_name || '—',
          },
          {
            key: 'body',
            header: 'Request',
            render: (o: Outreach) => <span className="text-sm">{o.body}</span>,
          },
          {
            key: 'status',
            header: 'Status',
            render: (o: Outreach) => <Badge variant={o.status === 'pending_admin_approval' ? 'info' : 'neutral'}>{o.status}</Badge>,
          },
          {
            key: 'actions',
            header: '',
            render: (o: Outreach) =>
              o.status === 'pending_admin_approval' ? (
                <div className="flex gap-2">
                  <Button size="sm" loading={actingId === o.id} onClick={() => act(o.id, 'approve')}>
                    Approve
                  </Button>
                  <Button size="sm" variant="secondary" loading={actingId === o.id} onClick={() => act(o.id, 'decline')}>
                    Decline
                  </Button>
                </div>
              ) : (
                <span className="text-xs text-text-secondary">{o.channel}</span>
              ),
          },
        ]}
        rows={outreaches}
        emptyState={<EmptyState title="No clarification requests" description="Reviewer follow-ups requiring approval will appear here." />}
      />
    </div>
  );
}
