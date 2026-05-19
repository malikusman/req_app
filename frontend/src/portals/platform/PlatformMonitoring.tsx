import { useEffect, useState } from 'react';
import { Building2, MessageSquare, FileBarChart, UserCog } from 'lucide-react';
import { api, type PlatformMonitoring } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, StatCard, Card, Skeleton } from '../../components/ui';

export function PlatformMonitoringPage() {
  const token = usePlatformToken();
  const [data, setData] = useState<PlatformMonitoring | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    api
      .platformMonitoring(token)
      .then(setData)
      .finally(() => setLoading(false));
  }, [token]);

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <div className="grid gap-4 md:grid-cols-3">
          {[1, 2, 3, 4, 5].map((i) => (
            <Skeleton key={i} variant="card" />
          ))}
        </div>
      </div>
    );
  }

  if (!data) return null;

  return (
    <div className="space-y-8">
      <PageHeader
        title="Monitoring"
        description="Cross-tenant metrics for operations and billing health."
      />

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        <Card title="Companies">
          <div className="grid gap-3 sm:grid-cols-3">
            <StatCard label="Total" value={data.companies.total} icon={<Building2 className="h-5 w-5 text-accent" />} />
            <StatCard label="Onboarded" value={data.companies.onboarded} />
            <StatCard label="Avg readiness" value={`${data.companies.avg_readiness}%`} />
          </div>
        </Card>

        <Card title="Subscriptions">
          <div className="space-y-2 text-sm text-text-primary">
            {Object.entries(data.subscriptions.by_status).map(([status, count]) => (
              <p key={status} className="m-0 flex justify-between">
                <span className="capitalize text-text-secondary">{status}</span>
                <strong>{count}</strong>
              </p>
            ))}
            <p className="m-0 flex justify-between border-t border-border pt-2">
              <span className="text-text-secondary">Trials expiring (7d)</span>
              <strong>{data.subscriptions.trials_expiring_7d}</strong>
            </p>
            <p className="m-0 flex justify-between">
              <span className="text-text-secondary">At conversation limit</span>
              <strong>{data.subscriptions.at_conversation_limit}</strong>
            </p>
          </div>
        </Card>

        <Card title="Discovery">
          <div className="space-y-3">
            <StatCard
              label="Active conversations"
              value={data.discovery.active_conversations}
              icon={<MessageSquare className="h-5 w-5 text-accent" />}
            />
            <StatCard label="Completed employees" value={data.discovery.completed_employees} />
            <StatCard label="New (24h)" value={data.discovery.conversations_last_24h} />
          </div>
        </Card>

        <Card title="Reports">
          <div className="grid gap-3 sm:grid-cols-3">
            <StatCard label="Ready" value={data.reports.ready} icon={<FileBarChart className="h-5 w-5 text-accent" />} />
            <StatCard label="Generating" value={data.reports.generating} />
            <StatCard label="Failed" value={data.reports.failed} />
          </div>
        </Card>

        <Card title="Impersonation">
          <div className="grid gap-3 sm:grid-cols-2">
            <StatCard
              label="Active sessions"
              value={data.impersonations.active_sessions}
              icon={<UserCog className="h-5 w-5 text-accent" />}
            />
            <StatCard label="Started (24h)" value={data.impersonations.last_24h} />
          </div>
        </Card>
      </div>
    </div>
  );
}
