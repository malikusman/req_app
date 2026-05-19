import { useEffect, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, DataTable, Badge, EmptyState } from '../../components/ui';

type ConversationRow = {
  id: number;
  employee_id: number;
  employee_name: string | null;
  status: string;
};

export function ReviewerConversations() {
  const { companyId } = useParams();
  const navigate = useNavigate();
  const token = useReviewerToken();
  const [conversations, setConversations] = useState<ConversationRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token || !companyId) return;
    api
      .reviewerConversations(token, Number(companyId))
      .then((d) => setConversations(d.conversations))
      .finally(() => setLoading(false));
  }, [token, companyId]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Discovery conversations"
        description="Review employee interview transcripts."
        breadcrumbs={[
          { label: 'Dashboard', href: '/reviewer/dashboard' },
          { label: 'Company', href: `/reviewer/companies/${companyId}` },
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
            key: 'view',
            header: '',
            render: (c) => (
              <Link
                to={`/reviewer/companies/${companyId}/conversations/${c.id}`}
                className="text-sm font-medium text-accent hover:underline"
                onClick={(e) => e.stopPropagation()}
              >
                View
              </Link>
            ),
          },
        ]}
        rows={conversations as ConversationRow[]}
        onRowClick={(c) => navigate(`/reviewer/companies/${companyId}/conversations/${c.id}`)}
        emptyState={<EmptyState title="No conversations" />}
      />
    </div>
  );
}
