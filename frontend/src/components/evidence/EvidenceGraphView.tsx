import { useEffect, useMemo, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { Badge, Card, EmptyState } from '../ui';

export type GraphNode = {
  type: string;
  id: number;
  label: string;
  department?: string;
  confidence?: number;
  source_type?: string;
  evidence_count?: number;
};

export type GraphEdge = {
  type: string;
  weight?: number;
  label?: string | null;
  excerpt?: string | null;
  from: { type: string; id: number };
  to: { type: string; id: number };
};

export type GraphPayload = {
  nodes: GraphNode[];
  edges: GraphEdge[];
  coverage: Record<string, unknown>;
};

type LaidOutNode = GraphNode & { x: number; y: number; key: string; radius: number };

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
  clusters: 'Employee clusters',
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

const CLUSTER_NODE_TYPES = new Set(['employee', 'signal', 'pattern']);
const CLUSTER_EDGE_TYPES = new Set([
  'extracted_from',
  'aggregates_into',
  'shares_signal',
  'same_department',
  'supports',
]);

function typeLabel(type: string) {
  return TYPE_LABELS[type] || type.replace(/_/g, ' ').replace(/^./, (c) => c.toUpperCase());
}

function nodeKey(n: { type: string; id: number }) {
  return `${n.type}:${n.id}`;
}

function departmentColor(department: string | undefined, fallback: string) {
  if (!department) return fallback;
  let hash = 0;
  for (let i = 0; i < department.length; i += 1) hash = (hash + department.charCodeAt(i) * (i + 1)) % 6;
  return CHART_TOKENS[hash];
}

function nodeRadius(n: GraphNode) {
  if (n.type !== 'employee') return 10;
  const evidence = Number(n.evidence_count || 0);
  return Math.min(22, 10 + evidence * 2);
}

function layoutRing(nodes: GraphNode[], width: number, height: number): LaidOutNode[] {
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
        radius: nodeRadius(n),
        x: cx + Math.cos(angle) * (r + jitter),
        y: cy + Math.sin(angle) * (r + jitter * 0.6),
      });
    });
  }

  const pad = 28;
  for (const n of result) {
    n.x = Math.min(width - pad, Math.max(pad, n.x));
    n.y = Math.min(height - pad, Math.max(pad, n.y));
  }

  return result;
}

function connectedComponents(employeeIds: number[], shareEdges: GraphEdge[]): number[][] {
  const parent = new Map<number, number>();
  const find = (id: number): number => {
    const p = parent.get(id) ?? id;
    if (p !== id) {
      const root = find(p);
      parent.set(id, root);
      return root;
    }
    return id;
  };
  const union = (a: number, b: number) => {
    const ra = find(a);
    const rb = find(b);
    if (ra !== rb) parent.set(ra, rb);
  };

  employeeIds.forEach((id) => parent.set(id, id));
  for (const e of shareEdges) {
    if (e.from.type === 'employee' && e.to.type === 'employee') union(e.from.id, e.to.id);
  }

  const groups = new Map<number, number[]>();
  for (const id of employeeIds) {
    const root = find(id);
    const list = groups.get(root) || [];
    list.push(id);
    groups.set(root, list);
  }
  return [...groups.values()];
}

function layoutClusters(
  nodes: GraphNode[],
  edges: GraphEdge[],
  width: number,
  height: number
): LaidOutNode[] {
  const employees = nodes.filter((n) => n.type === 'employee');
  const signals = nodes.filter((n) => n.type === 'signal');
  const patterns = nodes.filter((n) => n.type === 'pattern');
  if (employees.length === 0 && signals.length === 0 && patterns.length === 0) return [];

  const shareEdges = edges.filter((e) => e.type === 'shares_signal' || e.type === 'same_department');
  const components = connectedComponents(
    employees.map((e) => e.id),
    shareEdges
  );
  if (components.length === 0 && employees.length === 0) {
    return layoutRing([...signals, ...patterns], width, height);
  }

  const cols = Math.max(1, Math.ceil(Math.sqrt(Math.max(components.length, 1))));
  const rows = Math.max(1, Math.ceil(components.length / cols));
  const cellW = width / cols;
  const cellH = height / rows;
  const byId = new Map(employees.map((e) => [e.id, e]));
  const result: LaidOutNode[] = [];

  components.forEach((ids, index) => {
    const col = index % cols;
    const row = Math.floor(index / cols);
    const cx = cellW * col + cellW / 2;
    const cy = cellH * row + cellH / 2;
    const radius = Math.min(cellW, cellH) * 0.28;
    ids.forEach((id, i) => {
      const emp = byId.get(id);
      if (!emp) return;
      const angle = (2 * Math.PI * i) / Math.max(ids.length, 1) - Math.PI / 2;
      const r = ids.length === 1 ? 0 : radius;
      result.push({
        ...emp,
        key: nodeKey(emp),
        radius: nodeRadius(emp),
        x: cx + Math.cos(angle) * r,
        y: cy + Math.sin(angle) * r,
      });
    });
  });

  const employeePos = new Map(result.filter((n) => n.type === 'employee').map((n) => [n.id, n]));

  const placeNearEmployees = (node: GraphNode, linkedEmployeeIds: number[], slot: number) => {
    const anchors = linkedEmployeeIds.map((id) => employeePos.get(id)).filter(Boolean) as LaidOutNode[];
    let x = width / 2;
    let y = height / 2;
    if (anchors.length > 0) {
      x = anchors.reduce((sum, a) => sum + a.x, 0) / anchors.length;
      y = anchors.reduce((sum, a) => sum + a.y, 0) / anchors.length;
      const angle = (slot % 8) * (Math.PI / 4);
      x += Math.cos(angle) * 36;
      y += Math.sin(angle) * 36;
    }
    result.push({ ...node, key: nodeKey(node), radius: nodeRadius(node), x, y });
  };

  signals.forEach((signal, idx) => {
    const linked = edges
      .filter(
        (e) =>
          e.type === 'extracted_from' &&
          ((e.from.type === 'signal' && e.from.id === signal.id && e.to.type === 'employee') ||
            (e.to.type === 'signal' && e.to.id === signal.id && e.from.type === 'employee'))
      )
      .map((e) => (e.from.type === 'employee' ? e.from.id : e.to.id));
    placeNearEmployees(signal, linked, idx);
  });

  patterns.forEach((pattern, idx) => {
    const linkedSignals = edges
      .filter(
        (e) =>
          e.type === 'aggregates_into' &&
          e.to.type === 'pattern' &&
          e.to.id === pattern.id &&
          e.from.type === 'signal'
      )
      .map((e) => e.from.id);
    const linkedEmployees = edges
      .filter(
        (e) =>
          e.type === 'extracted_from' &&
          e.from.type === 'signal' &&
          linkedSignals.includes(e.from.id) &&
          e.to.type === 'employee'
      )
      .map((e) => e.to.id);
    placeNearEmployees(pattern, linkedEmployees, idx + 3);
  });

  const pad = 28;
  for (const n of result) {
    n.x = Math.min(width - pad, Math.max(pad, n.x));
    n.y = Math.min(height - pad, Math.max(pad, n.y));
  }

  return result;
}

function labelForRef(
  ref: { type: string; id: number },
  nodesByKey: Map<string, GraphNode>
): string {
  const node = nodesByKey.get(nodeKey(ref));
  if (!node) return `${typeLabel(ref.type)} ${ref.id}`;
  return node.label || `${typeLabel(ref.type)} ${ref.id}`;
}

export function EvidenceGraphView({
  graph,
  documentsHref,
  title = 'Evidence graph',
  description = 'How interviews, documents, signals, and recommendations connect.',
  breadcrumbs,
}: {
  graph: GraphPayload;
  documentsHref?: string;
  title?: string;
  description?: string;
  breadcrumbs?: { label: string; href?: string }[];
}) {
  const [filter, setFilter] = useState('clusters');
  const [selected, setSelected] = useState<GraphNode | null>(null);
  const svgRef = useRef<SVGSVGElement>(null);
  const [size, setSize] = useState({ w: 720, h: 520 });

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
  }, [graph]);

  const clusterMode = filter === 'clusters';

  const visibleNodes = useMemo(() => {
    const list = graph.nodes || [];
    if (filter === 'all') return list;
    if (clusterMode) return list.filter((n) => CLUSTER_NODE_TYPES.has(n.type));
    return list.filter((n) => n.type === filter);
  }, [graph, filter, clusterMode]);

  const candidateEdges = useMemo(() => {
    const list = graph.edges || [];
    if (!clusterMode) return list;
    return list.filter((e) => CLUSTER_EDGE_TYPES.has(e.type));
  }, [graph, clusterMode]);

  const laidOut = useMemo(() => {
    if (clusterMode) return layoutClusters(visibleNodes, candidateEdges, size.w, size.h);
    return layoutRing(visibleNodes, size.w, size.h);
  }, [visibleNodes, candidateEdges, size.w, size.h, clusterMode]);

  const positionByKey = useMemo(() => {
    const map = new Map<string, LaidOutNode>();
    for (const n of laidOut) map.set(n.key, n);
    return map;
  }, [laidOut]);

  const nodesByKey = useMemo(() => {
    const map = new Map<string, GraphNode>();
    for (const n of graph.nodes || []) map.set(nodeKey(n), n);
    return map;
  }, [graph]);

  const visibleKeys = useMemo(() => new Set(laidOut.map((n) => n.key)), [laidOut]);

  const edges = useMemo(() => {
    return candidateEdges.filter(
      (e) => visibleKeys.has(nodeKey(e.from)) && visibleKeys.has(nodeKey(e.to))
    );
  }, [candidateEdges, visibleKeys]);

  const connectedKeys = useMemo(() => {
    if (!selected) return null;
    const sel = nodeKey(selected);
    const set = new Set<string>([sel]);
    for (const e of graph.edges || []) {
      const from = nodeKey(e.from);
      const to = nodeKey(e.to);
      if (from === sel) set.add(to);
      if (to === sel) set.add(from);
    }
    return set;
  }, [selected, graph]);

  const selectedEdges = useMemo(() => {
    if (!selected) return [];
    return (graph.edges || [])
      .filter(
        (e) =>
          (e.from.type === selected.type && e.from.id === selected.id) ||
          (e.to.type === selected.type && e.to.id === selected.id)
      )
      .slice(0, 40);
  }, [selected, graph]);

  const sharedSignalsForEmployee = useMemo(() => {
    if (!selected || selected.type !== 'employee') return [];
    const signalIds = new Set<number>();
    for (const e of graph.edges || []) {
      if (e.type !== 'extracted_from') continue;
      if (e.to.type === 'employee' && e.to.id === selected.id && e.from.type === 'signal') {
        signalIds.add(e.from.id);
      }
    }
    return (graph.nodes || []).filter((n) => n.type === 'signal' && signalIds.has(n.id));
  }, [selected, graph]);

  const types = [
    'clusters',
    'all',
    'employee',
    'document',
    'signal',
    'pattern',
    'recommendation',
    'message',
    'finding',
  ];

  return (
    <div className="space-y-6">
      {(title || breadcrumbs) && (
        <div className="space-y-1">
          {breadcrumbs && breadcrumbs.length > 0 && (
            <nav className="flex flex-wrap gap-1 text-xs text-muted-foreground">
              {breadcrumbs.map((crumb, idx) => (
                <span key={`${crumb.label}-${idx}`} className="inline-flex items-center gap-1">
                  {idx > 0 ? <span>/</span> : null}
                  {crumb.href ? (
                    <Link to={crumb.href} className="hover:text-foreground hover:underline">
                      {crumb.label}
                    </Link>
                  ) : (
                    <span>{crumb.label}</span>
                  )}
                </span>
              ))}
            </nav>
          )}
          {title ? <h1 className="text-2xl font-semibold tracking-tight text-foreground">{title}</h1> : null}
          {description ? <p className="text-sm text-muted-foreground">{description}</p> : null}
        </div>
      )}

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
        {documentsHref ? (
          <Link to={documentsHref} className="ml-auto text-xs text-primary hover:underline">
            Browse documents
          </Link>
        ) : null}
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
        <Card title={`Graph (${laidOut.length} nodes · ${edges.length} edges)`}>
          {laidOut.length === 0 ? (
            <EmptyState
              title="No nodes"
              description="Evidence will appear after discovery and intelligence aggregation."
            />
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
                    connectedKeys && !connectedKeys.has(from.key) && !connectedKeys.has(to.key);
                  const highlight =
                    connectedKeys && connectedKeys.has(from.key) && connectedKeys.has(to.key);
                  const weight = Math.min(6, Math.max(1, Number(e.weight || 1)));
                  return (
                    <line
                      key={idx}
                      x1={from.x}
                      y1={from.y}
                      x2={to.x}
                      y2={to.y}
                      stroke={
                        e.type === 'shares_signal'
                          ? 'hsl(var(--chart-1))'
                          : highlight
                            ? 'hsl(var(--foreground))'
                            : 'hsl(var(--border))'
                      }
                      strokeWidth={highlight ? weight + 0.5 : weight}
                      opacity={dimmed ? 0.1 : highlight ? 0.95 : e.type === 'shares_signal' ? 0.55 : 0.4}
                    />
                  );
                })}
                {laidOut.map((n) => {
                  const color =
                    n.type === 'employee'
                      ? departmentColor(n.department, TYPE_COLORS.employee)
                      : TYPE_COLORS[n.type] || 'hsl(var(--muted-foreground))';
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
                        r={isSelected ? n.radius + 3 : n.radius}
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
                  .filter(([t]) => (graph.nodes || []).some((n) => n.type === t))
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
            <p className="text-sm text-text-secondary">
              Click a node to inspect cluster links and evidence.
            </p>
          ) : (
            <div className="space-y-3 text-sm">
              <div>
                <div className="font-medium">{selected.label || `${typeLabel(selected.type)} ${selected.id}`}</div>
                <div className="text-text-secondary">
                  {typeLabel(selected.type)}
                  {selected.department ? ` · ${selected.department}` : ''}
                  {typeof selected.evidence_count === 'number' && selected.type === 'employee'
                    ? ` · ${selected.evidence_count} linked signal${selected.evidence_count === 1 ? '' : 's'}`
                    : ''}
                </div>
                {typeof selected.confidence === 'number' && (
                  <div className="mt-1">
                    <Badge variant="info">{selected.confidence.toFixed(2)}</Badge>
                  </div>
                )}
              </div>

              {sharedSignalsForEmployee.length > 0 && (
                <div>
                  <div className="mb-1 text-xs uppercase tracking-wide text-text-secondary">Shared signals</div>
                  <ul className="max-h-28 space-y-1 overflow-auto">
                    {sharedSignalsForEmployee.map((s) => (
                      <li key={s.id} className="text-xs">
                        {s.label}
                      </li>
                    ))}
                  </ul>
                </div>
              )}

              <div>
                <div className="mb-1 text-xs uppercase tracking-wide text-text-secondary">Connected edges</div>
                <ul className="max-h-64 space-y-1 overflow-auto">
                  {selectedEdges.map((e, idx) => (
                    <li key={idx} className="text-xs">
                      <span className="capitalize text-text-secondary">{e.type.replace(/_/g, ' ')}</span>
                      {e.weight && e.weight > 1 ? ` ×${e.weight}` : ''}:{' '}
                      {labelForRef(e.from, nodesByKey)} → {labelForRef(e.to, nodesByKey)}
                      {e.excerpt ? (
                        <div className="mt-0.5 text-[11px] text-muted-foreground">“{e.excerpt}”</div>
                      ) : null}
                    </li>
                  ))}
                </ul>
              </div>

              {graph.coverage && (
                <div className="rounded-md border border-border p-3 text-xs text-text-secondary">
                  <div>Nodes: {String(graph.coverage.node_count ?? '—')}</div>
                  <div>Edges: {String(graph.coverage.edge_count ?? '—')}</div>
                  <div>Supported links: {String(graph.coverage.supported_edges ?? '—')}</div>
                  <div>Shared-signal links: {String(graph.coverage.shares_signal_edges ?? '—')}</div>
                </div>
              )}
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}
