import { useEffect, useState } from 'react';
import { api, type Recommendation } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Button, Badge, EmptyState, Skeleton } from '../../components/ui';

export function CompanyRecommendations() {
  const token = useCompanyToken();
  const [recs, setRecs] = useState<Recommendation[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    api
      .companyRecommendations(token)
      .then((d) => setRecs(d.recommendations))
      .finally(() => setLoading(false));
  }, [token]);

  const submitFeedback = async (id: number, feedback: string) => {
    if (!token) return;
    await api.recommendationFeedback(token, id, feedback);
    const d = await api.companyRecommendations(token);
    setRecs(d.recommendations);
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Recommendations"
        description="AI-generated opportunities with matched solutions from our catalog."
      />

      {recs.length === 0 ? (
        <EmptyState title="No recommendations" description="Complete discovery interviews to generate recommendations." />
      ) : (
        recs.map((r) => (
          <Card key={r.id}>
            <div className="mb-2 flex items-center gap-2">
              <h3 className="m-0 font-medium text-text-primary">{r.title}</h3>
              <Badge variant={r.priority === 'high' ? 'warning' : 'info'}>{r.priority}</Badge>
            </div>
            {r.description && <p className="text-sm text-text-secondary">{r.description}</p>}
            {r.implementation_outline && (
              <p className="text-sm text-text-primary">{r.implementation_outline}</p>
            )}
            {r.catalog_matches?.length > 0 && (
              <div className="mt-3">
                <p className="text-sm font-medium text-text-primary">Suggested tools</p>
                <ul className="mt-1 list-inside list-disc text-sm text-text-secondary">
                  {r.catalog_matches.map((c, i) => (
                    <li key={i}>
                      {c.name}
                      {c.vendor ? ` (${c.vendor})` : ''}
                    </li>
                  ))}
                </ul>
              </div>
            )}
            <div className="mt-4 flex flex-wrap gap-2">
              {(['interested', 'already_doing', 'not_relevant'] as const).map((f) => (
                <Button
                  key={f}
                  variant={r.company_feedback === f ? 'primary' : 'secondary'}
                  size="sm"
                  onClick={() => submitFeedback(r.id, f)}
                >
                  {f.replace(/_/g, ' ')}
                </Button>
              ))}
            </div>
          </Card>
        ))
      )}
    </div>
  );
}
