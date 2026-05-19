import { useEffect, useState } from 'react';
import { api, type CompanyPattern } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Badge, EmptyState, Skeleton } from '../../components/ui';

export function CompanyPatterns() {
  const token = useCompanyToken();
  const [patterns, setPatterns] = useState<CompanyPattern[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    api
      .intelligencePatterns(token)
      .then((d) => setPatterns(d.patterns))
      .finally(() => setLoading(false));
  }, [token]);

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
        title="Patterns"
        description="Cross-team themes that emerge as signals strengthen."
      />

      {patterns.length === 0 ? (
        <EmptyState title="No patterns yet" description="Patterns emerge as signals strengthen across departments." />
      ) : (
        <div className="grid gap-4 md:grid-cols-2">
          {patterns.map((p) => (
            <Card key={p.id}>
              <div className="flex items-start justify-between gap-2">
                <h3 className="m-0 font-medium text-text-primary">{p.title}</h3>
                <Badge variant="info">{Math.round(p.confidence * 100)}%</Badge>
              </div>
              {p.description && <p className="mt-2 text-sm text-text-secondary">{p.description}</p>}
              <p className="mt-2 text-xs text-text-secondary">{p.departments.join(', ') || 'All departments'}</p>
              <Badge variant="neutral" className="mt-2">
                {p.status}
              </Badge>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
