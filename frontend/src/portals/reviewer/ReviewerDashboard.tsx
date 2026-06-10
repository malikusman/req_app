import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  Building2,
  FileBarChart,
  Users,
  ClipboardList,
  MessageSquare,
  Bell,
} from 'lucide-react';
import {
  api,
  type ReviewerCompanyDetail,
  type ReviewerCompanySummary,
  type ReviewerFollowupRow,
} from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { AnimatedCard, Stagger, StatCardGrid } from '../../components/motion';
import {
  PageHeader,
  Card,
  Badge,
  EmptyState,
  Skeleton,
  StatCard,
  Button,
} from '../../components/ui';

const OPEN_FOLLOWUP_STATUSES = new Set(['awaiting_reply', 'sent']);
const SUBMITTED_REVIEW_STATUSES = new Set(['approved', 'rejected']);

function isReviewPending(detail: ReviewerCompanyDetail): boolean {
  const report = detail.latest_report;
  if (!report || report.status !== 'ready') return false;
  const status = detail.my_review_status;
  if (!status) return true;
  return !SUBMITTED_REVIEW_STATUSES.has(status);
}

function reviewStatusVariant(status: string | null): 'success' | 'warning' | 'info' | 'neutral' {
  if (!status || status === 'pending') return 'warning';
  if (status === 'in_review' || status === 'needs_info') return 'info';
  if (status === 'approved') return 'success';
  return 'neutral';
}

type AttentionItem = {
  companyId: number;
  companyName: string;
  reportId: number;
  reportVersion: number;
  reviewStatus: string | null;
};

export function ReviewerDashboard() {
  const token = useReviewerToken();
  const [companies, setCompanies] = useState<ReviewerCompanySummary[]>([]);
  const [companyDetails, setCompanyDetails] = useState<Record<number, ReviewerCompanyDetail>>({});
  const [followups, setFollowups] = useState<ReviewerFollowupRow[]>([]);
  const [unreadNotifications, setUnreadNotifications] = useState(0);
  const [profilePercent, setProfilePercent] = useState<number | null>(null);
  const [profilePublished, setProfilePublished] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [partialErrors, setPartialErrors] = useState<string[]>([]);

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    setError('');
    setPartialErrors([]);

    api
      .reviewerCompanies(token)
      .then(async (companiesRes) => {
        const assigned = companiesRes.companies;
        setCompanies(assigned);

        const results = await Promise.allSettled([
          api.reviewerMe(token),
          api.reviewerFollowups(token),
          api.reviewerNotifications(token, { per_page: 1 }),
          ...assigned.map((c) => api.reviewerCompany(token, c.id)),
        ]);

        const errors: string[] = [];

        const [meResult, followupsResult, notificationsResult, ...detailResults] = results;

        if (meResult.status === 'fulfilled') {
          setProfilePercent(meResult.value.profile_completeness_percent);
          setProfilePublished(meResult.value.profile.profile_status === 'published');
        } else {
          errors.push('Could not load profile.');
        }

        if (followupsResult.status === 'fulfilled') {
          setFollowups(followupsResult.value.followups);
        } else {
          errors.push('Could not load follow-ups.');
        }

        if (notificationsResult.status === 'fulfilled') {
          setUnreadNotifications(notificationsResult.value.unread_count);
        } else {
          errors.push('Could not load notifications.');
        }

        const details: Record<number, ReviewerCompanyDetail> = {};
        detailResults.forEach((result, index) => {
          if (result.status === 'fulfilled') {
            details[assigned[index].id] = result.value.company;
          }
        });
        setCompanyDetails(details);

        if (detailResults.some((r) => r.status === 'rejected')) {
          errors.push('Some company details could not be loaded.');
        }

        setPartialErrors(errors);
      })
      .catch(() => setError('Could not load assigned companies.'))
      .finally(() => setLoading(false));
  }, [token]);

  const stats = useMemo(() => {
    const detailList = Object.values(companyDetails);
    const avgReadiness =
      companies.length > 0
        ? Math.round(companies.reduce((sum, c) => sum + c.report_readiness_score, 0) / companies.length)
        : 0;
    const totalCompleted = companies.reduce((sum, c) => sum + c.completed_count, 0);
    const totalInvited = companies.reduce((sum, c) => sum + c.invited_count, 0);
    const pendingReviews = detailList.filter(isReviewPending).length;
    const openFollowups = followups.filter((f) => OPEN_FOLLOWUP_STATUSES.has(f.status)).length;

    return { avgReadiness, totalCompleted, totalInvited, pendingReviews, openFollowups };
  }, [companies, companyDetails, followups]);

  const attentionItems = useMemo((): AttentionItem[] => {
    return Object.values(companyDetails)
      .filter(isReviewPending)
      .map((detail) => ({
        companyId: detail.id,
        companyName: detail.name,
        reportId: detail.latest_report!.id,
        reportVersion: detail.latest_report!.version,
        reviewStatus: detail.my_review_status,
      }));
  }, [companyDetails]);

  const recentFollowups = useMemo(
    () =>
      [...followups]
        .sort((a, b) => new Date(b.updated_at).getTime() - new Date(a.updated_at).getTime())
        .slice(0, 3),
    [followups]
  );

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
        <Skeleton variant="card" />
        <div className="grid gap-4 md:grid-cols-2">
          <Skeleton variant="card" />
          <Skeleton variant="card" />
        </div>
      </div>
    );
  }

  if (error && companies.length === 0) {
    return (
      <div className="space-y-6">
        <PageHeader title="Dashboard" description="Portfolio overview and pending actions." />
        <EmptyState title="Unable to load dashboard" description={error} />
      </div>
    );
  }

  return (
    <div className="space-y-8">
      <PageHeader
        title="Dashboard"
        description="Portfolio overview, pending reviews, and follow-ups across your assigned companies."
      />

      {!profilePublished && profilePercent != null && (
        <div className="rounded-card border border-accent/30 bg-surface-muted px-4 py-3 text-sm text-text-primary">
          Your expert profile is {profilePercent}% complete.{' '}
          <Link to="/reviewer/profile" className="font-medium text-accent hover:underline">
            Complete your profile →
          </Link>
        </div>
      )}

      {(error || partialErrors.length > 0) && (
        <div className="rounded-card border border-status-warning/30 bg-status-warningBg px-4 py-3 text-sm">
          {[error, ...partialErrors].filter(Boolean).join(' ')}
        </div>
      )}

      <StatCardGrid className="grid-cols-2 md:grid-cols-3 xl:grid-cols-6">
        <StatCard
          label="Assigned companies"
          value={companies.length}
          icon={<Building2 className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Avg readiness"
          value={`${stats.avgReadiness}%`}
          icon={<FileBarChart className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Interviews completed"
          value={`${stats.totalCompleted}/${stats.totalInvited}`}
          icon={<Users className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Reviews pending"
          value={stats.pendingReviews}
          icon={<ClipboardList className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Open follow-ups"
          value={stats.openFollowups}
          icon={<MessageSquare className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Unread notifications"
          value={unreadNotifications}
          icon={<Bell className="h-5 w-5 text-accent" />}
        />
      </StatCardGrid>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card title="Needs your attention">
          {attentionItems.length === 0 ? (
            <EmptyState
              title="All caught up"
              description="No report reviews waiting on you right now."
            />
          ) : (
            <div className="space-y-3">
              {attentionItems.map((item) => (
                <div
                  key={`${item.companyId}-${item.reportId}`}
                  className="flex flex-wrap items-center justify-between gap-3 rounded-card border border-border bg-surface-muted px-4 py-3"
                >
                  <div>
                    <p className="m-0 font-medium text-text-primary">{item.companyName}</p>
                    <div className="mt-2 flex flex-wrap gap-2">
                      <Badge variant="info">Report v{item.reportVersion}</Badge>
                      <Badge variant={reviewStatusVariant(item.reviewStatus)}>
                        {item.reviewStatus || 'not started'}
                      </Badge>
                    </div>
                  </div>
                  <Link to={`/reviewer/companies/${item.companyId}/reports/${item.reportId}/review`}>
                    <Button>Open review</Button>
                  </Link>
                </div>
              ))}
            </div>
          )}
        </Card>

        <Card title="Recent follow-ups">
          {recentFollowups.length === 0 ? (
            <EmptyState
              title="No follow-ups"
              description="Follow-up threads appear when you request clarification from employees."
            />
          ) : (
            <div className="space-y-3">
              {recentFollowups.map((f) => (
                <div
                  key={f.id}
                  className="flex flex-wrap items-start justify-between gap-3 rounded-card border border-border bg-surface-muted px-4 py-3"
                >
                  <div>
                    <p className="m-0 text-sm text-text-secondary">{f.company_name}</p>
                    <p className="m-0 font-medium text-text-primary">
                      {f.employee_name || `Employee #${f.employee_id}`}
                    </p>
                    <p className="mt-1 line-clamp-2 text-sm text-text-secondary">{f.last_message}</p>
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
              {followups.length > 3 && (
                <Link to="/reviewer/followups" className="text-sm font-medium text-accent hover:underline">
                  View all follow-ups →
                </Link>
              )}
            </div>
          )}
        </Card>
      </div>

      <section className="space-y-4">
        <h2 className="m-0 text-lg font-medium text-text-primary">Assigned companies</h2>
        {companies.length === 0 ? (
          <EmptyState
            title="No companies assigned yet"
            description="No companies assigned yet. Contact your platform administrator."
          />
        ) : (
          <Stagger className="grid gap-4 md:grid-cols-2 lg:grid-cols-3" staggerDelay={0.08}>
            {companies.map((c) => {
              const detail = companyDetails[c.id];
              return (
                <Link key={c.id} to={`/reviewer/companies/${c.id}`} className="block no-underline">
                  <AnimatedCard>
                    <Card className="h-full transition-shadow hover:shadow-md">
                      <h3 className="m-0 font-medium text-text-primary">{c.name}</h3>
                      <div className="mt-3 flex flex-wrap gap-2">
                        <Badge variant="info">{c.report_readiness_score}% readiness</Badge>
                        <Badge variant="neutral">
                          {c.completed_count}/{c.invited_count} completed
                        </Badge>
                        {detail?.latest_report && (
                          <Badge variant={detail.latest_report.status === 'ready' ? 'success' : 'neutral'}>
                            v{detail.latest_report.version} — {detail.latest_report.status}
                          </Badge>
                        )}
                        {detail?.latest_report && (
                          <Badge variant={reviewStatusVariant(detail.my_review_status)}>
                            Review: {detail.my_review_status || 'pending'}
                          </Badge>
                        )}
                      </div>
                      {detail && detail.co_reviewer_count > 0 && (
                        <p className="mt-2 text-xs text-text-secondary">
                          {detail.co_reviewer_count} co-reviewer{detail.co_reviewer_count === 1 ? '' : 's'}
                        </p>
                      )}
                      <p className="mt-3 text-sm font-medium text-accent">Open company →</p>
                    </Card>
                  </AnimatedCard>
                </Link>
              );
            })}
          </Stagger>
        )}
      </section>
    </div>
  );
}
