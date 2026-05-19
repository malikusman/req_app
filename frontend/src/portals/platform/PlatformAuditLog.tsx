import { PageHeader, DataTable, Badge, EmptyState } from '../../components/ui';
import { mockAuditLogs } from '../../lib/mocks/platformAuditLog';

export function PlatformAuditLog() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Audit log"
        description="Platform administration events (mock data for preview)."
      />

      <DataTable
        columns={[
          { key: 'created_at', header: 'When', render: (r) => new Date(r.created_at).toLocaleString() },
          { key: 'actor', header: 'Actor' },
          {
            key: 'action',
            header: 'Action',
            render: (r) => (
              <Badge variant="info">{r.action.replace(/_/g, ' ')}</Badge>
            ),
          },
          { key: 'target', header: 'Target' },
          { key: 'ip', header: 'IP' },
        ]}
        rows={mockAuditLogs}
        emptyState={<EmptyState title="No audit events" />}
      />
    </div>
  );
}
