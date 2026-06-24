import { useEffect, useState } from 'react';
import {
  Building2,
  Clock,
  FileText,
  Activity,
  MessageSquare,
  Users,
  Radio,
} from 'lucide-react';
import { api, type PlatformDashboardPayload } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import {
  DashboardShell,
  StatCard,
  Card,
  DataTable,
  Badge,
  Button,
  EmptyState,
} from '../../components/ui';

function statusDot(status: string) {
  if (status === 'ok' || status === 'healthy' || status === 'configured') return 'bg-status-success';
  if (status === 'degraded' || status === 'warning' || status === 'unconfigured') return 'bg-status-warning';
  return 'bg-status-error';
}

function serviceLabel(status: string) {
  if (status === 'ok' || status === 'configured') return 'Healthy';
  if (status === 'unconfigured') return 'Not configured';
  if (status === 'unavailable') return 'Unavailable';
  return 'Down';
}

function serviceVariant(status: string): 'success' | 'warning' | 'error' | 'neutral' {
  if (status === 'ok' || status === 'configured') return 'success';
  if (status === 'unconfigured' || status === 'unavailable') return 'warning';
  return 'error';
}

export function PlatformDashboard() {
  const token = usePlatformToken();
  const [data, setData] = useState<PlatformDashboardPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [extendingId, setExtendingId] = useState<number | null>(null);

  const load = () => {
    if (!token) return;
    setLoading(true);
    setError('');
    api
      .platformDashboard(token)
      .then(setData)
      .catch(() => setError('Could not load platform dashboard.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const extendTrial = async (companyId: number) => {
    if (!token) return;
    setExtendingId(companyId);
    try {
      await api.extendPlatformTrial(token, companyId, 7);
      load();
    } finally {
      setExtendingId(null);
    }
  };

  const monitoring = data?.monitoring;
  const system = data?.system;
  const trials = data?.trials_expiring_soon ?? [];
  const activeTrials = monitoring?.subscriptions.active_trials ?? monitoring?.subscriptions.by_status?.trial ?? 0;
  const reportsTotal = monitoring
    ? monitoring.reports.ready + monitoring.reports.generating + monitoring.reports.failed
    : '—';

  const systemHealthLabel = (() => {
    if (!system) return 'Unknown';
    const statuses = Object.values(system.services).map((s) => s.status);
    if (statuses.every((s) => s === 'ok' || s === 'configured')) return 'Healthy';
    if (statuses.some((s) => s === 'error')) return 'Degraded';
    return 'Partial';
  })();

  return (
    <DashboardShell
      title="Platform dashboard"
      description="Cross-tenant health, trials, and discovery activity."
      loading={loading}
      banner={
        error ? (
          <div className="rounded-card border border-status-warning/30 bg-status-warningBg px-4 py-3 text-sm">
            {error}
          </div>
        ) : undefined
      }
      kpiRow={
        monitoring ? (
          <>
            <StatCard label="Total companies" value={monitoring.companies.total} icon={<Building2 className="h-5 w-5 text-accent" />} />
            <StatCard label="Active trials" value={activeTrials} icon={<Clock className="h-5 w-5 text-accent" />} />
            <StatCard label="Discovery (24h)" value={monitoring.discovery.conversations_last_24h} icon={<MessageSquare className="h-5 w-5 text-accent" />} />
            <StatCard label="Reports" value={reportsTotal} icon={<FileText className="h-5 w-5 text-accent" />} />
            <StatCard label="Avg readiness" value={`${monitoring.companies.avg_readiness}%`} icon={<Users className="h-5 w-5 text-accent" />} />
            <StatCard label="System" value={systemHealthLabel} icon={<Activity className="h-5 w-5 text-accent" />} />
          </>
        ) : undefined
      }
    >
      {monitoring && (
        <div className="grid gap-4 lg:grid-cols-3">
          <Card title="Discovery velocity">
            <div className="space-y-3 text-sm">
              <div className="flex justify-between">
                <span className="text-text-secondary">Active conversations</span>
                <span className="font-medium">{monitoring.discovery.active_conversations}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-secondary">Completed employees</span>
                <span className="font-medium">{monitoring.discovery.completed_employees}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-text-secondary">Trials at limit</span>
                <span className="font-medium">{monitoring.subscriptions.at_conversation_limit}</span>
              </div>
            </div>
          </Card>

          <Card title="Report pipeline">
            <div className="space-y-3 text-sm">
              <div className="flex justify-between">
                <span className="text-text-secondary">Ready</span>
                <Badge variant="success">{monitoring.reports.ready}</Badge>
              </div>
              <div className="flex justify-between">
                <span className="text-text-secondary">Generating</span>
                <Badge variant="info">{monitoring.reports.generating}</Badge>
              </div>
              <div className="flex justify-between">
                <span className="text-text-secondary">Failed</span>
                <Badge variant={monitoring.reports.failed > 0 ? 'error' : 'neutral'}>{monitoring.reports.failed}</Badge>
              </div>
            </div>
          </Card>

          {monitoring.multimodal && (
            <Card title="Multimodal">
              <div className="space-y-3 text-sm">
                <div className="flex justify-between">
                  <span className="text-text-secondary">Ready attachments</span>
                  <span className="font-medium">{monitoring.multimodal.ready_attachments}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-secondary">Processing</span>
                  <span className="font-medium">{monitoring.multimodal.processing_attachments}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-text-secondary">Last 24h</span>
                  <span className="font-medium">{monitoring.multimodal.attachments_last_24h}</span>
                </div>
              </div>
            </Card>
          )}
        </div>
      )}

      <Card title="Trials expiring soon">
        <DataTable
          columns={[
            { key: 'name', header: 'Company', render: (r) => r.company.name },
            {
              key: 'plan',
              header: 'Plan',
              render: (r) => <Badge variant="neutral">{r.subscription.plan ?? 'Trial'}</Badge>,
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
                  onClick={() => extendTrial(r.company.id)}
                >
                  Extend
                </Button>
              ),
            },
          ]}
          rows={trials}
          emptyState={<EmptyState title="No trials expiring" description="No trials ending in the next 7 days." />}
        />
      </Card>

      {system && (
        <div className="flex flex-wrap items-center gap-4 rounded-card border border-border bg-surface px-4 py-3 shadow-card">
          <span className="text-label-caps text-text-secondary">System health</span>
          {Object.entries(system.services).map(([name, service]) => (
            <div key={name} className="flex items-center gap-2 text-sm">
              <span className={`h-2.5 w-2.5 rounded-full ${statusDot(service.status)}`} aria-hidden />
              <span className="capitalize text-text-primary">{name}</span>
              <Badge variant={serviceVariant(service.status)}>{serviceLabel(service.status)}</Badge>
            </div>
          ))}
          <div className="flex items-center gap-2 text-sm">
            <Radio className="h-4 w-4 text-text-secondary" />
            <span className="text-text-secondary">WhatsApp failure rate</span>
            <Badge variant={system.whatsapp_delivery.failure_rate >= 5 ? 'warning' : 'success'}>
              {system.whatsapp_delivery.failure_rate}%
            </Badge>
          </div>
        </div>
      )}
    </DashboardShell>
  );
}
