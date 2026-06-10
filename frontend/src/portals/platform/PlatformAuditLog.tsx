import { useEffect, useState } from 'react';
import { api, type PlatformAuditLogEntry } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, DataTable, Badge, EmptyState, Button } from '../../components/ui';

const AUDIT_ACTIONS = [
  '',
  'company_created',
  'company_updated',
  'reviewer_assigned',
  'report_generated',
  'report_approved',
  'trial_extended',
];

export function PlatformAuditLog() {
  const token = usePlatformToken();
  const [logs, setLogs] = useState<PlatformAuditLogEntry[]>([]);
  const [page, setPage] = useState(1);
  const [total, setTotal] = useState(0);
  const [actionFilter, setActionFilter] = useState('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    api
      .platformAuditLogs(token, {
        page,
        action: actionFilter || undefined,
      })
      .then((d) => {
        setLogs(d.audit_logs);
        setTotal(d.pagination.total);
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load audit log'))
      .finally(() => setLoading(false));
  }, [token, page, actionFilter]);

  const totalPages = Math.max(1, Math.ceil(total / 50));

  return (
    <div className="space-y-6">
      <PageHeader
        title="Audit log"
        description="Platform administration events."
      />

      <div className="flex flex-wrap items-center gap-3">
        <label className="text-sm text-text-secondary">
          Action
          <select
            className="ml-2 rounded-button border border-border bg-surface px-3 py-1.5 text-sm text-text-primary"
            value={actionFilter}
            onChange={(e) => {
              setActionFilter(e.target.value);
              setPage(1);
            }}
          >
            <option value="">All actions</option>
            {AUDIT_ACTIONS.filter(Boolean).map((action) => (
              <option key={action} value={action}>
                {action.replace(/_/g, ' ')}
              </option>
            ))}
          </select>
        </label>
      </div>

      {error && <p className="text-sm text-status-error">{error}</p>}

      <DataTable
        loading={loading}
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
          { key: 'ip', header: 'IP', render: (r) => r.ip || '—' },
        ]}
        rows={logs}
        emptyState={<EmptyState title="No audit events" />}
      />

      {totalPages > 1 && (
        <div className="flex items-center justify-end gap-2">
          <Button variant="secondary" size="sm" disabled={page <= 1} onClick={() => setPage((p) => p - 1)}>
            Previous
          </Button>
          <span className="text-sm text-text-secondary">
            Page {page} of {totalPages}
          </span>
          <Button variant="secondary" size="sm" disabled={page >= totalPages} onClick={() => setPage((p) => p + 1)}>
            Next
          </Button>
        </div>
      )}
    </div>
  );
}
