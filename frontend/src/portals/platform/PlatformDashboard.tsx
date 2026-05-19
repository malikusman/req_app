import { useEffect, useState } from 'react';
import { Building2, MessageSquare, FileBarChart, Users } from 'lucide-react';
import { api, type PlatformMonitoring, type PlatformSystemHealth } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, StatCard, Card, DataTable, Badge, Skeleton, EmptyState } from '../../components/ui';

const API_URL = import.meta.env.VITE_API_URL || '';

type TrialRow = {
  company: { id: number; name: string; report_readiness_score: number };
  subscription: { days_remaining: number };
};

function statusDot(status: string) {
  if (status === 'ok') return 'bg-status-success';
  if (status === 'degraded' || status === 'warning') return 'bg-status-warning';
  return 'bg-status-error';
}

function SystemHealthStrip({ health }: { health: PlatformSystemHealth | null }) {
  if (!health) return null;
  return (
    <div className="flex flex-wrap items-center gap-4 rounded-card border border-border bg-surface px-4 py-3">
      <span className="text-label-caps text-text-secondary">Services</span>
      {Object.entries(health.services).map(([name, svc]) => (
        <div key={name} className="flex items-center gap-2 text-sm">
          <span className={`h-2.5 w-2.5 rounded-full ${statusDot(svc.status)}`} aria-hidden />
          <span className="capitalize text-text-primary">{name}</span>
          <Badge variant={svc.status === 'ok' ? 'success' : svc.status === 'degraded' ? 'warning' : 'error'}>
            {svc.status}
          </Badge>
        </div>
      ))}
    </div>
  );
}

export function PlatformDashboard() {
  const token = usePlatformToken();
  const [monitoring, setMonitoring] = useState<PlatformMonitoring | null>(null);
  const [health, setHealth] = useState<PlatformSystemHealth | null>(null);
  const [trials, setTrials] = useState<TrialRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    Promise.all([
      api.platformMonitoring(token),
      api.platformSystem(token),
      fetch(`${API_URL}/api/v1/platform/trials`, { headers: { Authorization: `Bearer ${token}` } }).then((r) =>
        r.json()
      ),
    ])
      .then(([mon, sys, trialsData]) => {
        setMonitoring(mon);
        setHealth(sys);
        setTrials(trialsData.trials?.slice(0, 5) || []);
      })
      .finally(() => setLoading(false));
  }, [token]);

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <div className="grid gap-4 md:grid-cols-4">
          {[1, 2, 3, 4].map((i) => (
            <Skeleton key={i} variant="card" />
          ))}
        </div>
      </div>
    );
  }

  if (!monitoring) return null;

  return (
    <div className="space-y-8">
      <PageHeader
        title="Platform dashboard"
        description="Cross-tenant health, trials, and discovery activity."
      />

      <SystemHealthStrip health={health} />

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          label="Companies"
          value={monitoring.companies.total}
          icon={<Building2 className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Active conversations"
          value={monitoring.discovery.active_conversations}
          icon={<MessageSquare className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Reports ready"
          value={monitoring.reports.ready}
          icon={<FileBarChart className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Avg readiness"
          value={`${monitoring.companies.avg_readiness}%`}
          icon={<Users className="h-5 w-5 text-accent" />}
        />
      </div>

      <Card title="Trials expiring soon">
        <DataTable
          columns={[
            { key: 'name', header: 'Company', render: (r) => r.company.name },
            {
              key: 'readiness',
              header: 'Readiness',
              render: (r) => `${Math.round(r.company.report_readiness_score)}%`,
            },
            {
              key: 'days',
              header: 'Days left',
              render: (r) => (
                <Badge variant={r.subscription.days_remaining <= 3 ? 'warning' : 'neutral'}>
                  {r.subscription.days_remaining}d
                </Badge>
              ),
            },
          ]}
          rows={trials as TrialRow[]}
          emptyState={
            <EmptyState title="No trials expiring" description="No trials ending in the next 7 days." />
          }
        />
      </Card>
    </div>
  );
}
