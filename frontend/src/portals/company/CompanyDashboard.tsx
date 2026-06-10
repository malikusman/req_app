import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  Users,
  CheckCircle2,
  Percent,
  FileBarChart,
  Radio,
  Lightbulb,
  MessageSquare,
} from 'lucide-react';
import { api, type IntelligenceSnapshot, type Report } from '../../lib/api';
import { useAuth, useCompanyToken } from '../../lib/auth';
import { StatCardGrid } from '../../components/motion';
import { PageHeader } from '../../components/ui/PageHeader';
import { StatCard } from '../../components/ui/StatCard';
import { Card } from '../../components/ui/Card';
import { ReadinessGauge } from '../../components/ui/ReadinessGauge';
import { ParticipationSummary } from '../../components/ui/ParticipationSummary';
import { StrengthBar } from '../../components/ui/StrengthBar';
import { Timeline } from '../../components/ui/Timeline';
import { Badge } from '../../components/ui/Badge';
import { Button } from '../../components/ui/Button';
import { Skeleton } from '../../components/ui/Skeleton';
import { EmptyState } from '../../components/ui/EmptyState';

type UsageSummary = {
  conversations_used: number;
  conversation_limit: number | null;
  remaining: number | null;
  limit_reached: boolean;
};

export function CompanyDashboard() {
  const token = useCompanyToken();
  const { session } = useAuth();
  const navigate = useNavigate();
  const [snapshot, setSnapshot] = useState<IntelligenceSnapshot | null>(null);
  const [latestReport, setLatestReport] = useState<Report | null>(null);
  const [usage, setUsage] = useState<UsageSummary | null>(null);
  const [score, setScore] = useState(0);
  const [breakdown, setBreakdown] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);
  const [snapshotError, setSnapshotError] = useState('');

  useEffect(() => {
    if (session?.portal === 'company' && !session.impersonating && !session.company.portal_onboarding_completed_at) {
      navigate('/company/onboarding', { replace: true });
    }
  }, [session, navigate]);

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    setSnapshotError('');

    Promise.allSettled([api.intelligenceSnapshot(token), api.companyMe(token), api.companyReports(token)])
      .then(([snapResult, meResult, reportsResult]) => {
        if (snapResult.status === 'fulfilled') {
          setSnapshot(snapResult.value.snapshot);
          setScore(Math.round(snapResult.value.report_readiness_score));
          setBreakdown(snapResult.value.report_readiness_breakdown as Record<string, number>);
        } else {
          setSnapshot(null);
          setSnapshotError('Could not load discovery snapshot. Try refreshing the page.');
        }

        if (meResult.status === 'fulfilled') {
          setUsage(meResult.value.usage);
          if (snapResult.status !== 'fulfilled' && meResult.value.company.intelligence_snapshot) {
            setSnapshot(meResult.value.company.intelligence_snapshot as IntelligenceSnapshot);
            setScore(Math.round(meResult.value.company.report_readiness_score ?? 0));
            setBreakdown((meResult.value.company.report_readiness_breakdown ?? {}) as Record<string, number>);
            setSnapshotError('');
          }
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
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-6">
          {[1, 2, 3, 4, 5, 6].map((i) => (
            <Skeleton key={i} variant="card" />
          ))}
        </div>
        <Skeleton variant="card" />
      </div>
    );
  }

  if (!snapshot) {
    return (
      <div className="space-y-6">
        <PageHeader title="Discovery intelligence" description="Live operational snapshot." />
        <EmptyState
          title="Unable to load dashboard"
          description={snapshotError || 'Complete onboarding and invite employees to start discovery.'}
        />
      </div>
    );
  }

  const p = snapshot.participation;
  const signalCount = snapshot.top_pain_points.length;
  const patternCount = snapshot.emerging_patterns?.length ?? 0;

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

      {snapshotError && (
        <div className="rounded-card border border-status-warning/30 bg-status-warningBg px-4 py-3 text-sm">
          {snapshotError}
        </div>
      )}

      <StatCardGrid className="grid-cols-2 md:grid-cols-3 xl:grid-cols-6">
        <StatCard label="Readiness" value={`${score}%`} icon={<FileBarChart className="h-5 w-5 text-accent" />} />
        <StatCard label="Invited" value={p.invited} icon={<Users className="h-5 w-5 text-accent" />} />
        <StatCard label="Completed" value={p.completed} icon={<CheckCircle2 className="h-5 w-5 text-accent" />} />
        <StatCard
          label="Completion rate"
          value={`${Math.round(p.completion_rate * 100)}%`}
          icon={<Percent className="h-5 w-5 text-accent" />}
        />
        <StatCard label="Signals" value={signalCount} icon={<Radio className="h-5 w-5 text-accent" />} />
        <StatCard
          label="Recommendations"
          value={snapshot.recommendation_count}
          icon={<Lightbulb className="h-5 w-5 text-accent" />}
        />
      </StatCardGrid>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="Participation">
          <ParticipationSummary
            participation={p}
            departmentCoverage={snapshot.department_coverage}
          />
        </Card>

        <Card title="Report readiness">
          <div className="flex flex-col gap-6 md:flex-row md:items-start">
            <ReadinessGauge score={score} breakdown={breakdown} />
            <div className="flex-1 space-y-3">
              {latestReport && (
                <p className="text-sm text-text-primary">
                  Latest report:{' '}
                  <Badge variant={latestReport.status === 'ready' ? 'success' : 'neutral'}>
                    v{latestReport.version} — {latestReport.status}
                  </Badge>
                  {latestReport.visibility === 'shared_with_company' && (
                    <Badge variant="success" className="ml-2">
                      Shared
                    </Badge>
                  )}
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

      <Card title="Program status">
        <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
          <div className="flex flex-wrap gap-6 text-sm">
            {usage && (
              <div>
                <p className="text-text-secondary">Trial conversations</p>
                <p className="font-semibold text-text-primary">
                  {usage.conversations_used}
                  {usage.conversation_limit != null ? ` / ${usage.conversation_limit}` : ''} used
                </p>
              </div>
            )}
            <div>
              <p className="text-text-secondary">Patterns detected</p>
              <p className="font-semibold text-text-primary">{patternCount}</p>
            </div>
            <div>
              <p className="text-text-secondary">In progress</p>
              <p className="font-semibold text-text-primary">{Math.max(0, p.started - p.completed)} interviews</p>
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            <Link to="/company/employees">
              <Button variant="secondary" size="sm">
                Employees
              </Button>
            </Link>
            <Link to="/company/conversations">
              <Button variant="secondary" size="sm">
                <MessageSquare className="mr-1.5 inline h-4 w-4" />
                Conversations
              </Button>
            </Link>
            <Link to="/company/intelligence/signals">
              <Button variant="secondary" size="sm">
                Signals
              </Button>
            </Link>
            <Link to="/company/intelligence/patterns">
              <Button variant="secondary" size="sm">
                Patterns
              </Button>
            </Link>
          </div>
        </div>
      </Card>

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
                  <p className="mt-1 text-xs text-text-secondary">{s.departments.join(', ') || s.signal_type}</p>
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
                  <p className="mt-1 text-xs text-text-secondary">
                    {pattern.departments.join(', ') || 'Cross-department'}
                  </p>
                </div>
              ))}
            </div>
          )}
          <Link to="/company/intelligence/patterns" className="mt-4 inline-block text-sm font-medium text-accent hover:underline">
            View all patterns →
          </Link>
        </Card>
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
    </div>
  );
}
