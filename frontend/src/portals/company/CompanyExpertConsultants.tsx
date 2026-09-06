import { useEffect, useState } from 'react';
import { api, type ConsultantPublicCard } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { Card } from '../../components/ui';
import { ExpertConsultantCard } from '../../components/ExpertConsultantCard';

export function CompanyExpertConsultants({ hideIntro = false }: { hideIntro?: boolean }) {
  const token = useCompanyToken();
  const [consultants, setConsultants] = useState<ConsultantPublicCard[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    api
      .companyExpertConsultants(token)
      .then((d) => setConsultants(d.expert_consultants))
      .catch(() => setConsultants([]))
      .finally(() => setLoading(false));
  }, [token]);

  if (loading) return null;

  return (
    <Card title={hideIntro ? undefined : 'Assigned consultants'}>
      {!hideIntro ? (
        <p className="mb-4 text-sm text-text-secondary">
          {consultants.length === 0
            ? 'Consultants appear here when Worktruth assigns experts to your company and they publish their profile.'
            : 'Independent experts shaping your transformation report — verified by Worktruth.'}
        </p>
      ) : null}
      {consultants.length > 0 ? (
        <div className="grid gap-4 lg:grid-cols-2">
          {consultants.map((r) => (
            <ExpertConsultantCard key={r.id} consultant={r} token={token} />
          ))}
        </div>
      ) : (
        <p className="m-0 text-sm text-muted-foreground">
          No consultant assigned yet — we'll introduce your expert here once they're matched to you.
        </p>
      )}
    </Card>
  );
}
