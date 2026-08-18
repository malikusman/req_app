import { useEffect, useState, type ReactNode } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  FileText,
  FileBarChart,
  HelpCircle,
  Radio,
  Sparkles,
  UserCircle,
  Users,
  Zap,
} from 'lucide-react';
import { api, type CompanyDashboardPayload, type ReviewerPublicCard } from '../../lib/api';
import { useAuth, useCompanyToken } from '../../lib/auth';
import {
  DashboardShell,
  Card,
  StrengthBar,
  Timeline,
  Badge,
  Button,
  EmptyState,
  NextStepHero,
  AttentionList,
  JourneySteps,
  OutcomeTile,
  type JourneyStep,
  type AttentionItemData,
} from '../../components/ui';
import { cn } from '../../lib/cn';
import { nextBestAction, type DashboardAction, type DashboardActionId } from './nextBestAction';

function iconFor(id: DashboardActionId): ReactNode {
  switch (id) {
    case 'review-report':
      return <FileBarChart className="h-[18px] w-[18px]" />;
    case 'answer-questions':
      return <HelpCircle className="h-[18px] w-[18px]" />;
    case 'nudge-stalled':
      return <Users className="h-[18px] w-[18px]" />;
    case 'add-profile':
      return <UserCircle className="h-[18px] w-[18px]" />;
    case 'get-started':
      return <FileText className="h-[18px] w-[18px]" />;
    default:
      return <Radio className="h-[18px] w-[18px]" />;
  }
}

function toAttentionItem(a: DashboardAction): AttentionItemData {
  return {
    tone: a.tone,
    icon: iconFor(a.id),
    title: a.attnTitle,
    detail: a.attnDetail,
    action: a.attnActionLabel ? { label: a.attnActionLabel, to: a.to } : undefined,
    optionalLabel: a.optionalLabel,
  };
}

function bandFor(strength: number): { label: string; variant: 'success' | 'warning' | 'neutral' } {
  if (strength >= 0.66) return { label: 'High', variant: 'success' };
  if (strength >= 0.4) return { label: 'Medium', variant: 'warning' };
  return { label: 'Low', variant: 'neutral' };
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

export function CompanyDashboard() {
  const token = useCompanyToken();
  const { session } = useAuth();
  const navigate = useNavigate();
  const [data, setData] = useState<CompanyDashboardPayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [reviewers, setReviewers] = useState<ReviewerPublicCard[]>([]);
  const [unansweredQuestions, setUnansweredQuestions] = useState(0);

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
    api
      .companyExpertReviewers(token)
      .then((d) => setReviewers(d.expert_reviewers || []))
      .catch(() => setReviewers([]));
    api
      .discoveryQuestions(token)
      .then((d) => {
        const qs = d.questions || [];
        setUnansweredQuestions(qs.filter((q) => !q.feedback).length);
      })
      .catch(() => setUnansweredQuestions(0));
  }, [token]);

  if (loading) {
    return <DashboardShell title="Home" description="Loading your discovery workspace…" loading />;
  }

  if (!data) {
    return (
      <DashboardShell title="Home" description="Your guided discovery workspace." loading={false}>
        <EmptyState
          title="Unable to load dashboard"
          description={error || 'Complete onboarding, then upload documents or invite employees to start discovery.'}
        />
      </DashboardShell>
    );
  }

  const snapshot = data.snapshot;
  const score = Math.round(data.report_readiness_score ?? 0);
  const breakdown = data.report_readiness_breakdown ?? {};
  const intel = data.intel_counts;
  const readyDocs = Number(intel?.ready_documents ?? breakdown.ready_documents ?? 0);
  const totalDocs = Number(intel?.total_documents ?? 0);
  const signalCount = intel?.signal_count ?? snapshot?.signal_count ?? snapshot?.top_pain_points.length ?? 0;
  const patternCount = intel?.pattern_count ?? snapshot?.emerging_patterns?.length ?? 0;
  const recommendationCount = intel?.recommendation_count ?? snapshot?.recommendation_count ?? 0;
  const docsFirstPhase = Boolean(data.docs_first_phase ?? data.company.docs_first_phase);
  const docsFirstActive = docsFirstPhase && (readyDocs > 0 || score > 0 || signalCount > 0);
  const processingDocs = docsFirstPhase && readyDocs === 0 && score === 0 && signalCount === 0;
  const docsOnlyView = docsFirstPhase && docsFirstActive;
  const qPercent = Math.round(data.questionnaire_completion_percent ?? 0);
  const qComplete = Boolean(data.questionnaire_completed_at) || qPercent >= 100;

  const invited = data.company.invited_count ?? 0;
  const completed = data.company.completed_count ?? 0;
  const reviewer = reviewers[0];
  const report = data.latest_report;
  const reportReady = Boolean(report && (report.status === 'ready' || report.status === 'shared'));

  const firstName = (session?.portal === 'company' ? session.user.name : '').trim().split(/\s+/)[0] || 'there';
  const hour = new Date().getHours();
  const greeting = hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening';

  const statusChip: { tone: 'ready' | 'progress' | 'setup'; label: string } = reportReady
    ? { tone: 'ready', label: 'Report ready' }
    : invited > 0 || totalDocs > 0
      ? { tone: 'progress', label: 'Discovery in progress' }
      : { tone: 'setup', label: 'Setting up' };

  const { hero: rankedHero, also } = nextBestAction(data, {
    reviewerName: reviewer?.name ?? null,
    unansweredQuestions,
    signalCount,
    patternCount,
    recommendationCount,
    readinessScore: score,
  });

  const processingHero: DashboardAction = {
    id: 'running',
    eyebrow: 'In progress',
    title: 'We’re analyzing your documents',
    description:
      'Your uploaded documents are being processed. Frictions and themes appear here as soon as they’re ready — nothing needs you yet.',
    primaryLabel: 'View documents',
    to: '/company/documents',
    tone: 'neutral',
    attnTitle: '',
  };
  const hero = processingDocs ? processingHero : rankedHero;
  const attentionItems = processingDocs ? [] : also.map(toAttentionItem);

  // Journey steps — single "now" at the current frontier.
  const interviewsDone = reportReady || (invited > 0 && completed >= invited);
  const journeySteps: JourneyStep[] = [
    {
      label: 'Profile',
      sublabel: qComplete ? 'complete' : 'optional',
      status: qComplete ? 'done' : 'optional',
    },
    {
      label: 'Documents',
      sublabel: readyDocs > 0 ? `${readyDocs} analyzed` : undefined,
      status: readyDocs > 0 ? 'done' : 'todo',
    },
    {
      label: 'Team invited',
      sublabel: invited > 0 ? `${completed} of ${invited}` : undefined,
      status: invited > 0 ? 'done' : 'todo',
    },
    {
      label: 'Interviews',
      sublabel:
        invited > 0 ? `${Math.round((completed / Math.max(1, invited)) * 100)}% done` : undefined,
      status: interviewsDone ? 'done' : invited > 0 ? 'now' : 'todo',
    },
    {
      label: 'Report',
      sublabel: reportReady && report ? `v${report.version} ready` : 'pending',
      status: reportReady ? 'now' : 'todo',
    },
  ];
  const journeyDone = journeySteps.filter((s) => s.status === 'done').length;

  const painPoints = (snapshot?.top_pain_points ?? []).slice(0, 3);
  const timeline = snapshot?.recent_timeline ?? [];

  return (
    <div className="space-y-6">
      {/* Greeting + status */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h1 className="m-0 font-display text-2xl font-semibold text-foreground">
            {greeting}, {firstName}
          </h1>
          <p className="m-0 mt-1 text-sm text-muted-foreground">
            Here’s where your discovery stands — and the one thing worth doing next.
          </p>
        </div>
        <StatusChip tone={statusChip.tone} label={statusChip.label} />
      </div>

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
        primaryAction={{ label: hero.primaryLabel, to: hero.to }}
        readiness={hero.readiness}
      />

      {/* Also waiting */}
      <AttentionList items={attentionItems} />

      {/* Journey */}
      <Card padding={false} className="p-5 sm:p-6">
        <div className="mb-4 flex items-center justify-between gap-3">
          <span className="font-display text-sm font-semibold text-foreground">Your discovery journey</span>
          <span className="text-xs text-muted-foreground">
            {journeyDone} of {journeySteps.length} complete
          </span>
        </div>
        <JourneySteps steps={journeySteps} />
      </Card>

      {/* Outcome tiles */}
      {!processingDocs && (
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3">
          {docsOnlyView ? (
            <OutcomeTile
              icon={<FileText className="h-4 w-4" />}
              label="Documents analyzed"
              value={readyDocs}
              action={{ label: 'View documents', to: '/company/documents' }}
            />
          ) : (
            <OutcomeTile
              icon={<Users className="h-4 w-4" />}
              label="People engaged"
              value={completed}
              valueSuffix={`of ${invited}`}
              action={{ label: 'View your team', to: '/company/employees' }}
            />
          )}
          <OutcomeTile
            icon={<Zap className="h-4 w-4" />}
            label="Frictions surfaced"
            value={signalCount}
            action={{ label: 'See what we found', to: '/company/intelligence#signals' }}
          />
          <OutcomeTile
            icon={<Sparkles className="h-4 w-4" />}
            label="Cross-team themes"
            value={patternCount}
            action={{ label: 'See the patterns', to: '/company/intelligence#patterns' }}
          />
        </div>
      )}

      {/* Two panels */}
      <div className="grid gap-4 lg:grid-cols-2">
        <Card
          title="Top of what we found"
          action={
            <Link to="/company/reports" className="text-sm font-semibold text-accent-hover hover:underline">
              See the full report →
            </Link>
          }
          className="min-w-0"
        >
          {painPoints.length === 0 ? (
            <p className="m-0 text-sm text-muted-foreground">
              {docsOnlyView
                ? 'Upload procedure or finance documents to surface baseline frictions.'
                : 'Complete more interviews to surface frictions.'}
            </p>
          ) : (
            <div className="space-y-4">
              {painPoints.map((s) => {
                const band = bandFor(s.strength);
                return (
                  <div key={s.id} className="min-w-0">
                    <div className="mb-1.5 flex items-baseline justify-between gap-2">
                      <span className="min-w-0 truncate text-sm font-semibold text-foreground">{s.label}</span>
                      <Badge variant={band.variant}>{band.label}</Badge>
                    </div>
                    <StrengthBar strength={s.strength} label="" />
                  </div>
                );
              })}
            </div>
          )}
        </Card>

        <Card title="Your reviewer" className="min-w-0">
          {reviewer ? (
            <div className="space-y-4">
              <div className="flex items-center gap-3">
                <span className="flex h-11 w-11 shrink-0 items-center justify-center rounded-full bg-foreground font-display text-base font-semibold text-background">
                  {reviewer.name.charAt(0).toUpperCase()}
                </span>
                <div className="min-w-0">
                  <p className="m-0 font-display text-sm font-semibold text-foreground">{reviewer.name}</p>
                  {reviewer.headline && (
                    <p className="m-0 truncate text-xs text-muted-foreground">{reviewer.headline}</p>
                  )}
                  {reviewer.expertise_tags?.length > 0 && (
                    <div className="mt-1.5 flex flex-wrap gap-1.5">
                      {reviewer.expertise_tags.slice(0, 3).map((tag) => (
                        <span
                          key={tag}
                          className="rounded-badge border border-border bg-background px-2 py-0.5 text-[11px] text-muted-foreground"
                        >
                          {tag}
                        </span>
                      ))}
                    </div>
                  )}
                </div>
              </div>

              {unansweredQuestions > 0 && (
                <div className="flex items-center gap-3 rounded-md border border-status-warning/30 bg-status-warningBg px-3.5 py-3">
                  <HelpCircle className="h-4 w-4 shrink-0 text-status-warning" />
                  <div className="min-w-0">
                    <p className="m-0 text-sm font-semibold text-foreground">
                      {unansweredQuestions} question{unansweredQuestions === 1 ? '' : 's'} need your input
                    </p>
                    <p className="m-0 text-xs text-muted-foreground">Answering makes your next report stronger</p>
                  </div>
                </div>
              )}

              <div className="flex flex-col gap-2 sm:flex-row">
                {unansweredQuestions > 0 && (
                  <Link to="/company/outreaches" className="w-full sm:w-auto">
                    <Button className="w-full sm:w-auto">Answer questions</Button>
                  </Link>
                )}
                <Link to="/company/reports" className="w-full sm:w-auto">
                  <Button variant="secondary" className="w-full sm:w-auto">
                    View report
                  </Button>
                </Link>
              </div>
            </div>
          ) : (
            <EmptyState
              icon={UserCircle}
              title="No reviewer assigned yet"
              description="A Worktruth expert appears here once they’re assigned to your company."
              className="py-8"
            />
          )}
        </Card>
      </div>

      {/* Recent activity */}
      {timeline.length > 0 && (
        <Card title="Recent activity" className="min-w-0">
          <Timeline
            events={timeline.map((e, i) => ({
              id: String(i),
              title: e.title,
              summary: e.summary,
              occurredAt: e.occurred_at,
            }))}
          />
        </Card>
      )}
    </div>
  );
}
