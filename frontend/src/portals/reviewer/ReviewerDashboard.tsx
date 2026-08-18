import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  Bell,
  Building2,
  FileBarChart,
  MessageSquare,
} from 'lucide-react';
import { api, type ReviewerDashboardPayload } from '../../lib/api';
import { useAuth, useReviewerToken } from '../../lib/auth';
import {
  DashboardShell,
  Card,
  Badge,
  EmptyState,
  SimpleBarChart,
  NextStepHero,
  AttentionList,
  OutcomeTile,
  type AttentionItemData,
} from '../../components/ui';
import { cn } from '../../lib/cn';
import { isReviewPending } from './nav';

function reviewStatusVariant(status: string | null): 'success' | 'warning' | 'info' | 'neutral' {
  if (!status || status === 'pending') return 'warning';
  if (status === 'in_review' || status === 'needs_info') return 'info';
  if (status === 'approved') return 'success';
  return 'neutral';
}

function companyCompletionRate(c: ReviewerDashboardPayload['companies'][number]): number {
  if (typeof c.completion_rate === 'number') return Math.round(c.completion_rate);
  const fromParticipation = c.participation?.completion_rate;
  if (typeof fromParticipation === 'number') return Math.round(fromParticipation);
  if (c.invited_count > 0) return Math.round((c.completed_count / c.invited_count) * 100);
  return 0;
}

function StatusChip({ tone, label }: { tone: 'ready' | 'progress' | 'setup'; label: string }) {
  const live = tone !== 'setup';
  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center gap-2 rounded-badge border px-3 py-1.5 text-xs font-semibold',
        tone === 'setup'
          ? 'border-border bg-card text-muted-foreground'
          : 'border-accent/40 bg-accent-muted text-accent-hover'
      )}
    >
      {live && (
        <span className="relative flex h-1.5 w-1.5">
          <span className="absolute inline-flex h-full w-full rounded-full bg-primary opacity-60 motion-safe:animate-ping" />
          <span className="relative inline-flex h-1.5 w-1.5 rounded-full bg-primary" />
        </span>
      )}
      {label}
    </span>
  );
}

export function ReviewerDashboard() {
  const token = useReviewerToken();
  const { session } = useAuth();
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

  const companies = data?.companies;
  const readinessByCompany = useMemo(
    () =>
      (companies ?? []).map((c) => ({
        name: c.name,
        value: Math.round(c.report_readiness_score ?? 0),
      })),
    [companies]
  );
  const participationByCompany = useMemo(
    () =>
      (companies ?? []).map((c) => ({
        name: c.name,
        value: companyCompletionRate(c),
      })),
    [companies]
  );

  if (loading) {
    return <DashboardShell title="Home" description="Loading your review workspace…" loading />;
  }

  if (!data) {
    return (
      <DashboardShell title="Home" description="Companies and reviews assigned to you." loading={false}>
        <EmptyState
          title="Unable to load dashboard"
          description={error || 'Contact your platform administrator if this persists.'}
        />
      </DashboardShell>
    );
  }

  const stats = data.stats;
  const list = companies ?? [];
  const firstCompany = list[0];
  const companiesTo = firstCompany ? `/reviewer/companies/${firstCompany.id}` : '/reviewer/profile';

  const firstName = (session?.portal === 'reviewer' ? session.user.name : '').trim().split(/\s+/)[0] || 'there';
  const hour = new Date().getHours();
  const greeting = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';

  const statusChip: { tone: 'ready' | 'progress' | 'setup'; label: string } =
    stats.pending_reviews > 0
      ? { tone: 'progress', label: `${stats.pending_reviews} review${stats.pending_reviews === 1 ? '' : 's'} pending` }
      : stats.open_followups > 0
        ? { tone: 'progress', label: 'Follow-ups open' }
        : stats.assigned_companies > 0
          ? { tone: 'ready', label: 'All caught up' }
          : { tone: 'setup', label: 'No assignments yet' };

  // Hero = the single top thing needing you.
  const heroReviewItem = data.attention_items.find((i) => i.report_id);
  const usedHeroReview = stats.pending_reviews > 0 && Boolean(heroReviewItem);

  const hero = usedHeroReview
    ? {
        eyebrow: 'Do this next',
        title: `Review ${heroReviewItem!.company_name}'s report v${heroReviewItem!.report_version}`,
        description: 'A report is waiting for your expert review.',
        primaryAction: {
          label: 'Open review',
          to: `/reviewer/companies/${heroReviewItem!.company_id}/reports/${heroReviewItem!.report_id}/review`,
        },
      }
    : stats.open_followups > 0
      ? {
          eyebrow: 'Do this next',
          title: `Answer ${stats.open_followups} follow-up${stats.open_followups === 1 ? '' : 's'}`,
          description: 'Employees are waiting on your clarification.',
          primaryAction: { label: 'Open inbox', to: '/reviewer/inbox' },
        }
      : {
          eyebrow: 'All caught up',
          title: 'Nothing needs you right now',
          description:
            'No report reviews or follow-ups are waiting. New work will surface here as soon as it arrives.',
          primaryAction: firstCompany
            ? { label: 'Open a company', to: `/reviewer/companies/${firstCompany.id}` }
            : { label: 'View your profile', to: '/reviewer/profile' },
        };

  // Everything else still waiting on you.
  const attentionItems: AttentionItemData[] = [
    ...data.attention_items
      .filter(
        (i) =>
          !(
            usedHeroReview &&
            i.company_id === heroReviewItem!.company_id &&
            i.report_id === heroReviewItem!.report_id
          )
      )
      .map<AttentionItemData>((i) => ({
        tone: 'attention',
        icon: <FileBarChart className="h-[18px] w-[18px]" />,
        title: `${i.company_name} — report v${i.report_version}`,
        detail: `Review ${i.review_status ? i.review_status.replace(/_/g, ' ') : 'not started'}`,
        action: {
          label: 'Review',
          to: `/reviewer/companies/${i.company_id}/reports/${i.report_id}/review`,
        },
      })),
    ...data.recent_followups
      .filter((f) => f.status === 'awaiting_reply')
      .map<AttentionItemData>((f) => ({
        tone: 'attention',
        icon: <MessageSquare className="h-[18px] w-[18px]" />,
        title: f.employee_name || `Employee #${f.employee_id}`,
        detail: `${f.company_name} · awaiting reply`,
        action: {
          label: 'Open thread',
          to: `/reviewer/companies/${f.company_id}/employees/${f.employee_id}/followup`,
        },
      })),
    ...(data.unread_count > 0
      ? [
          {
            tone: 'attention' as const,
            icon: <Bell className="h-[18px] w-[18px]" />,
            title: `${data.unread_count} unread notification${data.unread_count === 1 ? '' : 's'}`,
            detail: 'Co-reviewer and platform updates',
            action: { label: 'Open inbox', to: '/reviewer/inbox' },
          },
        ]
      : []),
  ];

  const pendingReviewTo = usedHeroReview
    ? `/reviewer/companies/${heroReviewItem!.company_id}/reports/${heroReviewItem!.report_id}/review`
    : companiesTo;

  return (
    <div className="space-y-6">
      {/* Greeting + status */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="m-0 font-display text-2xl font-semibold text-foreground">
            {greeting}, {firstName}
          </h1>
          <p className="m-0 mt-1 text-sm text-muted-foreground">
            Here’s what’s waiting on you across your assigned companies.
          </p>
        </div>
        <StatusChip tone={statusChip.tone} label={statusChip.label} />
      </div>

      {/* Profile completeness banner (unpublished profile only) */}
      {data.profile.profile_status !== 'published' && data.profile.profile_completeness_percent != null && (
        <div className="rounded-md border border-accent/30 bg-accent-muted px-4 py-3 text-sm text-foreground">
          Your expert profile is {data.profile.profile_completeness_percent}% complete.{' '}
          <Link to="/reviewer/profile" className="font-semibold text-accent-hover hover:underline">
            Complete your profile →
          </Link>
        </div>
      )}

      {error && (
        <div className="rounded-md border border-status-warning/30 bg-status-warningBg px-4 py-3 text-sm text-foreground">
          {error}
        </div>
      )}

      {/* Hero next step */}
      <NextStepHero
        eyebrow={hero.eyebrow}
        title={hero.title}
        description={hero.description}
        primaryAction={hero.primaryAction}
      />

      {/* Also waiting */}
      <AttentionList items={attentionItems} />

      {/* Outcome tiles */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
        <OutcomeTile
          icon={<Building2 className="h-4 w-4" />}
          label="Companies assigned"
          value={stats.assigned_companies}
          action={{
            label: firstCompany ? 'Open a company' : 'Set up profile',
            to: companiesTo,
          }}
        />
        <OutcomeTile
          icon={<FileBarChart className="h-4 w-4" />}
          label="Avg readiness"
          value={stats.avg_readiness}
          valueSuffix="%"
          action={{ label: 'View companies', to: companiesTo }}
        />
        <OutcomeTile
          icon={<FileBarChart className="h-4 w-4" />}
          label="Pending reviews"
          value={stats.pending_reviews}
          action={{
            label: stats.pending_reviews > 0 ? 'Start reviewing' : 'View companies',
            to: pendingReviewTo,
          }}
        />
      </div>

      {/* Your companies */}
      <section className="space-y-4">
        <h2 className="m-0 font-display text-lg font-semibold text-foreground">Your companies</h2>
        {list.length === 0 ? (
          <EmptyState title="No companies assigned yet" description="Contact your platform administrator." />
        ) : (
          <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
            {list.map((c) => {
              const rate = companyCompletionRate(c);
              const pending = isReviewPending(c);
              const actionLabel =
                pending && c.latest_report ? `Review report v${c.latest_report.version}` : 'Open';
              return (
                <Link
                  key={c.id}
                  to={`/reviewer/companies/${c.id}`}
                  className="block rounded-card no-underline focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
                >
                  <Card className="h-full transition-shadow hover:shadow-card">
                    <div className="flex items-start justify-between gap-2">
                      <h3 className="m-0 font-display font-semibold text-foreground">{c.name}</h3>
                      {pending && <Badge variant="warning">Review</Badge>}
                    </div>
                    <div className="mt-3 flex flex-wrap gap-2">
                      <Badge variant="info">{Math.round(c.report_readiness_score ?? 0)}% readiness</Badge>
                      <Badge variant="neutral">{rate}% participation</Badge>
                      {(c.ready_documents ?? 0) > 0 && (
                        <Badge variant="neutral">{c.ready_documents} docs ready</Badge>
                      )}
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
                    <p className="mt-3 text-sm font-semibold text-accent-hover">{actionLabel} →</p>
                  </Card>
                </Link>
              );
            })}
          </div>
        )}
      </section>

      {/* Secondary: portfolio charts */}
      {list.length > 0 && (
        <div className="grid gap-4 lg:grid-cols-2">
          <Card title="Readiness by company">
            <SimpleBarChart
              data={readinessByCompany}
              emptyLabel="Assign companies to see portfolio readiness."
              valueSuffix="%"
              layout="horizontal"
              height={Math.max(200, readinessByCompany.length * 40)}
            />
          </Card>
          <Card title="Participation rate by company">
            <SimpleBarChart
              data={participationByCompany}
              emptyLabel="Participation appears once employees are invited."
              valueSuffix="%"
              layout="horizontal"
              height={Math.max(200, participationByCompany.length * 40)}
            />
          </Card>
        </div>
      )}
    </div>
  );
}
