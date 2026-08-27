import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useConsultantToken } from '../../lib/auth';
import { PageHeader, DataTable, Badge, EmptyState } from '../../components/ui';

type ConversationRow = {
  id: number;
  employee_id: number;
  employee_name: string | null;
  department: string | null;
  status: string;
  last_active_at: string | null;
};

export function ConsultantConversations() {
  const { companyId } = useParams();
  const navigate = useNavigate();
  const token = useConsultantToken();
  const [conversations, setConversations] = useState<ConversationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token || !companyId) return;
    setLoading(true);
    setError('');
    api
      .consultantConversations(token, Number(companyId))
      .then(async (d) => {
        const employees = await api.consultantEmployees(token, Number(companyId)).catch(() => ({ employees: [] }));
        const deptByEmployee = new Map(employees.employees.map((e) => [e.id, e.department]));
        setConversations(
          d.conversations.map((c) => ({
            ...c,
            department: deptByEmployee.get(c.employee_id) || null,
            last_active_at: c.last_activity_at,
          }))
        );
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load conversations'))
      .finally(() => setLoading(false));
  }, [token, companyId]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Discovery conversations"
        description="Review employee interview transcripts."
        breadcrumbs={[
          { label: 'Dashboard', href: '/consultant/dashboard' },
          { label: 'Company', href: `/consultant/companies/${companyId}` },
          { label: 'Conversations' },
        ]}
      />

      <DataTable
        loading={loading}
        columns={[
          {
            key: 'employee',
            header: 'Employee',
            render: (c) => c.employee_name || `Employee #${c.employee_id}`,
          },
          {
            key: 'status',
            header: 'Status',
            render: (c) => <Badge variant={c.status === 'completed' ? 'success' : 'info'}>{c.status}</Badge>,
          },
          {
            key: 'department',
            header: 'Department',
            render: (c) => c.department || '—',
          },
          {
            key: 'lastActive',
            header: 'Last active',
            render: (c) => (c.last_active_at ? new Date(c.last_active_at).toLocaleString() : '—'),
          },
          {
            key: 'view',
            header: '',
            render: (c) => (
              <Link
                to={`/consultant/companies/${companyId}/conversations/${c.id}`}
                className="text-sm font-medium text-accent hover:underline"
                onClick={(e) => e.stopPropagation()}
              >
                View
              </Link>
            ),
          },
        ]}
        rows={conversations as ConversationRow[]}
        onRowClick={(c) => navigate(`/consultant/companies/${companyId}/conversations/${c.id}`)}
        emptyState={
          <EmptyState
            title={error ? 'Unable to load conversations' : 'No conversations'}
            description={error || 'Employee interview transcripts will appear here once interviews begin.'}
          />
        }
      />
    </div>
  );
}
