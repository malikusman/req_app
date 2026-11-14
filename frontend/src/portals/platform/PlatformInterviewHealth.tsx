import { useCallback, useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type InterviewHealthRow } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { Badge, Card, EmptyState, ErrorNotice, Select, Skeleton } from '../../components/ui';

const CLOSE_LABELS: Record<string, string> = {
  dossier_complete: 'covered the role',
  employee_ended: 'employee stopped',
  stalled: 'stalled',
  ceiling: 'hit the question limit',
};

const WINDOWS = [
  { value: '7', label: 'Last 7 days' },
  { value: '30', label: 'Last 30 days' },
  { value: '90', label: 'Last 90 days' },
];

/**
 * How each company's interviews are going, for running a pilot: are people
 * finishing, is anything failing, will the report have hours in it. Companies
 * with something to look at come first.
 */
export function PlatformInterviewHealth() {
  const token = usePlatformToken();
  const [days, setDays] = useState('30');
  const [rows, setRows] = useState<InterviewHealthRow[] | null>(null);
  const [error, setError] = useState('');

  const load = useCallback(() => {
    if (!token) return;
    api
      .interviewHealth(token, Number(days))
      .then((d) => {
        setRows(d.companies);
        setError('');
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Could not load interview health'));
  }, [token, days]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <p className="m-0 max-w-2xl text-sm text-muted-foreground">
          Interviews started in the period, by company. Counts only — nothing anyone said is shown here.
        </p>
        <div className="w-48">
          <Select label="Period" value={days} onChange={(e) => setDays(e.target.value)} options={WINDOWS} />
        </div>
      </div>
      {error && <ErrorNotice message={error} onRetry={load} />}
      {rows === null && !error && <Skeleton variant="card" />}
      {rows?.length === 0 && <EmptyState title="No interviews in this period" />}
      {rows?.map((r) => {
        const closed = Object.values(r.closes).reduce((a, b) => a + b, 0);
        return (
          <Card
            key={r.company.id}
            title={r.company.name}
            action={
              r.flags.length > 0 ? (
                <Badge variant="warning">{r.flags.length} to look at</Badge>
              ) : (
                <Badge variant="success">Healthy</Badge>
              )
            }
          >
            <div className="grid gap-4 text-sm sm:grid-cols-2 lg:grid-cols-4">
              <div>
                <p className="m-0 text-xs text-muted-foreground">Interviews</p>
                <p className="m-0 text-foreground">
                  <strong>{r.interviews.completed}</strong> finished of {r.interviews.started} started
                </p>
                <p className="m-0 text-muted-foreground">
                  {r.interviews.in_progress} in progress · {r.interviews.abandoned} abandoned
                </p>
              </div>
              <div>
                <p className="m-0 text-xs text-muted-foreground">How they ended</p>
                {closed === 0 ? (
                  <p className="m-0 text-muted-foreground">None ended yet</p>
                ) : (
                  Object.entries(r.closes).map(([reason, n]) => (
                    <p key={reason} className="m-0 text-foreground">
                      {n} {CLOSE_LABELS[reason] ?? reason.replace(/_/g, ' ')}
                    </p>
                  ))
                )}
                {r.median_questions != null && (
                  <p className="m-0 text-muted-foreground">median {r.median_questions} questions</p>
                )}
              </div>
              <div>
                <p className="m-0 text-xs text-muted-foreground">Findings</p>
                <p className="m-0 text-foreground">
                  <strong>{r.findings.with_hours}</strong> of {r.findings.live} with hours
                </p>
                <p className="m-0 text-muted-foreground">{r.findings.to_review} waiting for review</p>
              </div>
              <div>
                <p className="m-0 text-xs text-muted-foreground">Recording & voice</p>
                <p className="m-0 text-foreground">
                  {r.capture.turns - r.capture.fallbacks} of {r.capture.turns} answers recorded
                </p>
                <p className="m-0 text-muted-foreground">
                  {r.voice.answers} spoken answers{r.voice.failed > 0 ? ` · ${r.voice.failed} failed` : ''}
                </p>
              </div>
            </div>
            {r.flags.length > 0 && (
              <ul className="m-0 mt-4 list-disc space-y-1 pl-5 text-sm text-foreground">
                {r.flags.map((f) => (
                  <li key={f}>{f}</li>
                ))}
              </ul>
            )}
            <Link
              to={`/platform/companies/${r.company.id}`}
              className="mt-3 inline-block text-sm text-accent hover:underline"
            >
              Open company
            </Link>
          </Card>
        );
      })}
    </div>
  );
}
