import { useEffect, useState } from 'react';
import {
  Building2,
  Clock,
  FileText,
  Activity,
  Inbox,
  MessageSquare,
  UserPlus,
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
  AttentionList,
  type AttentionItemData,
} from '../../components/ui';
import { cn } from '../../lib/cn';

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

function StatusChip({ count }: { count: number }) {
  const clear = count === 0;
  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center gap-2 rounded-badge border px-3 py-1.5 text-xs font-semibold',
        clear
          ? 'border-border bg-card text-muted-foreground'
          : 'border-status-warning/40 bg-status-warningBg text-status-warning'
      )}
    >
      {!clear && (
        <span className="relative flex h-1.5 w-1.5">
          <span className="absolute inline-flex h-full w-full rounded-full bg-status-warning opacity-60 motion-safe:animate-ping" />
          <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-status-warning" />
        </span>
      )}
      {clear ? 'All clear' : `${count} item${count === 1 ? '' : 's'} need you`}
    </span>
  );
}

export function PlatformDashboard() {
  const token = usePlatformToken();
  const [data, setData] = useState<PlatformDashboardPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [extendingId, setExtendingId] = useState<number | null>(null);
  const [pendingCompanies, setPendingCompanies] = useState<number | null>(null);
  const [pendingReviewers, setPendingReviewers] = useState<number | null>(null);
  const [pendingCandidates, setPendingCandidates] = useState<number | null>(null);

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

  // Pending-work counts for the triage queue. Best-effort: a failed fetch leaves
  // the count null and that triage row is simply omitted.
  useEffect(() => {
    if (!token) return;
    api
      .platformRegistrations(token, 'pending')
      .then((d) => {
        setPendingCompanies(d.company_registrations.filter((r) => r.status === 'pending').length);
        setPendingReviewers(d.reviewer_applications.filter((r) => r.status === 'pending').length);
      })
      .catch(() => undefined);
    api
      .platformCatalogCandidates(token, { reviewStatus: 'pending', perPage: 1 })
      .then((d) => setPendingCandidates(d.pagination?.total ?? 0))
      .catch(() => undefined);
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
  const reportsReady = monitoring ? monitoring.reports.ready : '—';

  const systemHealthLabel = (() => {
    if (!system) return 'Unknown';
    const statuses = Object.values(system.services).map((s) => s.status);
    if (statuses.every((s) => s === 'ok' || s === 'configured')) return 'Healthy';
    if (statuses.some((s) => s === 'error')) return 'Degraded';
    return 'Partial';
  })();

  // Build the triage queue. Each row leads with its count; a 0/unavailable
  // count omits the row entirely.
  const attentionItems: AttentionItemData[] = [];
  if (pendingCompanies && pendingCompanies > 0) {
    attentionItems.push({
      tone: 'attention',
      icon: <Building2 className="h-[18px] w-[18px]" />,
      title: `${pendingCompanies} company registration${pendingCompanies === 1 ? '' : 's'}`,
      detail: 'Awaiting your approval',
      action: { label: 'Review', to: '/platform/registrations' },
    });
  }
  if (pendingReviewers && pendingReviewers > 0) {
    attentionItems.push({
      tone: 'attention',
      icon: <UserPlus className="h-[18px] w-[18px]" />,
      title: `${pendingReviewers} reviewer application${pendingReviewers === 1 ? '' : 's'}`,
      detail: 'Awaiting your approval',
      action: { label: 'Review', to: '/platform/registrations' },
    });
  }
  if (pendingCandidates && pendingCandidates > 0) {
    attentionItems.push({
      tone: 'attention',
      icon: <Inbox className="h-[18px] w-[18px]" />,
      title: `${pendingCandidates} catalog candidate${pendingCandidates === 1 ? '' : 's'}`,
      detail: 'Awaiting curation review',
      action: { label: 'Review', to: '/platform/catalog/candidates' },
    });
  }
  if (trials.length > 0) {
    attentionItems.push({
      tone: 'attention',
      icon: <Clock className="h-[18px] w-[18px]" />,
      title: `${trials.length} trial${trials.length === 1 ? '' : 's'} expiring soon`,
      detail: 'Ending within 7 days — extend below',
      action: { label: 'Manage', to: '/platform/operations?tab=trials' },
    });
  }

  const attentionCount = attentionItems.length;

  if (loading && !data) {
    return <DashboardShell title="Platform" description="Loading cross-tenant work queue…" loading />;
  }

  if (!data) {
    return (
      <DashboardShell
        title="Platform"
        description="Approvals, trials, and cross-tenant health — triaged for you."
        loading={false}
      >
        <EmptyState
          title="Unable to load dashboard"
          description={error || 'Try again shortly, or check platform services.'}
        />
      </DashboardShell>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header + status */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="m-0 font-display text-2xl font-semibold text-foreground">Platform</h1>
          <p className="m-0 mt-1 text-sm text-muted-foreground">
            Approvals, trials, and cross-tenant health — triaged for you.
          </p>
        </div>
        <StatusChip count={attentionCount} />
      </div>

      {error && (
        <div className="rounded-card border border-status-warning/30 bg-status-warningBg px-4 py-3 text-sm text-foreground">
          {error}
        </div>
      )}

      {/* Triage queue */}
      <section className="space-y-4">
        <h2 className="m-0 font-display text-lg font-semibold text-foreground">Needs your attention</h2>
        {attentionCount === 0 ? (
          <EmptyState
            title="You're all caught up"
            description="No registrations, catalog candidates, or expiring trials are waiting on you right now."
          />
        ) : (
          <AttentionList items={attentionItems} />
        )}
      </section>

      {/* Trials — kept with inline Extend action */}
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

      {/* At a glance — demoted secondary KPIs */}
      {monitoring && (
        <section className="space-y-3">
          <h2 className="m-0 font-display text-lg font-semibold text-foreground">At a glance</h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-6">
            <StatCard label="Total companies" value={monitoring.companies.total} icon={<Building2 className="h-5 w-5 text-accent" />} />
            <StatCard label="Active trials" value={activeTrials} icon={<Clock className="h-5 w-5 text-accent" />} />
            <StatCard label="Discovery (24h)" value={monitoring.discovery.conversations_last_24h} icon={<MessageSquare className="h-5 w-5 text-accent" />} />
            <StatCard label="Reports ready" value={reportsReady} icon={<FileText className="h-5 w-5 text-accent" />} />
            <StatCard label="Avg readiness" value={`${monitoring.companies.avg_readiness}%`} icon={<Users className="h-5 w-5 text-accent" />} />
            <StatCard label="System" value={systemHealthLabel} icon={<Activity className="h-5 w-5 text-accent" />} />
          </div>
        </section>
      )}

      {/* Telemetry — secondary monitoring */}
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
    </div>
  );
}
