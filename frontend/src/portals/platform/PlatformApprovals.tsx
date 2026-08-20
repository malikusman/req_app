import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type PlatformApprovalRow } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, DataTable, Button, Badge, EmptyState } from '../../components/ui';

function generatedLabel(iso: string | null): string {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' });
}

export function PlatformApprovals() {
  const token = usePlatformToken();
  const navigate = useNavigate();
  const [rows, setRows] = useState<PlatformApprovalRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    api
      .platformPendingReports(token)
      .then((d) => setRows(d.reports))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load the approval queue'))
      .finally(() => setLoading(false));
  }, [token]);

  const openReview = (companyId: number) => navigate(`/platform/companies/${companyId}?tab=reports`);

  const count = rows.length;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Approvals"
        description={
          count > 0
            ? `${count} report${count === 1 ? '' : 's'} finished review and are waiting for you to approve and ship to the company.`
            : 'Reports finished review and waiting to ship appear here.'
        }
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <DataTable
        loading={loading}
        columns={[
          { key: 'company', header: 'Company', render: (r) => r.company.name },
          {
            key: 'version',
            header: 'Report',
            render: (r) => <span className="tabular-nums text-muted-foreground">v{r.report.version}</span>,
          },
          {
            key: 'generated',
            header: 'Generated',
            render: (r) => (
              <span className="tabular-nums text-muted-foreground">{generatedLabel(r.report.generated_at)}</span>
            ),
          },
          {
            key: 'status',
            header: 'Status',
            render: (r) =>
              r.blocked_needs_info ? (
                <Badge variant="warning">Needs clarification</Badge>
              ) : (
                <Badge variant="success">Ready to approve</Badge>
              ),
          },
          {
            key: 'reviewer',
            header: 'Reviewer',
            render: (r) => (
              <span className="text-sm text-muted-foreground">{r.has_reviewer ? 'Expert reviewed' : 'No reviewer'}</span>
            ),
          },
          {
            key: 'actions',
            header: '',
            render: (r) => (
              <Button variant="secondary" size="sm" onClick={() => openReview(r.company.id)}>
                {r.blocked_needs_info ? 'Resolve' : 'Review & approve'}
              </Button>
            ),
          },
        ]}
        rows={rows}
        emptyState={
          <EmptyState
            title="You're all caught up"
            description="No reports are waiting on your approval right now."
          />
        }
      />
    </div>
  );
}
