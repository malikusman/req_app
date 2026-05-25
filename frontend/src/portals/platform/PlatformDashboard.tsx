import { useEffect, useState } from 'react';
import { Building2, Clock, FileText, Activity } from 'lucide-react';
import {
  api,
  type PlatformMonitoring,
  type PlatformSystemHealth,
  type PlatformTrialRow,
} from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { StatCardGrid } from '../../components/motion';
import {
  PageHeader,
  StatCard,
  Card,
  DataTable,
  Badge,
  Button,
  Skeleton,
  EmptyState,
} from '../../components/ui';

function statusDot(status: string) {
  if (status === 'ok' || status === 'healthy') return 'bg-status-success';
  if (status === 'degraded' || status === 'warning') return 'bg-status-warning';
  return 'bg-status-error';
}

function aggregateSystemHealth(health: PlatformSystemHealth | null): {
  label: string;
  variant: 'success' | 'warning' | 'error';
} {
  if (!health) return { label: 'Unknown', variant: 'warning' };
  const services = Object.values(health.services);
  const langgraph = health.services.langgraph?.status;
  const redis = health.services.redis?.status;
  if (langgraph === 'error' && redis === 'error') return { label: 'Down', variant: 'error' };
  if (services.some((s) => s.status === 'error' || s.status === 'unavailable')) {
    return { label: 'Degraded', variant: 'warning' };
  }
  return { label: 'Healthy', variant: 'success' };
}

function whatsappStatus(health: PlatformSystemHealth | null): string {
  if (!health) return 'error';
  const rate = health.whatsapp_delivery?.failure_rate ?? 0;
  return rate < 5 ? 'ok' : 'warning';
}

function SystemHealthStrip({ health }: { health: PlatformSystemHealth | null }) {
  const items = [
    { name: 'LangGraph', status: health?.services.langgraph?.status ?? 'error' },
    { name: 'Sidekiq', status: health?.services.redis?.status ?? 'error' },
    { name: 'WhatsApp', status: whatsappStatus(health) },
    { name: 'OpenAI', status: 'ok' as const },
  ];

  return (
    <div className="flex flex-wrap items-center gap-4 rounded-card border border-border bg-surface px-4 py-3 shadow-card">
      <span className="text-label-caps text-text-secondary">System health</span>
      {items.map(({ name, status }) => (
        <div key={name} className="flex items-center gap-2 text-sm">
          <span className={`h-2.5 w-2.5 rounded-full ${statusDot(status)}`} aria-hidden />
          <span className="text-text-primary">{name}</span>
          <Badge variant={status === 'ok' ? 'success' : status === 'warning' ? 'warning' : 'error'}>
            {status === 'ok' ? 'Healthy' : status === 'warning' ? 'Degraded' : 'Down'}
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
  const [trials, setTrials] = useState<PlatformTrialRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [errors, setErrors] = useState<string[]>([]);
  const [extendingId, setExtendingId] = useState<number | null>(null);

  const loadTrials = () => {
    if (!token) return;
    api.platformTrials(token).then((d) => setTrials(d.trials || [])).catch(() => setTrials([]));
  };

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    setErrors([]);

    Promise.allSettled([
      api.platformMonitoring(token),
      api.platformSystem(token),
      api.platformTrials(token),
    ])
      .then(([monResult, sysResult, trialsResult]) => {
        const errs: string[] = [];
        if (monResult.status === 'fulfilled') {
          setMonitoring(monResult.value);
        } else {
          errs.push('Could not load monitoring metrics.');
        }
        if (sysResult.status === 'fulfilled') {
          setHealth(sysResult.value);
        } else {
          errs.push('Could not load system health.');
        }
        if (trialsResult.status === 'fulfilled') {
          setTrials(trialsResult.value.trials || []);
        } else {
          errs.push('Could not load trial data.');
        }
        setErrors(errs);
      })
      .finally(() => setLoading(false));
  }, [token]);

  const extendTrial = async (companyId: number, days: number) => {
    if (!token) return;
    setExtendingId(companyId);
    try {
      await api.extendPlatformTrial(token, companyId, days);
      loadTrials();
    } finally {
      setExtendingId(null);
    }
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {[1, 2, 3, 4].map((i) => (
            <Skeleton key={i} variant="card" />
          ))}
        </div>
        <Skeleton variant="card" />
      </div>
    );
  }

  const systemHealth = aggregateSystemHealth(health);
  const activeTrials =
    monitoring?.subscriptions.by_status.trial ??
    monitoring?.subscriptions.by_status.trialing ??
    monitoring?.subscriptions.trials_expiring_7d ??
    0;
  const reportsTotal = monitoring
    ? monitoring.reports.ready + monitoring.reports.generating + monitoring.reports.failed
    : '—';

  return (
    <div className="space-y-8">
      <PageHeader
        title="Platform dashboard"
        description="Cross-tenant health, trials, and discovery activity."
      />

      {errors.length > 0 && (
        <div className="rounded-card border border-status-warning/30 bg-status-warningBg px-4 py-3 text-sm text-text-primary">
          {errors.join(' ')}
        </div>
      )}

      <StatCardGrid>
        <StatCard
          label="Total companies"
          value={monitoring?.companies.total ?? '—'}
          icon={<Building2 className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Active trials"
          value={activeTrials}
          icon={<Clock className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Reports generated"
          value={reportsTotal}
          icon={<FileText className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="System health"
          value={systemHealth.label}
          icon={<Activity className="h-5 w-5 text-accent" />}
        />
      </StatCardGrid>

      <Card title="Trials expiring soon">
        <div className="overflow-x-auto">
          <DataTable
            columns={[
              { key: 'name', header: 'Company', render: (r) => r.company.name },
              {
                key: 'plan',
                header: 'Plan',
                render: (r) => (
                  <Badge variant="neutral">{r.subscription.plan ?? 'Trial'}</Badge>
                ),
              },
              {
                key: 'readiness',
                header: 'Readiness',
                render: (r) => `${Math.round(r.company.report_readiness_score)}%`,
              },
              {
                key: 'days',
                header: 'Days remaining',
                render: (r) => {
                  const d = r.subscription.days_remaining;
                  const variant = d <= 3 ? 'error' : d <= 7 ? 'warning' : 'neutral';
                  return <Badge variant={variant}>{d}d</Badge>;
                },
              },
              {
                key: 'actions',
                header: '',
                render: (r) => (
                  <Button
                    variant="secondary"
                    size="sm"
                    loading={extendingId === r.company.id}
                    onClick={() => extendTrial(r.company.id, 7)}
                  >
                    Extend
                  </Button>
                ),
              },
            ]}
            rows={trials}
            emptyState={
              <EmptyState
                title="No trials expiring"
                description="No trials ending in the next 7 days."
              />
            }
          />
        </div>
      </Card>

      <SystemHealthStrip health={health} />

      {!monitoring && !health && trials.length === 0 && errors.length > 0 && (
        <EmptyState
          title="Dashboard unavailable"
          description="Check your connection and try refreshing the page."
        />
      )}
    </div>
  );
}
