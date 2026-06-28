import { Badge, StrengthBar } from '../../../components/ui';
import type { ReportSectionKey } from './workspaceSteps';

type SignalItem = {
  label: string;
  strength: number;
  departments: string[];
  evidence_count?: number;
  multimodal_evidence?: { attachment_type: string; excerpt?: string }[];
  source_excerpts?: { message_id: number; excerpt: string; employee_id?: number }[];
};

export function ReviewerSectionContent({
  section,
  snapshot,
  onJumpToMessage,
}: {
  section: ReportSectionKey;
  snapshot: Record<string, unknown>;
  onJumpToMessage?: (messageId: number) => void;
}) {
  if (section === 'executive_summary') {
    const summary = String(snapshot.executive_summary || '');
    const company = snapshot.company as { name?: string } | undefined;
    return (
      <div className="space-y-3">
        {summary ? (
          <p className="m-0 text-sm leading-relaxed text-foreground">{summary}</p>
        ) : (
          <p className="text-sm text-muted-foreground">
            Discovery report for <strong>{company?.name ?? 'this company'}</strong>. No executive summary was generated.
          </p>
        )}
      </div>
    );
  }

  if (section === 'readiness') {
    const r = snapshot.readiness as { score?: number; breakdown?: Record<string, number> } | undefined;
    return (
      <div className="space-y-3">
        <p className="text-2xl font-semibold text-foreground">{r?.score ?? 0}%</p>
        {r?.breakdown &&
          Object.entries(r.breakdown).map(([k, v]) => (
            <div key={k}>
              <div className="mb-1 flex justify-between text-sm">
                <span className="capitalize">{k.replace(/_/g, ' ')}</span>
                <span>{v}%</span>
              </div>
              <StrengthBar strength={typeof v === 'number' ? v / 100 : 0} />
            </div>
          ))}
      </div>
    );
  }

  if (section === 'participation') {
    const p = snapshot.participation as Record<string, number> | undefined;
    if (!p) return <p className="text-sm text-muted-foreground">No participation data.</p>;
    return (
      <ul className="space-y-2 text-sm">
        {Object.entries(p).map(([k, v]) => (
          <li key={k} className="flex justify-between">
            <span className="capitalize text-muted-foreground">{k.replace(/_/g, ' ')}</span>
            <strong>{typeof v === 'number' && v < 1 ? `${Math.round(v * 100)}%` : v}</strong>
          </li>
        ))}
      </ul>
    );
  }

  if (section === 'delta') {
    const d = snapshot.delta_from_previous as Record<string, unknown> | undefined;
    if (!d) return <p className="text-sm text-muted-foreground">First report — no delta.</p>;
    return <pre className="overflow-auto rounded-lg bg-muted p-3 text-xs">{JSON.stringify(d, null, 2)}</pre>;
  }

  if (section === 'signals') {
    const signals = (snapshot.signals as SignalItem[]) || [];
    if (signals.length === 0) {
      return (
        <p className="text-sm text-muted-foreground">
          No extracted signals in this report. Cross-check agent shared findings and the employee transcript in earlier
          steps.
        </p>
      );
    }
    return (
      <ul className="space-y-4">
        {signals.map((s, i) => (
          <li key={i} className="rounded-lg border border-border p-4">
            <div className="flex justify-between text-sm font-medium">
              <span>{s.label}</span>
              <span>{Math.round(s.strength * 100)}%</span>
            </div>
            <StrengthBar strength={s.strength} className="mt-2" />
            <p className="mt-1 text-xs text-muted-foreground">{s.departments?.join(', ')}</p>
            {s.evidence_count != null && (
              <p className="mt-1 text-xs text-muted-foreground">{s.evidence_count} evidence mentions</p>
            )}
            {s.source_excerpts && s.source_excerpts.length > 0 && (
              <ul className="mt-3 space-y-2 border-t border-border pt-3">
                {s.source_excerpts.map((item) => (
                  <li key={item.message_id} className="text-sm">
                    {onJumpToMessage ? (
                      <button
                        type="button"
                        onClick={() => onJumpToMessage(item.message_id)}
                        className="text-left text-accent hover:underline"
                      >
                        View in transcript
                      </button>
                    ) : null}
                    <p className="m-0 mt-1 text-muted-foreground">&ldquo;{item.excerpt}&rdquo;</p>
                  </li>
                ))}
              </ul>
            )}
            {s.multimodal_evidence && s.multimodal_evidence.length > 0 && (
              <ul className="mt-2 space-y-1 text-xs text-muted-foreground">
                {s.multimodal_evidence.map((item, idx) => (
                  <li key={idx}>
                    {item.attachment_type}: {item.excerpt || 'Supporting media'}
                  </li>
                ))}
              </ul>
            )}
          </li>
        ))}
      </ul>
    );
  }

  if (section === 'patterns') {
    const patterns = (snapshot.patterns as { title: string; description?: string; confidence: number }[]) || [];
    if (patterns.length === 0) {
      return <p className="text-sm text-muted-foreground">No cross-employee patterns yet (common with a single interview).</p>;
    }
    return (
      <ul className="space-y-3">
        {patterns.map((p, i) => (
          <li key={i} className="rounded-lg border border-border p-4">
            <div className="flex justify-between">
              <strong className="text-sm">{p.title}</strong>
              <Badge variant="info">{Math.round(p.confidence * 100)}%</Badge>
            </div>
            {p.description && <p className="mt-1 text-sm text-muted-foreground">{p.description}</p>}
          </li>
        ))}
      </ul>
    );
  }

  if (section === 'recommendations') {
    const recs = (snapshot.recommendations as { title: string; description?: string; priority?: string }[]) || [];
    return (
      <ul className="space-y-3">
        {recs.length === 0 ? (
          <li className="text-sm text-muted-foreground">No recommendations published.</li>
        ) : (
          recs.map((r, i) => (
            <li key={i} className="rounded-lg border border-border p-4">
              <strong className="text-sm">{r.title}</strong>
              {r.priority && (
                <Badge variant="neutral" className="ml-2">
                  {r.priority}
                </Badge>
              )}
              {r.description && <p className="mt-1 text-sm text-muted-foreground">{r.description}</p>}
            </li>
          ))
        )}
      </ul>
    );
  }

  return null;
}
