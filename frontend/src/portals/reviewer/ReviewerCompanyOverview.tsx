import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import {
  MessageSquare,
  FileBarChart,
  Users,
  UserPlus,
  ChevronRight,
  ClipboardCheck,
  MessagesSquare,
} from 'lucide-react';
import { api, type ReviewerCompanyDetail } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, StatCard, Button, Badge, Skeleton, EmptyState } from '../../components/ui';
import { ReviewerChatDrawer } from './workspace/ReviewerChatDrawer';

type ConversationRow = {
  id: number;
  employee_id: number;
  employee_name: string | null;
  status: string;
};

const ROSTER_PREVIEW = 6;

export function ReviewerCompanyOverview() {
  const { companyId } = useParams();
  const token = useReviewerToken();
  const [company, setCompany] = useState<ReviewerCompanyDetail | null>(null);
  const [conversations, setConversations] = useState<ConversationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [chatOpen, setChatOpen] = useState(false);

  useEffect(() => {
    if (!token || !companyId) return;
    setLoading(true);
    setError('');
    Promise.all([
      api.reviewerCompany(token, Number(companyId)),
      api.reviewerConversations(token, Number(companyId)).catch(() => ({ conversations: [] })),
    ])
      .then(([detail, convs]) => {
        setCompany(detail.company);
        setConversations(convs.conversations);
      })
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load company'))
      .finally(() => setLoading(false));
  }, [token, companyId]);

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <div className="grid gap-4 md:grid-cols-3">
          {[1, 2, 3].map((i) => (
            <Skeleton key={i} variant="card" />
          ))}
        </div>
        <Skeleton variant="card" />
      </div>
    );
  }

  if (!company) {
    return (
      <div className="space-y-6">
        <PageHeader title="Company" description="Company overview and report review." />
        <EmptyState
          title={error || 'Company not found'}
          description="This company may no longer be assigned to you."
        />
      </div>
    );
  }

  const reportId = company.latest_report?.id;
  const reviewSubmitted = company.my_review_status === 'submitted';
  const hasCoReviewers = company.co_reviewer_count >= 2;
  const completedInterviews = conversations.filter((c) => c.status === 'completed').length;

  return (
    <div className="space-y-6">
      <PageHeader
        title={company.name}
        description="Everything shared by this company — the report to review, interviews, and your co-reviewers."
        breadcrumbs={[{ label: 'Dashboard', href: '/reviewer/dashboard' }, { label: company.name }]}
      />

      <div className="grid gap-4 md:grid-cols-3">
        <StatCard
          label="Readiness"
          value={`${company.report_readiness_score}%`}
          icon={<FileBarChart className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Participation"
          value={`${company.completed_count} / ${company.invited_count}`}
          icon={<Users className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Co-reviewers"
          value={company.co_reviewer_count}
          icon={<UserPlus className="h-5 w-5 text-accent" />}
        />
      </div>

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-2">
          <Card title="Report review">
            {reportId ? (
              <div className="flex flex-wrap items-center justify-between gap-4">
                <div>
                  <p className="m-0 text-sm text-muted-foreground">
                    Version {company.latest_report?.version} ·{' '}
                    <span className="capitalize">{company.latest_report?.status.replace(/_/g, ' ')}</span>
                  </p>
                  <p className="m-0 mt-2 flex items-center gap-2 text-sm">
                    Your review:
                    <Badge variant={reviewSubmitted ? 'success' : 'warning'}>
                      {company.my_review_status || 'pending'}
                    </Badge>
                  </p>
                </div>
                <Link to={`/reviewer/companies/${companyId}/reports/${reportId}/review`}>
                  <Button icon={<ClipboardCheck className="h-4 w-4" />}>
                    {reviewSubmitted ? 'View review' : 'Open report review'}
                  </Button>
                </Link>
              </div>
            ) : (
              <EmptyState
                title="No report yet"
                description="A report will appear here once this company reaches readiness and one is generated."
              />
            )}
          </Card>

          <Card
            title="Interviews"
            action={
              conversations.length > 0 ? (
                <Link
                  to={`/reviewer/companies/${companyId}/conversations`}
                  className="text-sm font-medium text-accent hover:underline"
                >
                  View all ({conversations.length})
                </Link>
              ) : undefined
            }
          >
            {conversations.length === 0 ? (
              <EmptyState
                title="No interviews yet"
                description="Employee interviews shared by this company will show up here for you to review."
              />
            ) : (
              <>
                <p className="mb-3 text-sm text-muted-foreground">
                  {completedInterviews} of {conversations.length} completed · open a transcript to read it or send a
                  WhatsApp follow-up to that employee.
                </p>
                <ul className="m-0 list-none space-y-2 p-0">
                  {conversations.slice(0, ROSTER_PREVIEW).map((c) => (
                    <li key={c.id}>
                      <Link
                        to={`/reviewer/companies/${companyId}/conversations/${c.id}`}
                        className="flex items-center justify-between rounded-lg border border-border px-3 py-2.5 transition-colors hover:bg-muted/50"
                      >
                        <span className="text-sm font-medium text-foreground">
                          {c.employee_name || `Employee #${c.employee_id}`}
                        </span>
                        <span className="flex items-center gap-2">
                          <Badge variant={c.status === 'completed' ? 'success' : 'info'}>{c.status}</Badge>
                          <ChevronRight className="h-4 w-4 text-muted-foreground" />
                        </span>
                      </Link>
                    </li>
                  ))}
                </ul>
              </>
            )}
          </Card>
        </div>

        <div className="space-y-6">
          <Card title="Quick actions">
            <div className="flex flex-col gap-2">
              <Link to={`/reviewer/companies/${companyId}/conversations`} className="w-full">
                <Button variant="secondary" className="w-full justify-start" icon={<Users className="h-4 w-4" />}>
                  All conversations
                </Button>
              </Link>
              {hasCoReviewers && (
                <Button
                  variant="secondary"
                  className="w-full justify-start"
                  onClick={() => setChatOpen(true)}
                  icon={<MessageSquare className="h-4 w-4" />}
                >
                  Co-reviewer chat
                </Button>
              )}
              <Link to="/reviewer/inbox" className="w-full">
                <Button variant="secondary" className="w-full justify-start" icon={<MessagesSquare className="h-4 w-4" />}>
                  Follow-ups &amp; inbox
                </Button>
              </Link>
            </div>
          </Card>

          <Card title="Collaboration">
            {hasCoReviewers ? (
              <p className="m-0 text-sm text-muted-foreground">
                {company.co_reviewer_count} reviewers are assigned to {company.name}. Use co-reviewer chat to stay
                aligned before you submit.
              </p>
            ) : (
              <p className="m-0 text-sm text-muted-foreground">
                You’re the only reviewer assigned to {company.name}. A second reviewer can be added by the platform
                team when needed.
              </p>
            )}
          </Card>
        </div>
      </div>

      <ReviewerChatDrawer companyId={Number(companyId)} open={chatOpen} onOpenChange={setChatOpen} />
    </div>
  );
}
