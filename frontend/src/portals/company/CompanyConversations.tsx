import { Link, useNavigate } from 'react-router-dom';
import { PageHeader, DataTable, Badge, EmptyState } from '../../components/ui';
import { mockConversations } from '../../lib/mocks/companyConversations';

export function CompanyConversations() {
  const navigate = useNavigate();

  return (
    <div className="space-y-6">
      <PageHeader
        title="Conversations"
        description="Discovery interview sessions with your employees (preview data)."
      />

      <DataTable
        columns={[
          {
            key: 'employee',
            header: 'Employee',
            render: (c) => (
              <Link to={`/company/conversations/${c.id}`} className="font-medium text-accent hover:underline">
                {c.employee_name}
              </Link>
            ),
          },
          { key: 'department', header: 'Department' },
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
            render: (c) => new Date(c.last_activity_at).toLocaleString(),
          },
        ]}
        rows={mockConversations}
        onRowClick={(c) => navigate(`/company/conversations/${c.id}`)}
        emptyState={<EmptyState title="No conversations" description="Conversations appear when employees start interviews." />}
      />
    </div>
  );
}
