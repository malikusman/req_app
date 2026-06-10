import { useEffect, useState } from 'react';
import { api, type PlatformTrialRow } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, DataTable, Button, Badge, EmptyState } from '../../components/ui';

export function PlatformTrials() {
  const token = usePlatformToken();
  const [trials, setTrials] = useState<PlatformTrialRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = () => {
    if (!token) return;
    setLoading(true);
    api
      .platformTrials(token)
      .then((d) => setTrials(d.trials))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load trials'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const extendTrial = async (companyId: number, days: number) => {
    if (!token) return;
    try {
      await api.extendPlatformTrial(token, companyId, days);
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to extend trial');
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Trials expiring soon"
        description="Companies with trials ending within 7 days."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <DataTable
        loading={loading}
        columns={[
          { key: 'name', header: 'Company', render: (r) => r.company.name },
          {
            key: 'readiness',
            header: 'Readiness',
            render: (r) => `${Math.round(r.company.report_readiness_score)}%`,
          },
          {
            key: 'participation',
            header: 'Participation',
            render: (r) => `${r.company.completed_count ?? 0} / ${r.company.invited_count ?? 0}`,
          },
          {
            key: 'days',
            header: 'Trial ends',
            render: (r) => (
              <Badge variant={r.subscription.days_remaining <= 3 ? 'warning' : 'neutral'}>
                {r.subscription.days_remaining} days left
              </Badge>
            ),
          },
          {
            key: 'actions',
            header: 'Actions',
            render: (r) => (
              <div className="flex gap-2">
                <Button variant="secondary" size="sm" onClick={() => extendTrial(r.company.id, 7)}>
                  +7 days
                </Button>
                <Button variant="secondary" size="sm" onClick={() => extendTrial(r.company.id, 14)}>
                  +14 days
                </Button>
              </div>
            ),
          },
        ]}
        rows={trials}
        emptyState={
          <EmptyState title="No expiring trials" description="No trials ending in the next 7 days." />
        }
      />
    </div>
  );
}
