import { useEffect, useState } from 'react';
import { Server } from 'lucide-react';
import { api, type PlatformSystemHealth } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, StatCard, Badge, Skeleton, EmptyState } from '../../components/ui';

function statusVariant(status: string): 'success' | 'warning' | 'error' {
  if (status === 'ok') return 'success';
  if (status === 'degraded') return 'warning';
  return 'error';
}

export function PlatformSystem() {
  const token = usePlatformToken();
  const [health, setHealth] = useState<PlatformSystemHealth | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    api
      .platformSystem(token)
      .then(setHealth)
      .finally(() => setLoading(false));
  }, [token]);

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <div className="grid gap-4 md:grid-cols-3">
          {[1, 2, 3].map((i) => (
            <Skeleton key={i} variant="card" />
          ))}
        </div>
      </div>
    );
  }

  if (!health) {
    return (
      <div className="space-y-6">
        <PageHeader title="System health" description="Service status and WhatsApp delivery metrics (last 24h)." />
        <EmptyState title="Unable to load system health" description="Try refreshing the page." />
      </div>
    );
  }

  const wa = health.whatsapp_delivery;

  return (
    <div className="space-y-8">
      <PageHeader
        title="System health"
        description="Service status and WhatsApp delivery metrics (last 24h)."
      />

      <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
        {Object.entries(health.services).map(([name, svc]) => (
          <Card key={name} title={name} className="capitalize">
            <Badge variant={statusVariant(svc.status)}>{svc.status}</Badge>
          </Card>
        ))}
      </div>

      <Card title="WhatsApp delivery health">
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard label="Templates sent" value={wa.template_sent} icon={<Server className="h-5 w-5 text-accent" />} />
          <StatCard label="Template failures" value={wa.template_failed} />
          <StatCard label="API errors" value={wa.api_errors} />
          <StatCard label="Failure rate" value={`${wa.failure_rate}%`} />
        </div>
      </Card>
    </div>
  );
}
