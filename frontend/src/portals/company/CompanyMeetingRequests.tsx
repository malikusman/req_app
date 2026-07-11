import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, EmptyState, Textarea } from '../../components/ui';

type Meeting = {
  id: number;
  purpose: string;
  status: string;
  urgency?: string;
  duration_minutes?: number;
  desired_roles?: string[];
  admin_note?: string;
  created_at: string;
};

export function CompanyMeetingRequests() {
  const token = useCompanyToken();
  const [meetings, setMeetings] = useState<Meeting[]>([]);
  const [note, setNote] = useState('');
  const [loading, setLoading] = useState(true);
  const [actingId, setActingId] = useState<number | null>(null);

  const load = () => {
    if (!token) return;
    api
      .companyMeetingRequests(token)
      .then((d) => setMeetings(d.meeting_requests as Meeting[]))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const act = async (id: number, action: 'approve' | 'decline') => {
    if (!token) return;
    setActingId(id);
    try {
      if (action === 'approve') await api.approveMeetingRequest(token, id, { admin_note: note });
      else await api.declineMeetingRequest(token, id, { admin_note: note });
      setNote('');
      load();
    } finally {
      setActingId(null);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Meeting requests"
        description="Approve reviewer call requests before employees are coordinated."
      />
      <Card title="Admin note (optional)">
        <Textarea rows={3} value={note} onChange={(e) => setNote(e.target.value)} placeholder="Optional note for the audit trail" />
      </Card>
      <DataTable
        loading={loading}
        columns={[
          {
            key: 'purpose',
            header: 'Purpose',
            render: (m: Meeting) => <span className="text-sm">{m.purpose}</span>,
          },
          {
            key: 'status',
            header: 'Status',
            render: (m: Meeting) => <Badge variant={m.status === 'pending_admin' ? 'info' : 'neutral'}>{m.status}</Badge>,
          },
          {
            key: 'actions',
            header: '',
            render: (m: Meeting) =>
              m.status === 'pending_admin' ? (
                <div className="flex gap-2">
                  <Button size="sm" loading={actingId === m.id} onClick={() => act(m.id, 'approve')}>
                    Approve
                  </Button>
                  <Button size="sm" variant="secondary" loading={actingId === m.id} onClick={() => act(m.id, 'decline')}>
                    Decline
                  </Button>
                </div>
              ) : (
                <span className="text-xs text-text-secondary">{m.urgency || m.duration_minutes || ''}</span>
              ),
          },
        ]}
        rows={meetings}
        emptyState={<EmptyState title="No meeting requests" description="Reviewer call requests will appear here for admin approval." />}
      />
    </div>
  );
}
