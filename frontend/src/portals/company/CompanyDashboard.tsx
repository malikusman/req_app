import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Users, CheckCircle2, Percent, FileBarChart } from 'lucide-react';
import { api, type IntelligenceSnapshot, type Report } from '../../lib/api';
import { useAuth, useCompanyToken } from '../../lib/auth';
import { StatCardGrid } from '../../components/motion';
import { PageHeader } from '../../components/ui/PageHeader';
import { StatCard } from '../../components/ui/StatCard';
import { Card } from '../../components/ui/Card';
import { ReadinessGauge } from '../../components/ui/ReadinessGauge';
import { DepartmentHeatmap } from '../../components/ui/DepartmentHeatmap';
import { StrengthBar } from '../../components/ui/StrengthBar';
import { Timeline } from '../../components/ui/Timeline';
import { Badge } from '../../components/ui/Badge';
import { Button } from '../../components/ui/Button';
import { Skeleton } from '../../components/ui/Skeleton';
import { EmptyState } from '../../components/ui/EmptyState';

export function CompanyDashboard() {
  const token = useCompanyToken();
  const { session } = useAuth();
  const navigate = useNavigate();
  const [snapshot, setSnapshot] = useState<IntelligenceSnapshot | null>(null);
  const [latestReport, setLatestReport] = useState<Report | null>(null);
  const [score, setScore] = useState(0);
  const [breakdown, setBreakdown] = useState<Record<string, number>>({});
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

    Promise.allSettled([api.intelligenceSnapshot(token), api.companyReports(token)])
      .then(([snapResult, reportsResult]) => {
        if (snapResult.status === 'fulfilled') {
          setSnapshot(snapResult.value.snapshot);
          setScore(Math.round(snapResult.value.report_readiness_score));
          setBreakdown(snapResult.value.report_readiness_breakdown as Record<string, number>);
        } else {
          setError('Could not load discovery snapshot. Try refreshing the page.');
        }
        if (reportsResult.status === 'fulfilled') {
          const reports = reportsResult.value.reports || [];
          const sorted = [...reports].sort((a, b) => b.version - a.version);
          setLatestReport(sorted[0] ?? null);
        }
      })
      .finally(() => setLoading(false));
  }, [token]);

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {[1, 2, 3, 4].map((i) => (
            <Skeleton key={i} variant="card" />
          ))}
        </div>
        <Skeleton variant="card" />
      </div>
    );
  }

  if (error && !snapshot) {
    return (
      <div className="space-y-6">
        <PageHeader title="Discovery intelligence" description="Live operational snapshot." />
        <EmptyState title="Unable to load dashboard" description={error} />
      </div>
    );
  }

  if (!snapshot) {
    return (
      <div className="space-y-6">
        <PageHeader title="Discovery intelligence" description="Live operational snapshot." />
        <EmptyState
          title="No data yet"
          description="Complete onboarding and invite employees to start discovery."
        />
      </div>
    );
  }

  const p = snapshot.participation;

  if (p.invited === 0) {
    return (
      <div className="space-y-6">
        <PageHeader title="Discovery intelligence" description="Get started with your discovery program." />
        <div className="rounded-card border border-border bg-surface p-8 shadow-card">
          <EmptyState
            title="Invite your first employees"
            description="Add employees to begin WhatsApp discovery interviews and build your operational snapshot."
            action={{ label: 'Invite employees', onClick: () => navigate('/company/employees') }}
          />
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      <PageHeader
        title="Discovery intelligence"
        description="Live operational snapshot — signals, patterns, and recommendations from your program."
      />

      {error && (
        <div className="rounded-card border border-status-warning/30 bg-status-warningBg px-4 py-3 text-sm">
          {error}
        </div>
      )}

      <StatCardGrid>
        <StatCard label="Invited" value={p.invited} icon={<Users className="h-5 w-5 text-accent" />} />
        <StatCard label="Completed" value={p.completed} icon={<CheckCircle2 className="h-5 w-5 text-accent" />} />
        <StatCard
          label="Completion rate"
          value={`${Math.round(p.completion_rate * 100)}%`}
          icon={<Percent className="h-5 w-5 text-accent" />}
        />
        <StatCard label="Readiness score" value={`${score}%`} icon={<FileBarChart className="h-5 w-5 text-accent" />} />
      </StatCardGrid>

      <Card title="Department coverage">
        <DepartmentHeatmap cells={snapshot.department_coverage} />
      </Card>

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
                <p className="mt-1 text-xs text-text-secondary">{s.departments.join(', ') || s.signal_type}</p>
              </div>
            ))}
          </div>
        )}
      </Card>

      <Card title="Report status">
        <div className="flex flex-col gap-6 md:flex-row md:items-center">
          <ReadinessGauge score={score} breakdown={breakdown} />
          <div className="flex-1 space-y-3">
            {latestReport && (
              <p className="text-sm text-text-primary">
                Latest report:{' '}
                <Badge variant={latestReport.status === 'ready' ? 'success' : 'neutral'}>
                  v{latestReport.version} — {latestReport.status}
                </Badge>
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
                <Button variant="secondary">Recommendations ({snapshot.recommendation_count})</Button>
              </Link>
            </div>
          </div>
        </div>
      </Card>

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
          <Link to="/company/intelligence/timeline" className="mt-4 inline-block text-sm font-medium">
            View full timeline →
          </Link>
        </Card>
      )}
    </div>
  );
}
