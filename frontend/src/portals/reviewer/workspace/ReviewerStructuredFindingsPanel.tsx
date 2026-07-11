import { useEffect, useState } from 'react';
import { api } from '../../../lib/api';
import { useReviewerToken } from '../../../lib/auth';
import { Card, Button, Textarea, Select, Badge } from '../../../components/ui';

type Finding = {
  id: number;
  finding_type: string;
  severity: string;
  body: string;
  publishable: boolean;
  disposition?: string | null;
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
  const [findingType, setFindingType] = useState('executive_conclusion');
  const [severity, setSeverity] = useState('info');
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
      });
      setBody('');
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
        Publishable findings are included in the final PDF. An executive conclusion is required before submit.
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
            <div className="mb-1 flex flex-wrap gap-2 text-xs text-text-secondary">
              <span>{f.finding_type.replace(/_/g, ' ')}</span>
              <span>· {f.severity}</span>
              {f.publishable ? <Badge variant="info">publishable</Badge> : null}
            </div>
            <p className="m-0">{f.body}</p>
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
          <Textarea
            label="Finding"
            rows={4}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="State the judgment, evidence sufficiency, risk, or recommendation disposition…"
          />
          <Button loading={saving} onClick={create} disabled={!body.trim()}>
            Add finding
          </Button>
        </div>
      )}
    </Card>
  );
}
