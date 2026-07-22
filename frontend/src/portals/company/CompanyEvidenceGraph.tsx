import { useEffect, useState } from 'react';
import { api } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { EvidenceGraphView, type GraphPayload } from '../../components/evidence/EvidenceGraphView';
import { Skeleton } from '../../components/ui';

export function CompanyEvidenceGraph() {
  const token = useCompanyToken();
  const [graph, setGraph] = useState<GraphPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    api
      .companyEvidenceGraph(token)
      .then((d) => setGraph(d.graph as GraphPayload))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load graph'))
      .finally(() => setLoading(false));
  }, [token]);

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {error && <p className="text-sm text-destructive">{error}</p>}
      {graph ? (
        <EvidenceGraphView
          graph={graph}
          documentsHref="/company/documents"
          title="Employee clusters"
          description="See which employees share the same signals and departments."
          breadcrumbs={[
            { label: 'Dashboard', href: '/company/dashboard' },
            { label: 'Employee clusters' },
          ]}
        />
      ) : null}
    </div>
  );
}
