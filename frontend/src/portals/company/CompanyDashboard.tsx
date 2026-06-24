import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Users, CheckCircle2, Percent, FileBarChart, Radio, Lightbulb, AlertTriangle } from 'lucide-react';
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
          description={error || 'Complete onboarding and invite employees to start discovery.'}
        />
      </DashboardShell>
    );
  }

  const snapshot = data?.snapshot;
  const p = snapshot?.participation;
  const score = Math.round(data?.report_readiness_score ?? 0);
  const breakdown = data?.report_readiness_breakdown ?? {};

  if (!loading && p && p.invited === 0) {
    return (
      <DashboardShell title="Discovery intelligence" description="Get started with your discovery program." loading={false}>
        <Card>
          <EmptyState
            title="Invite your first employees"
            description="Add employees to begin WhatsApp discovery interviews and build your operational snapshot."
            action={{ label: 'Invite employees', onClick: () => navigate('/company/employees') }}
          />
        </Card>
      </DashboardShell>
    );
  }

  return (
    <DashboardShell
      title="Discovery intelligence"
      description="Live operational snapshot — signals, patterns, and recommendations from your program."
      loading={loading}
      banner={
        error ? (
          <div className="rounded-card border border-status-warning/30 bg-status-warningBg px-4 py-3 text-sm">{error}</div>
        ) : undefined
      }
      kpiRow={
        p ? (
          <>
            <StatCard label="Readiness" value={`${score}%`} icon={<FileBarChart className="h-5 w-5 text-accent" />} />
            <StatCard label="Invited" value={p.invited} icon={<Users className="h-5 w-5 text-accent" />} />
            <StatCard label="Completed" value={p.completed} icon={<CheckCircle2 className="h-5 w-5 text-accent" />} />
            <StatCard
              label="Completion rate"
              value={`${Math.round(p.completion_rate * 100)}%`}
              icon={<Percent className="h-5 w-5 text-accent" />}
            />
          </>
        ) : undefined
      }
    >
      {data && snapshot && p && (
        <>
          {data.employees_summary.stalled_count > 0 && (
            <Card title="Stalled employees">
              <div className="mb-4 flex items-start gap-3 rounded-button border border-status-warning/30 bg-status-warningBg px-4 py-3 text-sm">
                <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-status-warning" />
                <div>
                  <p className="m-0 font-medium text-text-primary">
                    {data.employees_summary.stalled_count} employee
                    {data.employees_summary.stalled_count === 1 ? '' : 's'} inactive for 48h+
                  </p>
                  <p className="mt-1 m-0 text-text-secondary">
                    Send a nudge reminder to help them continue discovery.
                  </p>
                </div>
              </div>
              <div className="space-y-2">
                {data.employees_summary.stalled_employees.map((employee) => (
                  <div
                    key={employee.id}
                    className="flex flex-wrap items-center justify-between gap-3 rounded-card border border-border bg-surface-muted px-4 py-3"
                  >
                    <div>
                      <p className="m-0 font-medium">{employee.display_name || `Employee #${employee.id}`}</p>
                      <p className="m-0 text-xs text-text-secondary">
                        {employee.department || 'No department'}
                        {employee.last_active_at
                          ? ` · last active ${new Date(employee.last_active_at).toLocaleString()}`
                          : ''}
                      </p>
                    </div>
                    {employee.can_nudge && (
                      <Link to="/company/employees">
                        <Button size="sm" variant="secondary">
                          Nudge
                        </Button>
                      </Link>
                    )}
                  </div>
                ))}
              </div>
              <Link to="/company/employees" className="mt-4 inline-block text-sm font-medium text-accent hover:underline">
                Manage employees →
              </Link>
            </Card>
          )}

          <div className="grid gap-4 lg:grid-cols-2">
            <Card title="Participation">
              <ParticipationSummary participation={p} departmentCoverage={snapshot.department_coverage} compact />
            </Card>

            <Card title="Report readiness">
              <div className="flex flex-col gap-6 md:flex-row md:items-start">
                <ReadinessGauge score={score} breakdown={breakdown} />
                <div className="flex-1 space-y-3">
                  {data.latest_report && (
                    <p className="text-sm text-text-primary">
                      Latest report:{' '}
                      <Badge variant={data.latest_report.status === 'ready' ? 'success' : 'neutral'}>
                        v{data.latest_report.version} — {data.latest_report.status}
                      </Badge>
                    </p>
                  )}
                  {data.usage && (
                    <p className="text-sm text-text-secondary">
                      Trial conversations: {data.usage.conversations_used}
                      {data.usage.conversation_limit != null ? ` / ${data.usage.conversation_limit}` : ''} used
                    </p>
                  )}
                  <p className="text-sm text-text-secondary">
                    {snapshot.report_ready
                      ? 'Your organization meets the readiness threshold to generate a discovery report.'
                      : 'Continue interviews and document uploads to increase readiness.'}
                  </p>
                  <div className="flex flex-wrap gap-2">
                    <Link to="/company/reports">
                      <Button>{snapshot.report_ready ? 'Generate report' : 'View reports'}</Button>
                    </Link>
                    <Link to="/company/recommendations">
                      <Button variant="secondary">Recommendations</Button>
                    </Link>
                  </div>
                </div>
              </div>
            </Card>
          </div>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card title="Top pain points">
              {snapshot.top_pain_points.length === 0 ? (
                <p className="text-sm text-text-secondary">Complete more interviews to surface signals.</p>
              ) : (
                <div className="space-y-4">
                  {snapshot.top_pain_points.map((s) => (
                    <div key={s.id}>
                      <div className="mb-1 flex justify-between text-sm">
                        <span className="font-medium text-text-primary">{s.label}</span>
                        <span className="text-text-secondary">{Math.round(s.strength * 100)}%</span>
                      </div>
                      <StrengthBar strength={s.strength} />
                    </div>
                  ))}
                </div>
              )}
              <Link to="/company/intelligence/signals" className="mt-4 inline-block text-sm font-medium text-accent hover:underline">
                View all signals →
              </Link>
            </Card>

            <Card title="Emerging patterns">
              {(snapshot.emerging_patterns?.length ?? 0) === 0 ? (
                <p className="text-sm text-text-secondary">Patterns appear when signals repeat across departments.</p>
              ) : (
                <div className="space-y-4">
                  {snapshot.emerging_patterns.map((pattern) => (
                    <div key={pattern.id}>
                      <div className="mb-1 flex items-start justify-between gap-2 text-sm">
                        <span className="font-medium text-text-primary">{pattern.title}</span>
                        <span className="shrink-0 text-text-secondary">{Math.round(pattern.confidence * 100)}%</span>
                      </div>
                      <StrengthBar strength={pattern.confidence} />
                    </div>
                  ))}
                </div>
              )}
              <Link to="/company/intelligence/patterns" className="mt-4 inline-block text-sm font-medium text-accent hover:underline">
                View all patterns →
              </Link>
            </Card>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <StatCard label="Signals" value={snapshot.top_pain_points.length} icon={<Radio className="h-5 w-5 text-accent" />} />
            <StatCard
              label="Recommendations"
              value={snapshot.recommendation_count}
              icon={<Lightbulb className="h-5 w-5 text-accent" />}
            />
          </div>

          {snapshot.recent_timeline.length > 0 && (
            <Card title="Recent activity">
              <Timeline
                events={snapshot.recent_timeline.map((e, i) => ({
                  id: String(i),
                  title: e.title,
                  summary: e.summary,
                  occurredAt: e.occurred_at,
                }))}
              />
              <Link to="/company/intelligence/timeline" className="mt-4 inline-block text-sm font-medium text-accent hover:underline">
                View full timeline →
              </Link>
            </Card>
          )}
        </>
      )}
    </DashboardShell>
  );
}
