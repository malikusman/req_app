import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type CompanyPattern } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Badge, EmptyState, Skeleton, Button } from '../../components/ui';

export function CompanyPatterns() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const [patterns, setPatterns] = useState<CompanyPattern[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');

  const load = () => {
    if (!token) return;
    setLoadError('');
    api
      .intelligencePatterns(token)
      .then((d) => setPatterns(d.patterns))
      .catch(() => setLoadError('Could not load patterns.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
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

      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      {patterns.length === 0 ? (
        !loadError && (
          <EmptyState
            title="No patterns yet"
            description="Patterns emerge as signals strengthen across departments — upload more docs or complete interviews."
            action={{ label: 'Upload documents', onClick: () => navigate('/company/documents') }}
            secondaryAction={{ label: 'View signals', onClick: () => navigate('/company/intelligence/signals') }}
          />
        )
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
