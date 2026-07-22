import { useEffect, useMemo, useRef, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
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

type LaidOutNode = GraphNode & { x: number; y: number; key: string };

// Pulse CVD-safe chart palette — CSS variable strings work directly in SVG fill/stroke.
const CHART_TOKENS = [1, 2, 3, 4, 5, 6].map((i) => `hsl(var(--chart-${i}))`);

const NODE_TYPES = [
  'employee',
  'signal',
  'document',
  'pattern',
  'recommendation',
  'conversation',
  'message',
  'media',
  'finding',
  'outreach',
];

// Cycle the six chart tokens across node types.
const TYPE_COLORS: Record<string, string> = Object.fromEntries(
  NODE_TYPES.map((t, i) => [t, CHART_TOKENS[i % CHART_TOKENS.length]])
);

const TYPE_LABELS: Record<string, string> = {
  employee: 'Employee',
  conversation: 'Conversation',
  message: 'Message',
  document: 'Document',
  media: 'Media',
  signal: 'Signal',
  pattern: 'Pattern',
  recommendation: 'Recommendation',
  finding: 'Finding',
  outreach: 'Outreach',
};

const FILTER_LABELS: Record<string, string> = {
  all: 'All',
  employee: 'Employees',
  conversation: 'Conversations',
  message: 'Messages',
  document: 'Documents',
  media: 'Media',
  signal: 'Signals',
  pattern: 'Patterns',
  recommendation: 'Recommendations',
  finding: 'Findings',
  outreach: 'Outreach',
};

function typeLabel(type: string) {
  return TYPE_LABELS[type] || type.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());
}

const TYPE_RING: Record<string, number> = {
  employee: 0,
  conversation: 1,
  document: 1,
  signal: 2,
  pattern: 2,
  recommendation: 3,
  finding: 3,
  message: 4,
  media: 4,
  outreach: 3,
};

function nodeKey(n: { type: string; id: number }) {
  return `${n.type}:${n.id}`;
}

function layoutNodes(nodes: GraphNode[], width: number, height: number): LaidOutNode[] {
  if (nodes.length === 0) return [];

  const cx = width / 2;
  const cy = height / 2;
  const byRing = new Map<number, GraphNode[]>();
  for (const n of nodes) {
    const ring = TYPE_RING[n.type] ?? 2;
    const list = byRing.get(ring) || [];
    list.push(n);
    byRing.set(ring, list);
  }

  const maxRing = Math.max(...byRing.keys(), 1);
  const baseRadius = Math.min(width, height) * 0.12;
  const ringStep = Math.min(width, height) * 0.14;
  const result: LaidOutNode[] = [];

  for (const [ring, list] of [...byRing.entries()].sort((a, b) => a[0] - b[0])) {
    const r = ring === 0 && list.length === 1 ? 0 : baseRadius + (ring / Math.max(maxRing, 1)) * (ringStep * maxRing);
    list.forEach((n, i) => {
      const angle = (2 * Math.PI * i) / list.length - Math.PI / 2;
      const jitter = (i % 3) * 4;
      result.push({
        ...n,
        key: nodeKey(n),
        x: cx + Math.cos(angle) * (r + jitter),
        y: cy + Math.sin(angle) * (r + jitter * 0.6),
      });
    });
  }

  // Keep nodes inside canvas padding
  const pad = 28;
  for (const n of result) {
    n.x = Math.min(width - pad, Math.max(pad, n.x));
    n.y = Math.min(height - pad, Math.max(pad, n.y));
  }

  return result;
}

export function ReviewerEvidenceGraph() {
  const { companyId } = useParams();
  const token = useReviewerToken();
  const [graph, setGraph] = useState<GraphPayload | null>(null);
  const [filter, setFilter] = useState('all');
  const [selected, setSelected] = useState<GraphNode | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const svgRef = useRef<SVGSVGElement>(null);
  const [size, setSize] = useState({ w: 720, h: 520 });

  useEffect(() => {
    if (!token || !companyId) return;
    setLoading(true);
    api
      .reviewerEvidenceGraph(token, Number(companyId))
      .then((d) => setGraph(d.graph as GraphPayload))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load graph'))
      .finally(() => setLoading(false));
  }, [token, companyId]);

  useEffect(() => {
    const el = svgRef.current?.parentElement;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      const rect = entries[0]?.contentRect;
      if (!rect) return;
      setSize({ w: Math.max(320, rect.width), h: Math.max(400, Math.min(640, rect.width * 0.65)) });
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [loading, graph]);

  const visibleNodes = useMemo(() => {
    const list = graph?.nodes || [];
    if (filter === 'all') return list;
    return list.filter((n) => n.type === filter);
  }, [graph, filter]);

  const laidOut = useMemo(
    () => layoutNodes(visibleNodes, size.w, size.h),
    [visibleNodes, size.w, size.h]
  );

  const positionByKey = useMemo(() => {
    const map = new Map<string, LaidOutNode>();
    for (const n of laidOut) map.set(n.key, n);
    return map;
  }, [laidOut]);

  const visibleKeys = useMemo(() => new Set(laidOut.map((n) => n.key)), [laidOut]);

  const edges = useMemo(() => {
    return (graph?.edges || []).filter(
      (e) => visibleKeys.has(nodeKey(e.from)) && visibleKeys.has(nodeKey(e.to))
    );
  }, [graph, visibleKeys]);

  const connectedKeys = useMemo(() => {
    if (!selected) return null;
    const sel = nodeKey(selected);
    const set = new Set<string>([sel]);
    for (const e of graph?.edges || []) {
      const from = nodeKey(e.from);
      const to = nodeKey(e.to);
      if (from === sel) set.add(to);
      if (to === sel) set.add(from);
    }
    return set;
  }, [selected, graph]);

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  const types = ['all', 'employee', 'document', 'signal', 'pattern', 'recommendation', 'message', 'finding'];

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

      <div className="flex flex-wrap items-center gap-2">
        {types.map((t) => (
          <button
            key={t}
            type="button"
            onClick={() => setFilter(t)}
            className={`rounded-full border px-3 py-1 text-xs ${filter === t ? 'border-primary bg-primary/10' : 'border-border'}`}
          >
            {FILTER_LABELS[t] || typeLabel(t)}
          </button>
        ))}
        <Link
          to={`/reviewer/companies/${companyId}/documents`}
          className="ml-auto text-xs text-primary hover:underline"
        >
          Browse documents
        </Link>
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
        <Card title={`Graph (${laidOut.length} nodes · ${edges.length} edges)`}>
          {laidOut.length === 0 ? (
            <EmptyState title="No nodes" description="Evidence will appear after discovery and intelligence aggregation." />
          ) : (
            <div className="w-full overflow-hidden rounded-md border border-border bg-muted/20">
              <svg
                ref={svgRef}
                width={size.w}
                height={size.h}
                viewBox={`0 0 ${size.w} ${size.h}`}
                className="block max-w-full"
                role="img"
                aria-label="Evidence connection graph"
              >
                {edges.map((e, idx) => {
                  const from = positionByKey.get(nodeKey(e.from));
                  const to = positionByKey.get(nodeKey(e.to));
                  if (!from || !to) return null;
                  const dimmed =
                    connectedKeys &&
                    !connectedKeys.has(from.key) &&
                    !connectedKeys.has(to.key);
                  const highlight =
                    connectedKeys &&
                    connectedKeys.has(from.key) &&
                    connectedKeys.has(to.key);
                  return (
                    <line
                      key={idx}
                      x1={from.x}
                      y1={from.y}
                      x2={to.x}
                      y2={to.y}
                      stroke={highlight ? 'hsl(var(--foreground))' : 'hsl(var(--border))'}
                      strokeWidth={highlight ? 1.75 : 1}
                      opacity={dimmed ? 0.12 : highlight ? 0.9 : 0.45}
                    />
                  );
                })}
                {laidOut.map((n) => {
                  const color = TYPE_COLORS[n.type] || 'hsl(var(--muted-foreground))';
                  const isSelected = selected && nodeKey(selected) === n.key;
                  const dimmed = connectedKeys && !connectedKeys.has(n.key);
                  return (
                    <g
                      key={n.key}
                      transform={`translate(${n.x},${n.y})`}
                      className="cursor-pointer"
                      onClick={() => setSelected(n)}
                      opacity={dimmed ? 0.2 : 1}
                    >
                      <circle
                        r={isSelected ? 14 : 10}
                        fill={color}
                        stroke={isSelected ? 'hsl(var(--foreground))' : 'hsl(var(--card))'}
                        strokeWidth={isSelected ? 2.5 : 1.5}
                      />
                      <title>{`${typeLabel(n.type)}: ${n.label || n.id}`}</title>
                    </g>
                  );
                })}
              </svg>
              <div className="flex flex-wrap gap-3 border-t border-border px-3 py-2 text-[10px] text-text-secondary">
                {Object.entries(TYPE_COLORS)
                  .filter(([t]) => (graph?.nodes || []).some((n) => n.type === t))
                  .map(([t, c]) => (
                    <span key={t} className="inline-flex items-center gap-1">
                      <span className="inline-block h-2 w-2 rounded-full" style={{ background: c }} />
                      {typeLabel(t)}
                    </span>
                  ))}
              </div>
            </div>
          )}
        </Card>

        <Card title="Selection">
          {!selected ? (
            <p className="text-sm text-text-secondary">Click a node to inspect connections.</p>
          ) : (
            <div className="space-y-3 text-sm">
              <div>
                <div className="font-medium">{selected.label || `${typeLabel(selected.type)} ${selected.id}`}</div>
                <div className="text-text-secondary">
                  {typeLabel(selected.type)} {selected.id}
                  {selected.department ? ` · ${selected.department}` : ''}
                </div>
                {typeof selected.confidence === 'number' && (
                  <div className="mt-1">
                    <Badge variant="info">{selected.confidence.toFixed(2)}</Badge>
                  </div>
                )}
              </div>
              <div>
                <div className="mb-1 text-xs uppercase tracking-wide text-text-secondary">Connected edges</div>
                <ul className="max-h-64 space-y-1 overflow-auto">
                  {(graph?.edges || [])
                    .filter(
                      (e) =>
                        (e.from.type === selected.type && e.from.id === selected.id) ||
                        (e.to.type === selected.type && e.to.id === selected.id)
                    )
                    .slice(0, 30)
                    .map((e, idx) => (
                      <li key={idx} className="text-xs">
                        <span className="capitalize text-text-secondary">{e.type.replace(/_/g, ' ')}:</span>{' '}
                        {typeLabel(e.from.type)} {e.from.id} → {typeLabel(e.to.type)} {e.to.id}
                      </li>
                    ))}
                </ul>
              </div>
              {graph?.coverage && (
                <div className="rounded-md border border-border p-3 text-xs text-text-secondary">
                  <div>Nodes: {String(graph.coverage.node_count ?? '—')}</div>
                  <div>Edges: {String(graph.coverage.edge_count ?? '—')}</div>
                </div>
              )}
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}
