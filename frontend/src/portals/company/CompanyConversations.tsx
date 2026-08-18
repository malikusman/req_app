import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { api, type CompanyConversation } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, DataTable, Badge, EmptyState } from '../../components/ui';

export function CompanyConversations() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const [conversations, setConversations] = useState<CompanyConversation[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    api
      .companyConversations(token)
      .then((d) => setConversations(d.conversations))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load conversations'))
      .finally(() => setLoading(false));
  }, [token]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Conversations"
        description="Discovery interviews with your team."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <DataTable
        loading={loading}
        columns={[
          {
            key: 'employee',
            header: 'Employee',
            render: (c) => (
              <Link to={`/company/conversations/${c.id}`} className="font-medium text-accent hover:underline">
                {c.employee_name || `Employee #${c.employee_id}`}
              </Link>
            ),
          },
          { key: 'department', header: 'Department', render: (c) => c.department || '—' },
          {
            key: 'status',
            header: 'Status',
            render: (c) => (
              <Badge variant={c.status === 'completed' ? 'success' : 'info'}>{c.status}</Badge>
            ),
          },
          {
            key: 'last_activity',
            header: 'Last activity',
            render: (c) => (c.last_activity_at ? new Date(c.last_activity_at).toLocaleString() : '—'),
          },
        ]}
        rows={conversations}
        onRowClick={(c) => navigate(`/company/conversations/${c.id}`)}
        emptyState={
          <EmptyState
            title="No conversations yet"
            description="Invite your team to begin — each conversation appears here as they start."
            action={{ label: 'Invite your team', onClick: () => navigate('/company/employees') }}
            secondaryAction={{ label: 'Upload documents instead', onClick: () => navigate('/company/documents') }}
          />
        }
      />
    </div>
  );
}
