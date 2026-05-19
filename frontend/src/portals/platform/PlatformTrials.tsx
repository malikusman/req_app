import { useEffect, useState } from 'react';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, DataTable, Button, Badge, EmptyState } from '../../components/ui';

const API_URL = import.meta.env.VITE_API_URL || '';

type TrialRow = {
  company: { id: number; name: string; report_readiness_score: number; completed_count: number; invited_count: number };
  subscription: { trial_ends_at: string; days_remaining: number };
};

export function PlatformTrials() {
  const token = usePlatformToken();
  const [trials, setTrials] = useState<TrialRow[]>([]);
  const [loading, setLoading] = useState(true);

  const load = () => {
    if (!token) return;
    fetch(`${API_URL}/api/v1/platform/trials`, {
      headers: { Authorization: `Bearer ${token}` },
    })
      .then((r) => r.json())
      .then((d) => setTrials(d.trials || []))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const extendTrial = async (companyId: number, days: number) => {
    if (!token) return;
    await fetch(`${API_URL}/api/v1/platform/trials/${companyId}/extend`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ days }),
    });
    load();
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Trials expiring soon"
        description="Companies with trials ending within 7 days."
      />

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
            render: (r) => `${r.company.completed_count} / ${r.company.invited_count}`,
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
        rows={trials as TrialRow[]}
        emptyState={
          <EmptyState title="No expiring trials" description="No trials ending in the next 7 days." />
        }
      />
    </div>
  );
}
