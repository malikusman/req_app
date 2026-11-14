import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type ReportCheck } from '../../../lib/api';
import { useConsultantToken } from '../../../lib/auth';
import { Button, Card, Skeleton } from '../../../components/ui';
import { ReportChecksList } from '../../shared/ReportChecksList';

/**
 * The same checks platform approval runs (Reports::Critic), shown before the
 * consultant submits so what they can fix — a finding that reads as a quote, one
 * hidden since this version — is fixed before it reaches the approver.
 */
export function ConsultantReportChecksPanel({ companyId, reportId }: { companyId: number; reportId: number }) {
  const token = useConsultantToken();
  const [checks, setChecks] = useState<ReportCheck[] | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const load = useCallback(() => {
    if (!token) return;
    setLoading(true);
    api
      .consultantReportChecks(token, companyId, reportId)
      .then((d) => {
        setChecks(d.checks);
        setError('');
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Could not run the checks'))
      .finally(() => setLoading(false));
  }, [token, companyId, reportId]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <Card
      title="Report checks"
      action={
        <Button size="sm" variant="secondary" onClick={load} loading={loading}>
          Check again
        </Button>
      }
    >
      <p className="mb-3 mt-0 text-sm text-muted-foreground">
        What platform approval checks before the report goes to the client. Anything marked Must fix blocks approval.
        Most are fixed on the{' '}
        <Link to={`/consultant/companies/${companyId}/findings`} className="text-accent hover:underline">
          Findings page
        </Link>
        , then by regenerating the report.
      </p>
      {error && <p className="m-0 text-sm text-destructive">{error}</p>}
      {checks === null && !error ? <Skeleton variant="text" /> : checks && <ReportChecksList checks={checks} />}
    </Card>
  );
}
