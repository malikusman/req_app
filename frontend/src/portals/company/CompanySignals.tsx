import { useEffect, useState } from 'react';
import { api, type CompanySignal } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, DataTable, Badge, StrengthBar, EmptyState } from '../../components/ui';

export function CompanySignals() {
  const token = useCompanyToken();
  const [signals, setSignals] = useState<CompanySignal[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    api
      .intelligenceSignals(token)
      .then((d) => setSignals(d.signals))
      .finally(() => setLoading(false));
  }, [token]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Signals"
        description="Pain points and opportunities surfaced from discovery interviews."
      />

      <DataTable
        loading={loading}
        columns={[
          { key: 'label', header: 'Signal' },
          {
            key: 'strength',
            header: 'Strength',
            render: (s) => (
              <div className="min-w-[120px]">
                <StrengthBar strength={s.strength} />
                <span className="text-xs text-text-secondary">{Math.round(s.strength * 100)}%</span>
              </div>
            ),
          },
          {
            key: 'departments',
            header: 'Departments',
            render: (s) => s.departments.join(', ') || '—',
          },
          {
            key: 'evidence',
            header: 'Evidence',
            render: (s) => s.evidence_count,
          },
          {
            key: 'status',
            header: 'Status',
            render: (s) => <Badge variant="info">{s.status}</Badge>,
          },
        ]}
        rows={signals as CompanySignal[]}
        emptyState={
          <EmptyState title="No signals yet" description="Complete more interviews to surface operational signals." />
        }
      />
    </div>
  );
}
