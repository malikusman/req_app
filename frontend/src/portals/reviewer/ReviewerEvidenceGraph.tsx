import { useEffect, useMemo, useState } from 'react';
import { useParams } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, Badge, EmptyState, Skeleton } from '../../components/ui';

type GraphNode = {
  type: string;
  id: number;
  label: string;
  department?: string;
  confidence?: number;
  source_type?: string;
};

type GraphEdge = {
  type: string;
  from: { type: string; id: number };
  to: { type: string; id: number };
};

type GraphPayload = {
  nodes: GraphNode[];
  edges: GraphEdge[];
  coverage: Record<string, unknown>;
};

export function ReviewerEvidenceGraph() {
  const { companyId } = useParams();
  const token = useReviewerToken();
  const [graph, setGraph] = useState<GraphPayload | null>(null);
  const [filter, setFilter] = useState('all');
  const [selected, setSelected] = useState<GraphNode | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token || !companyId) return;
    setLoading(true);
    api
      .reviewerEvidenceGraph(token, Number(companyId))
      .then((d) => setGraph(d.graph))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load graph'))
      .finally(() => setLoading(false));
  }, [token, companyId]);

  const nodes = useMemo(() => {
    const list = graph?.nodes || [];
    if (filter === 'all') return list;
    return list.filter((n) => n.type === filter);
  }, [graph, filter]);

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Evidence graph"
        description="How interviews, documents, signals, and recommendations connect."
        breadcrumbs={[
          { label: 'Dashboard', href: '/reviewer/dashboard' },
          { label: 'Company', href: `/reviewer/companies/${companyId}` },
          { label: 'Evidence graph' },
        ]}
      />
      {error && <p className="text-sm text-destructive">{error}</p>}

      <div className="flex flex-wrap gap-2">
        {['all', 'signal', 'pattern', 'recommendation', 'document', 'message', 'employee'].map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setFilter(t)}
            className={`rounded-full border px-3 py-1 text-xs ${filter === t ? 'border-primary bg-primary/10' : 'border-border'}`}
          >
            {t}
          </button>
        ))}
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
        <Card title={`Nodes (${nodes.length})`}>
          {nodes.length === 0 ? (
            <EmptyState title="No nodes" description="Evidence will appear after discovery and intelligence aggregation." />
          ) : (
            <div className="max-h-[560px] space-y-2 overflow-auto">
              {nodes.map((node) => (
                <button
                  key={`${node.type}-${node.id}`}
                  type="button"
                  onClick={() => setSelected(node)}
                  className="flex w-full items-start justify-between rounded-md border border-border px-3 py-2 text-left hover:bg-muted/40"
                >
                  <div>
                    <div className="text-sm font-medium">{node.label || `${node.type} #${node.id}`}</div>
                    <div className="text-xs text-text-secondary">
                      {node.type}
                      {node.department ? ` · ${node.department}` : ''}
                    </div>
                  </div>
                  {typeof node.confidence === 'number' && <Badge variant="info">{node.confidence.toFixed(2)}</Badge>}
                </button>
              ))}
            </div>
          )}
        </Card>
        <Card title="Selection">
          {!selected ? (
            <p className="text-sm text-text-secondary">Select a node to inspect connections.</p>
          ) : (
            <div className="space-y-3 text-sm">
              <div>
                <div className="font-medium">{selected.label}</div>
                <div className="text-text-secondary">
                  {selected.type} #{selected.id}
                </div>
              </div>
              <div>
                <div className="mb-1 text-xs uppercase tracking-wide text-text-secondary">Connected edges</div>
                <ul className="space-y-1">
                  {(graph?.edges || [])
                    .filter(
                      (e) =>
                        (e.from.type === selected.type && e.from.id === selected.id) ||
                        (e.to.type === selected.type && e.to.id === selected.id)
                    )
                    .slice(0, 20)
                    .map((e, idx) => (
                      <li key={idx} className="text-xs">
                        {e.type}: {e.from.type}#{e.from.id} → {e.to.type}#{e.to.id}
                      </li>
                    ))}
                </ul>
              </div>
              {graph?.coverage && (
                <div className="rounded-md border border-border p-3 text-xs">
                  <div>Signals: {String(graph.coverage.signals ?? '—')}</div>
                  <div>Supported edges: {String(graph.coverage.supported_edges ?? '—')}</div>
                </div>
              )}
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}
