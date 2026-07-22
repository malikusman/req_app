import { useEffect, useMemo, useState } from 'react';
import { api, type CompanyPattern, type CompanySignal } from '../../../lib/api';
import { useReviewerToken } from '../../../lib/auth';
import { Card, Button, Textarea, Select, Badge } from '../../../components/ui';
import { REPORT_SECTIONS } from './workspaceSteps';

type Finding = {
  id: number;
  finding_type: string;
  severity: string;
  body: string;
  publishable: boolean;
  disposition?: string | null;
  section_key?: string | null;
  evidence_refs?: string[] | null;
};

const FINDING_TYPES = [
  { value: 'executive_conclusion', label: 'Executive conclusion' },
  { value: 'evidence_sufficiency', label: 'Evidence sufficiency' },
  { value: 'correction', label: 'Material correction' },
  { value: 'risk', label: 'Risk / assumption' },
  { value: 'recommendation_disposition', label: 'Recommendation disposition' },
  { value: 'catalog_assessment', label: 'Catalog / tool fit' },
  { value: 'unresolved_followup', label: 'Unresolved follow-up' },
];

const DISPOSITIONS = [
  { value: '', label: 'None' },
  { value: 'endorse', label: 'Endorse' },
  { value: 'modify', label: 'Modify' },
  { value: 'reject', label: 'Reject' },
  { value: 'needs_more_evidence', label: 'Needs more evidence' },
  { value: 'approve', label: 'Approve' },
  { value: 'needs_info', label: 'Needs info' },
];

const SECTION_OPTIONS = [
  { value: '', label: 'Report-wide' },
  ...REPORT_SECTIONS.map((key) => ({
    value: key,
    label: key.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase()),
  })),
];

function severityVariant(severity: string): 'info' | 'warning' | 'error' {
  if (severity === 'critical') return 'error';
  if (severity === 'material') return 'warning';
  return 'info';
}

function refLabel(ref: string, signals: CompanySignal[], patterns: CompanyPattern[]): string {
  const [kind, idRaw] = ref.split(':');
  const id = Number(idRaw);
  if (kind === 'signal') {
    const signal = signals.find((s) => s.id === id);
    return signal ? `Signal: ${signal.label}` : ref;
  }
  if (kind === 'pattern') {
    const pattern = patterns.find((p) => p.id === id);
    return pattern ? `Pattern: ${pattern.title}` : ref;
  }
  return ref;
}

export function ReviewerStructuredFindingsPanel({
  companyId,
  reportId,
  readOnly,
}: {
  companyId: number;
  reportId: number;
  readOnly?: boolean;
}) {
  const token = useReviewerToken();
  const [findings, setFindings] = useState<Finding[]>([]);
  const [signals, setSignals] = useState<CompanySignal[]>([]);
  const [patterns, setPatterns] = useState<CompanyPattern[]>([]);
  const [findingType, setFindingType] = useState('executive_conclusion');
  const [severity, setSeverity] = useState('info');
  const [disposition, setDisposition] = useState('');
  const [sectionKey, setSectionKey] = useState('');
  const [selectedRefs, setSelectedRefs] = useState<string[]>([]);
  const [body, setBody] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const load = () => {
    if (!token) return;
    api
      .reviewerReportFindings(token, companyId, reportId)
      .then((d) => setFindings(d.findings as Finding[]))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load findings'));
  };

  useEffect(() => {
    load();
  }, [token, companyId, reportId]);

  useEffect(() => {
    if (!token) return;
    Promise.all([api.reviewerSignals(token, companyId), api.reviewerPatterns(token, companyId)])
      .then(([signalPayload, patternPayload]) => {
        setSignals(signalPayload.signals);
        setPatterns(patternPayload.patterns);
      })
      .catch(() => {
        /* Evidence picker stays empty; findings still work without links. */
      });
  }, [token, companyId]);

  const evidenceOptions = useMemo(() => {
    const signalOpts = signals.map((s) => ({
      value: `signal:${s.id}`,
      label: `Signal · ${s.label}`,
    }));
    const patternOpts = patterns.map((p) => ({
      value: `pattern:${p.id}`,
      label: `Pattern · ${p.title}`,
    }));
    return [...signalOpts, ...patternOpts];
  }, [signals, patterns]);

  const toggleRef = (value: string) => {
    setSelectedRefs((prev) => {
      if (prev.includes(value)) return prev.filter((ref) => ref !== value);
      if (prev.length >= 12) return prev;
      return [...prev, value];
    });
  };

  const create = async () => {
    if (!token || !body.trim()) return;
    setSaving(true);
    setError('');
    try {
      await api.createReviewerReportFinding(token, companyId, reportId, {
        finding_type: findingType,
        severity,
        body: body.trim(),
        publishable: true,
        disposition: disposition || null,
        section_key: sectionKey || null,
        evidence_refs: selectedRefs,
      });
      setBody('');
      setSelectedRefs([]);
      setDisposition('');
      setSectionKey('');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to save finding');
    } finally {
      setSaving(false);
    }
  };

  const hasExecutive = findings.some((f) => f.finding_type === 'executive_conclusion' && f.publishable);

  return (
    <Card title="Structured expert findings">
      <p className="mb-3 text-sm text-text-secondary">
        Publishable findings are included in the final PDF. Link real signals or patterns and set a disposition so the
        appendix reads as a complete shared artifact. An executive conclusion is required before submit.
      </p>
      {error && <p className="mb-2 text-sm text-destructive">{error}</p>}
      <div className="mb-3">
        <Badge variant={hasExecutive ? 'success' : 'warning'}>
          {hasExecutive ? 'Executive conclusion present' : 'Executive conclusion required'}
        </Badge>
      </div>
      <ul className="mb-4 space-y-2">
        {findings.map((f) => (
          <li key={f.id} className="rounded-md border border-border px-3 py-2 text-sm">
            <div className="mb-1 flex flex-wrap items-center gap-2 text-xs text-text-secondary">
              <span className="capitalize">{f.finding_type.replace(/_/g, ' ')}</span>
              <Badge variant={severityVariant(f.severity)}>{f.severity}</Badge>
              {f.disposition ? (
                <Badge variant="info">{f.disposition.replace(/_/g, ' ')}</Badge>
              ) : null}
              {f.section_key ? <span>· {f.section_key.replace(/_/g, ' ')}</span> : null}
              {f.publishable ? <Badge variant="success">publishable</Badge> : null}
            </div>
            <p className="m-0">{f.body}</p>
            {Array.isArray(f.evidence_refs) && f.evidence_refs.length > 0 ? (
              <div className="mt-2 flex flex-wrap gap-1.5">
                {f.evidence_refs.map((ref) => (
                  <span
                    key={`${f.id}-${ref}`}
                    className="rounded bg-muted px-2 py-0.5 text-[11px] text-muted-foreground"
                  >
                    {refLabel(ref, signals, patterns)}
                  </span>
                ))}
              </div>
            ) : null}
          </li>
        ))}
      </ul>
      {!readOnly && (
        <div className="space-y-3">
          <Select
            label="Finding type"
            value={findingType}
            onChange={(e) => setFindingType(e.target.value)}
            options={FINDING_TYPES}
          />
          <div className="grid gap-3 sm:grid-cols-2">
            <Select
              label="Severity"
              value={severity}
              onChange={(e) => setSeverity(e.target.value)}
              options={[
                { value: 'info', label: 'Info' },
                { value: 'material', label: 'Material' },
                { value: 'critical', label: 'Critical' },
              ]}
            />
            <Select
              label="Disposition"
              value={disposition}
              onChange={(e) => setDisposition(e.target.value)}
              options={DISPOSITIONS}
            />
          </div>
          <Select
            label="Section (optional)"
            value={sectionKey}
            onChange={(e) => setSectionKey(e.target.value)}
            options={SECTION_OPTIONS}
          />
          <Textarea
            label="Finding"
            rows={4}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="State the judgment, evidence sufficiency, risk, or recommendation disposition…"
          />
          <div>
            <p className="mb-2 text-sm font-medium text-foreground">Evidence links (optional)</p>
            {evidenceOptions.length === 0 ? (
              <p className="m-0 text-xs text-muted-foreground">No signals or patterns available to link yet.</p>
            ) : (
              <div className="flex max-h-40 flex-wrap gap-2 overflow-y-auto rounded-md border border-border p-2">
                {evidenceOptions.map((opt) => {
                  const selected = selectedRefs.includes(opt.value);
                  return (
                    <button
                      key={opt.value}
                      type="button"
                      onClick={() => toggleRef(opt.value)}
                      className={`rounded-full border px-2.5 py-1 text-left text-xs transition-colors ${
                        selected
                          ? 'border-primary bg-primary/10 text-foreground'
                          : 'border-border bg-background text-muted-foreground hover:border-primary/40'
                      }`}
                    >
                      {opt.label}
                    </button>
                  );
                })}
              </div>
            )}
            <p className="mt-1.5 m-0 text-xs text-muted-foreground">
              Select up to 12 real signals or patterns. Free-text refs are no longer accepted.
            </p>
          </div>
          <Button loading={saving} onClick={create} disabled={!body.trim()}>
            Add finding
          </Button>
        </div>
      )}
    </Card>
  );
}
