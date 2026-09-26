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

type ReportFindings = {
  totals: { findings: number; roles: number; hours_min: number | null; hours_max: number | null };
  withheld: number;
  departments: {
    name: string;
    roles: {
      title: string;
      potential: string | null;
      hours_min: number | null;
      hours_max: number | null;
      findings: { id: number; title: string; friction: string | null; hours_min: number | null; hours_max: number | null }[];
    }[];
  }[];
};

function hoursRange(min: number | null, max: number | null) {
  if (min == null) return '';
  const fmt = (n: number) => n.toLocaleString('en');
  return min === max || max == null ? fmt(min) : `${fmt(min)}–${fmt(max)}`;
}

export function ConsultantSectionContent({
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

  if (section === 'role_findings') {
    const view = snapshot.findings as ReportFindings | undefined;
    const departments = view?.departments ?? [];
    if (departments.length === 0) {
      return (
        <p className="text-sm text-muted-foreground">
          No findings reached this version of the report. Findings appear as interviews finish; review them on the
          company&apos;s Findings page, then regenerate.
        </p>
      );
    }
    return (
      <div className="space-y-4">
        <p className="m-0 text-sm text-foreground">
          {view?.totals.findings} findings across {view?.totals.roles} roles
          {view?.totals.hours_min != null && (
            <>
              {' '}
              · <strong>{hoursRange(view.totals.hours_min, view.totals.hours_max)} hours a year</strong>
            </>
          )}
        </p>
        {view && view.withheld > 0 && (
          <p className="m-0 rounded-md bg-warning/10 px-3 py-2 text-sm text-foreground">
            {view.withheld} finding{view.withheld === 1 ? ' is' : 's are'} held back until reviewed — about a role one
            person holds, or a probable double count. Review them on the Findings page, then regenerate.
          </p>
        )}
        {departments.map((d) => (
          <div key={d.name} className="space-y-2">
            <h4 className="m-0 text-sm font-semibold text-foreground">{d.name}</h4>
            {d.roles.map((r) => (
              <div key={r.title} className="rounded-lg border border-border p-3">
                <div className="flex justify-between gap-2 text-sm">
                  <strong>{r.title}</strong>
                  {r.hours_min != null && <span>{hoursRange(r.hours_min, r.hours_max)} h</span>}
                </div>
                {r.potential && <p className="m-0 mt-1 text-xs italic text-muted-foreground">{r.potential}</p>}
                <ul className="m-0 mt-2 space-y-1 pl-4 text-sm text-muted-foreground">
                  {r.findings.map((f) => (
                    <li key={f.id}>
                      <span className="text-foreground">{f.title}</span> — {f.friction}
                      {f.hours_min != null && ` (${hoursRange(f.hours_min, f.hours_max)} h)`}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
        ))}
      </div>
    );
  }

  if (section === 'coverage') {
    const c = snapshot.coverage as
      | { invited: number; completed: number; roles_interviewed: number; not_interviewed: string[];
          departments: { department: string; invited: number; completed: number }[] }
      | undefined;
    if (!c) return <p className="text-sm text-muted-foreground">No coverage data in this version.</p>;
    return (
      <div className="space-y-3 text-sm">
        <p className="m-0">
          {c.completed} of {c.invited} invited took part, covering {c.roles_interviewed} roles.
        </p>
        <ul className="m-0 space-y-1 pl-4">
          {c.departments.map((d) => (
            <li key={d.department}>
              {d.department}: {d.completed} of {d.invited}
            </li>
          ))}
        </ul>
        {c.not_interviewed.length > 0 && (
          <p className="m-0 text-muted-foreground">Not covered: {c.not_interviewed.join(', ')}.</p>
        )}
      </div>
    );
  }

  if (section === 'delta') {
    // Shape built by Reports::DeltaCalculator on the backend.
    const d = snapshot.delta_from_previous as
      | {
          summary?: string;
          new_signals?: { label?: string; strength?: number }[];
          new_patterns?: { title?: string }[];
          new_recommendations?: { title?: string }[];
          strengthened_signals?: { label?: string; strength?: number }[];
        }
      | undefined;
    if (!d) return <p className="text-sm text-muted-foreground">First report — no delta.</p>;
    const withStrength = (label?: string, strength?: number) =>
      typeof strength === 'number' ? `${label ?? 'Untitled'} (${Math.round(strength * 100)}%)` : label ?? 'Untitled';
    const groups = [
      { label: 'New signals', items: (d.new_signals || []).map((s) => withStrength(s.label, s.strength)) },
      { label: 'Strengthened signals', items: (d.strengthened_signals || []).map((s) => withStrength(s.label, s.strength)) },
      { label: 'New patterns', items: (d.new_patterns || []).map((p) => p.title ?? 'Untitled') },
      { label: 'New recommendations', items: (d.new_recommendations || []).map((r) => r.title ?? 'Untitled') },
    ].filter((g) => g.items.length > 0);
    return (
      <div className="space-y-4">
        {d.summary && <p className="m-0 text-sm text-foreground">{d.summary}</p>}
        {groups.length === 0 ? (
          <p className="text-sm text-muted-foreground">No new signals, patterns, or recommendations since the previous report.</p>
        ) : (
          groups.map((g) => (
            <div key={g.label}>
              <p className="m-0 mb-1 text-xs font-medium uppercase tracking-wide text-muted-foreground">{g.label}</p>
              <ul className="m-0 list-disc space-y-1 pl-5 text-sm">
                {g.items.map((item, i) => (
                  <li key={i}>{item}</li>
                ))}
              </ul>
            </div>
          ))
        )}
      </div>
    );
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
            <StrengthBar strength={s.strength} tone="evidence" className="mt-2" />
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
