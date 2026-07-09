import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  Building2,
  FileBarChart,
  Users,
  ClipboardList,
  MessageSquare,
  Bell,
} from 'lucide-react';
import { api, type ReviewerDashboardPayload } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { AnimatedCard, Stagger } from '../../components/motion';
import {
  DashboardShell,
  Card,
  Badge,
  EmptyState,
  StatCard,
  Button,
} from '../../components/ui';

function reviewStatusVariant(status: string | null): 'success' | 'warning' | 'info' | 'neutral' {
  if (!status || status === 'pending') return 'warning';
  if (status === 'in_review' || status === 'needs_info') return 'info';
  if (status === 'approved') return 'success';
  return 'neutral';
}

export function ReviewerDashboard() {
  const token = useReviewerToken();
  const [data, setData] = useState<ReviewerDashboardPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    setError('');
    api
      .reviewerDashboard(token)
      .then(setData)
      .catch(() => setError('Could not load assigned companies.'))
      .finally(() => setLoading(false));
  }, [token]);

  if (!loading && error && !data) {
    return (
      <DashboardShell title="Dashboard" description="Portfolio overview and pending actions." loading={false}>
        <EmptyState title="Unable to load dashboard" description={error} />
      </DashboardShell>
    );
  }

  const stats = data?.stats;
  const companies = data?.companies ?? [];
  const actionQueue = [...(data?.attention_items ?? [])].sort((a, b) => {
    const rank = (status: string | null) => {
      if (!status || status === 'pending') return 0;
      if (status === 'needs_info') return 1;
      if (status === 'in_review') return 2;
      return 3;
    };
    return rank(a.review_status) - rank(b.review_status);
  });

  return (
    <DashboardShell
      title="Dashboard"
      description="Portfolio overview, pending reviews, and follow-ups across your assigned companies."
      loading={loading}
      banner={
        data && data.profile.profile_status !== 'published' && data.profile.profile_completeness_percent != null ? (
          <div className="rounded-lg border border-accent/30 bg-muted px-4 py-3 text-sm text-foreground">
            Your expert profile is {data.profile.profile_completeness_percent}% complete.{' '}
            <Link to="/reviewer/profile" className="font-medium text-accent hover:underline">
              Complete your profile →
            </Link>
          </div>
        ) : undefined
      }
      kpiRow={
        stats ? (
          <>
            <StatCard label="Assigned companies" value={stats.assigned_companies} icon={<Building2 className="h-5 w-5 text-accent" />} />
            <StatCard label="Avg readiness" value={`${stats.avg_readiness}%`} icon={<FileBarChart className="h-5 w-5 text-accent" />} />
            <StatCard
              label="Interviews completed"
              value={`${stats.total_completed}/${stats.total_invited}`}
              icon={<Users className="h-5 w-5 text-accent" />}
            />
            <StatCard label="Reviews pending" value={stats.pending_reviews} icon={<ClipboardList className="h-5 w-5 text-accent" />} />
            <StatCard label="Open follow-ups" value={stats.open_followups} icon={<MessageSquare className="h-5 w-5 text-accent" />} />
            <StatCard label="Unread notifications" value={data?.unread_count ?? 0} icon={<Bell className="h-5 w-5 text-accent" />} />
          </>
        ) : undefined
      }
    >
      {data && (
        <>
          <div className="grid gap-4 lg:grid-cols-2">
            <Card title={`Action queue (${actionQueue.length})`}>
              {actionQueue.length === 0 ? (
                <EmptyState title="All caught up" description="No report reviews waiting on you right now." />
              ) : (
                <div className="space-y-3">
                  {actionQueue.map((item) => (
                    <div
                      key={`${item.company_id}-${item.report_id}`}
                      className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-border bg-muted px-4 py-3"
                    >
                      <div>
                        <p className="m-0 font-medium text-foreground">{item.company_name}</p>
                        <div className="mt-2 flex flex-wrap gap-2">
                          <Badge variant="info">Report v{item.report_version}</Badge>
                          <Badge variant={reviewStatusVariant(item.review_status)}>
                            {item.review_status || 'not started'}
                          </Badge>
                        </div>
                      </div>
                      <Link to={`/reviewer/companies/${item.company_id}/reports/${item.report_id}/review`}>
                        <Button>Open review</Button>
                      </Link>
                    </div>
                  ))}
                </div>
              )}
            </Card>

            <Card title="Recent follow-ups">
              {data.recent_followups.length === 0 ? (
                <EmptyState
                  title="No follow-ups"
                  description="Follow-up threads appear when you request clarification from employees."
                />
              ) : (
                <div className="space-y-3">
                  {data.recent_followups.map((f) => (
                    <div
                      key={f.id}
                      className="flex flex-wrap items-start justify-between gap-3 rounded-lg border border-border bg-muted px-4 py-3"
                    >
                      <div>
                        <p className="m-0 text-sm text-muted-foreground">{f.company_name}</p>
                        <p className="m-0 font-medium text-foreground">
                          {f.employee_name || `Employee #${f.employee_id}`}
                        </p>
                        <p className="mt-1 line-clamp-2 text-sm text-muted-foreground">{f.last_message}</p>
                      </div>
                      <div className="flex flex-col items-end gap-2">
                        <Badge variant={f.status === 'awaiting_reply' ? 'warning' : 'info'}>
                          {f.status.replace(/_/g, ' ')}
                        </Badge>
                        <Link
                          to={`/reviewer/companies/${f.company_id}/employees/${f.employee_id}/followup`}
                          className="text-sm font-medium text-accent hover:underline"
                        >
                          Open thread →
                        </Link>
                      </div>
                    </div>
                  ))}
                  {data.stats.open_followups > 3 && (
                    <Link to="/reviewer/inbox" className="text-sm font-medium text-accent hover:underline">
                      View all follow-ups →
                    </Link>
                  )}
                </div>
              )}
            </Card>
          </div>

          <section className="space-y-4">
            <h2 className="m-0 text-lg font-medium text-foreground">Assigned companies</h2>
            {companies.length === 0 ? (
              <EmptyState
                title="No companies assigned yet"
                description="Contact your platform administrator."
              />
            ) : (
              <Stagger className="grid gap-4 md:grid-cols-2 lg:grid-cols-3" staggerDelay={0.08}>
                {companies.map((c) => (
                  <Link key={c.id} to={`/reviewer/companies/${c.id}`} className="block no-underline">
                    <AnimatedCard>
                      <Card className="h-full transition-shadow hover:shadow-md">
                        <h3 className="m-0 font-medium text-foreground">{c.name}</h3>
                        <div className="mt-3 flex flex-wrap gap-2">
                          <Badge variant="info">{c.report_readiness_score}% readiness</Badge>
                          <Badge variant="neutral">
                            {c.completed_count}/{c.invited_count} completed
                          </Badge>
                          {c.latest_report && (
                            <Badge variant={c.latest_report.status === 'ready' ? 'success' : 'neutral'}>
                              v{c.latest_report.version} — {c.latest_report.status}
                            </Badge>
                          )}
                          {c.latest_report && (
                            <Badge variant={reviewStatusVariant(c.my_review_status ?? null)}>
                              Review: {c.my_review_status || 'pending'}
                            </Badge>
                          )}
                        </div>
                        {c.co_reviewer_count > 0 && (
                          <p className="mt-2 text-xs text-muted-foreground">
                            {c.co_reviewer_count} co-reviewer{c.co_reviewer_count === 1 ? '' : 's'}
                          </p>
                        )}
                        <p className="mt-3 text-sm font-medium text-accent">Open company →</p>
                      </Card>
                    </AnimatedCard>
                  </Link>
                ))}
              </Stagger>
            )}
          </section>
        </>
      )}
    </DashboardShell>
  );
}
