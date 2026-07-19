import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  FileBarChart,
  FileText,
  Radio,
  AlertTriangle,
  PlayCircle,
} from 'lucide-react';
import { api, type CompanyDashboardPayload } from '../../lib/api';
import { useAuth, useCompanyToken } from '../../lib/auth';
import {
  DashboardShell,
  StatCard,
  Card,
  ReadinessGauge,
  ParticipationSummary,
  StrengthBar,
  Timeline,
  Badge,
  Button,
  EmptyState,
} from '../../components/ui';

export function CompanyDashboard() {
  const token = useCompanyToken();
  const { session } = useAuth();
  const navigate = useNavigate();
  const [data, setData] = useState<CompanyDashboardPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (session?.portal === 'company' && !session.impersonating && !session.company.portal_onboarding_completed_at) {
      navigate('/company/onboarding', { replace: true });
    }
  }, [session, navigate]);

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    setError('');
    api
      .companyDashboard(token)
      .then(setData)
      .catch(() => setError('Could not load discovery dashboard.'))
      .finally(() => setLoading(false));
  }, [token]);

  if (!loading && !data) {
    return (
      <DashboardShell title="Discovery intelligence" description="Live operational snapshot." loading={false}>
        <EmptyState
          title="Unable to load dashboard"
          description={error || 'Complete onboarding, then upload documents or invite employees to start discovery.'}
        />
      </DashboardShell>
    );
  }

  const snapshot = data?.snapshot;
  const p = snapshot?.participation;
  const score = Math.round(data?.report_readiness_score ?? 0);
  const breakdown = data?.report_readiness_breakdown ?? {};
  const readyDocs = Number(breakdown.ready_documents ?? 0);
  const signalCount = snapshot?.top_pain_points.length ?? 0;
  const docsFirstPhase = Boolean(data?.docs_first_phase ?? data?.company.docs_first_phase);
  const docsFirstActive = docsFirstPhase && (readyDocs > 0 || score > 0 || signalCount > 0);
  const processingDocs = docsFirstPhase && readyDocs === 0 && score === 0 && signalCount === 0;

  if (!loading && docsFirstPhase && processingDocs) {
    return (
      <DashboardShell title="Discovery intelligence" description="Start with documents or invite employees." loading={false}>
        <Card>
          <EmptyState
            title="Start discovery"
            description="Upload internal SOPs, policies, or finance exports for a baseline — or invite employees for live interviews. You can do both; intelligence accumulates."
            action={{ label: 'Upload documents', onClick: () => navigate('/company/documents') }}
          />
          <div className="mt-4 flex justify-center">
            <Button variant="secondary" onClick={() => navigate('/company/employees')}>
              Invite employees later
            </Button>
          </div>
        </Card>
      </DashboardShell>
    );
  }

  const docsOnlyView = docsFirstPhase && docsFirstActive;

  return (
    <DashboardShell
      title="Discovery intelligence"
      description={
        docsOnlyView
          ? 'Baseline from internal documents — invite employees later to strengthen evidence.'
          : 'Live operational snapshot — signals, patterns, and recommendations from your program.'
      }
      loading={loading}
      banner={
        error ? (
          <div className="rounded-lg border border-warning/30 bg-warning/10 px-4 py-3 text-sm text-foreground">
            {error}
          </div>
        ) : undefined
      }
      kpiRow={
        p && data ? (
          <>
            <StatCard
              label="Readiness"
              value={`${score}%`}
              icon={<FileBarChart className="h-5 w-5 text-primary" />}
            />
            {docsOnlyView ? (
              <StatCard
                label="Documents"
                value={readyDocs}
                icon={<PlayCircle className="h-5 w-5 text-primary" />}
              />
            ) : (
              <StatCard
                label="In progress"
                value={data.employees_summary.in_progress_count}
                icon={<PlayCircle className="h-5 w-5 text-primary" />}
              />
            )}
            {docsOnlyView ? (
              <StatCard
                label="Doc departments"
                value={Number(breakdown.document_departments ?? 0)}
                icon={<FileText className="h-5 w-5 text-primary" />}
              />
            ) : (
              <StatCard
                label="Stalled"
                value={data.employees_summary.stalled_count}
                icon={<AlertTriangle className="h-5 w-5 text-primary" />}
              />
            )}
            <StatCard
              label="Signals"
              value={signalCount}
              icon={<Radio className="h-5 w-5 text-primary" />}
            />
          </>
        ) : undefined
      }
    >
      {data && snapshot && p && (
        <>
          {docsOnlyView && (
            <Card>
              <div className="flex min-w-0 flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <p className="m-0 text-sm text-muted-foreground">
                  No employees invited yet. Document intelligence is the baseline — interviews strengthen the same signals later.
                </p>
                <Button variant="secondary" className="shrink-0" onClick={() => navigate('/company/employees')}>
                  Invite employees
                </Button>
              </div>
            </Card>
          )}

          {!docsOnlyView && data.employees_summary.stalled_count > 0 && (
            <Card title="Stalled employees">
              <div className="mb-4 flex items-start gap-3 rounded-lg border border-warning/30 bg-warning/10 px-4 py-3 text-sm">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-warning" />
                <div className="min-w-0">
                  <p className="m-0 font-medium text-foreground">
                    {data.employees_summary.stalled_count} employee
                    {data.employees_summary.stalled_count === 1 ? '' : 's'} inactive for 48h+
                  </p>
                  <p className="m-0 mt-1 text-muted-foreground">
                    Send a nudge reminder to help them continue discovery.
                  </p>
                </div>
              </div>
              <div className="space-y-2">
                {data.employees_summary.stalled_employees.map((employee) => (
                  <div
                    key={employee.id}
                    className="flex min-w-0 flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-muted/50 px-4 py-3"
                  >
                    <div className="min-w-0">
                      <p className="m-0 truncate font-medium text-foreground">
                        {employee.display_name || `Employee #${employee.id}`}
                      </p>
                      <p className="m-0 truncate text-xs text-muted-foreground">
                        {employee.department || 'No department'}
                        {employee.last_active_at
                          ? ` · last active ${new Date(employee.last_active_at).toLocaleString()}`
                          : ''}
                      </p>
                    </div>
                    {employee.can_nudge && (
                      <Link to="/company/employees" className="shrink-0">
                        <Button size="sm" variant="secondary">
                          Nudge
                        </Button>
                      </Link>
                    )}
                  </div>
                ))}
              </div>
              <Link to="/company/employees" className="mt-4 inline-block text-sm font-medium text-primary hover:underline">
                Manage employees →
              </Link>
            </Card>
          )}

          <div className="grid min-w-0 gap-4 lg:grid-cols-2">
            <Card title="Participation" className="min-w-0">
              <ParticipationSummary participation={p} departmentCoverage={snapshot.department_coverage} compact />
            </Card>

            <Card title="Report readiness" className="min-w-0">
              <div className="flex min-w-0 flex-col gap-6 md:flex-row md:items-start">
                <div className="mx-auto w-full min-w-0 shrink-0 md:mx-0 md:w-auto">
                  <ReadinessGauge score={score} breakdown={breakdown} docsFirstPhase={docsFirstPhase} />
                </div>
                <div className="min-w-0 flex-1 space-y-3">
                  {data.latest_report && (
                    <p className="text-sm text-foreground">
                      Latest report:{' '}
                      <Badge variant={data.latest_report.status === 'ready' ? 'success' : 'neutral'}>
                        v{data.latest_report.version} — {data.latest_report.status}
                      </Badge>
                    </p>
                  )}
                  {data.usage && (
                    <p className="text-sm text-muted-foreground">
                      Trial conversations: {data.usage.conversations_used}
                      {data.usage.conversation_limit != null ? ` / ${data.usage.conversation_limit}` : ''} used
                    </p>
                  )}
                  <p className="text-sm text-muted-foreground">
                    {snapshot.report_ready
                      ? 'Your organization meets the readiness threshold to generate a discovery report.'
                      : docsOnlyView
                        ? 'Upload more department-tagged documents to increase baseline readiness.'
                        : 'Continue interviews and document uploads to increase readiness.'}
                  </p>
                  <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap">
                    <Link to="/company/reports" className="w-full sm:w-auto">
                      <Button className="w-full sm:w-auto">
                        {snapshot.report_ready ? 'Generate report' : 'View reports'}
                      </Button>
                    </Link>
                    <Link to="/company/recommendations" className="w-full sm:w-auto">
                      <Button variant="secondary" className="w-full sm:w-auto">
                        Recommendations
                        {snapshot.recommendation_count > 0 ? ` (${snapshot.recommendation_count})` : ''}
                      </Button>
                    </Link>
                  </div>
                </div>
              </div>
            </Card>
          </div>

          <div className="grid min-w-0 gap-4 lg:grid-cols-2">
            <Card title="Top pain points" className="min-w-0">
              {snapshot.top_pain_points.length === 0 ? (
                <p className="text-sm text-muted-foreground">
                  {docsOnlyView
                    ? 'Upload procedure or finance documents to surface baseline signals.'
                    : 'Complete more interviews to surface signals.'}
                </p>
              ) : (
                <div className="space-y-4">
                  {snapshot.top_pain_points.map((s) => (
                    <div key={s.id} className="min-w-0">
                      <div className="mb-1 flex justify-between gap-2 text-sm">
                        <span className="min-w-0 truncate font-medium text-foreground">{s.label}</span>
                        <span className="shrink-0 text-muted-foreground">{Math.round(s.strength * 100)}%</span>
                      </div>
                      <StrengthBar strength={s.strength} />
                    </div>
                  ))}
                </div>
              )}
              <Link
                to="/company/intelligence/signals"
                className="mt-4 inline-block text-sm font-medium text-primary hover:underline"
              >
                View all signals →
              </Link>
            </Card>

            <Card title="Emerging patterns" className="min-w-0">
              {(snapshot.emerging_patterns?.length ?? 0) === 0 ? (
                <p className="text-sm text-muted-foreground">Patterns appear when signals repeat across departments.</p>
              ) : (
                <div className="space-y-4">
                  {snapshot.emerging_patterns.map((pattern) => (
                    <div key={pattern.id} className="min-w-0">
                      <div className="mb-1 flex items-start justify-between gap-2 text-sm">
                        <span className="min-w-0 font-medium text-foreground">{pattern.title}</span>
                        <span className="shrink-0 text-muted-foreground">{Math.round(pattern.confidence * 100)}%</span>
                      </div>
                      <StrengthBar strength={pattern.confidence} />
                    </div>
                  ))}
                </div>
              )}
              <Link
                to="/company/intelligence/patterns"
                className="mt-4 inline-block text-sm font-medium text-primary hover:underline"
              >
                View all patterns →
              </Link>
            </Card>
          </div>

          {snapshot.recent_timeline.length > 0 && (
            <Card title="Recent activity" className="min-w-0">
              <Timeline
                events={snapshot.recent_timeline.map((e, i) => ({
                  id: String(i),
                  title: e.title,
                  summary: e.summary,
                  occurredAt: e.occurred_at,
                }))}
              />
              <Link
                to="/company/intelligence/timeline"
                className="mt-4 inline-block text-sm font-medium text-primary hover:underline"
              >
                View full timeline →
              </Link>
            </Card>
          )}
        </>
      )}
    </DashboardShell>
  );
}
