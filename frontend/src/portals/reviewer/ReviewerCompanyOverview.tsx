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
  FileText,
  Package,
} from 'lucide-react';
import {
  api,
  type CompanyPattern,
  type CompanySignal,
  type Employee,
  type Recommendation,
  type ReviewerCompanyDetail,
} from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import {
  PageHeader,
  Card,
  StatCard,
  Button,
  Badge,
  Skeleton,
  EmptyState,
  Select,
  Textarea,
  Tabs,
} from '../../components/ui';
import { label } from '../../lib/labels';
import { ReviewerChatDrawer } from './workspace/ReviewerChatDrawer';
import { AgenticIdeasPanel } from '../shared/AgenticIdeasPanel';

type ConversationRow = {
  id: number;
  employee_id: number;
  employee_name: string | null;
  status: string;
};

const ROSTER_PREVIEW = 12;

export function ReviewerCompanyOverview() {
  const { companyId } = useParams();
  const token = useReviewerToken();
  const [company, setCompany] = useState<ReviewerCompanyDetail | null>(null);
  const [conversations, setConversations] = useState<ConversationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [chatOpen, setChatOpen] = useState(false);
  const [signals, setSignals] = useState<CompanySignal[]>([]);
  const [patterns, setPatterns] = useState<CompanyPattern[]>([]);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);
  const [tab, setTab] = useState('overview');

  useEffect(() => {
    if (!token || !companyId) return;
    setLoading(true);
    setError('');
    Promise.all([
      api.reviewerCompany(token, Number(companyId)),
      api.reviewerConversations(token, Number(companyId)).catch(() => ({ conversations: [] })),
      api.reviewerEmployees(token, Number(companyId)).catch(() => ({ employees: [] })),
      api.reviewerSignals(token, Number(companyId)).catch(() => ({ signals: [] })),
      api.reviewerPatterns(token, Number(companyId)).catch(() => ({ patterns: [] })),
      api.reviewerRecommendations(token, Number(companyId)).catch(() => ({ recommendations: [] })),
    ])
      .then(([detail, convs, employeesData, signalsData, patternsData, recommendationsData]) => {
        setCompany(detail.company);
        setConversations(convs.conversations);
        setEmployees(employeesData.employees);
        setSignals(signalsData.signals);
        setPatterns(patternsData.patterns);
        setRecommendations(recommendationsData.recommendations);
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
  const hasCoReviewers = company.co_reviewer_count >= 1;
  const completedInterviews = conversations.filter((c) => c.status === 'completed').length;
  const roster =
    employees.length > 0
      ? employees
      : conversations.map((c) => ({
          id: c.employee_id,
          phone_e164: '',
          email: null,
          display_name: c.employee_name,
          department: null,
          participation_status: c.status,
          onboarding_step: 'unknown',
          preferred_language: null,
          invited_at: null,
          started_at: null,
          completed_at: null,
          last_active_at: null,
          last_nudged_at: null,
        }));

  return (
    <div className="space-y-6">
      <PageHeader
        title={company.name}
        description="Everything shared by this company — the report to review, interviews, and your co-reviewers."
        breadcrumbs={[{ label: 'Dashboard', href: '/reviewer/dashboard' }, { label: company.name }]}
      />

      <Tabs
        tabs={[
          { value: 'overview', label: 'Overview' },
          { value: 'profile', label: 'Profile' },
          { value: 'interviews', label: 'Interviews' },
          { value: 'intelligence', label: 'Intelligence' },
          { value: 'clarifications', label: 'Clarifications' },
          { value: 'ideas', label: 'Agentic ideas' },
        ]}
        value={tab}
        onChange={setTab}
      />

      {tab === 'profile' && (
        <div className="space-y-6">
          <Card title="Firmographics">
            {company.company_profile || company.website_url ? (
              <dl className="m-0 grid gap-3 sm:grid-cols-2 text-sm">
                {[
                  ['Industry', company.company_profile?.industry],
                  ['Sub-industry', company.company_profile?.sub_industry],
                  ['Size', company.company_profile?.size_band],
                  ['Region', company.company_profile?.region || company.company_profile?.country],
                  ['Revenue band', company.company_profile?.annual_revenue_band],
                  ['Website', company.website_url],
                ].map(([label, value]) =>
                  value ? (
                    <div key={String(label)}>
                      <dt className="text-muted-foreground">{label}</dt>
                      <dd className="m-0 font-medium">
                        {label === 'Website' && typeof value === 'string' ? (
                          <a href={value} target="_blank" rel="noreferrer" className="text-accent hover:underline">
                            {value}
                          </a>
                        ) : (
                          String(value)
                        )}
                      </dd>
                    </div>
                  ) : null
                )}
              </dl>
            ) : (
              <EmptyState
                title="No profile yet"
                description="Firmographics appear after the company completes onboarding."
              />
            )}
          </Card>

          {(Array.isArray(company.company_profile?.business_goals)
            ? company.company_profile.business_goals.length > 0
            : Boolean(company.company_profile?.business_goals)) && (
            <Card title="Business goals">
              <ul className="m-0 list-disc space-y-1 pl-5 text-sm">
                {(Array.isArray(company.company_profile?.business_goals)
                  ? company.company_profile!.business_goals!
                  : [String(company.company_profile?.business_goals)]
                ).map((g) => (
                  <li key={g}>{g}</li>
                ))}
              </ul>
            </Card>
          )}

          {Array.isArray(company.company_profile?.org_departments) &&
            company.company_profile!.org_departments!.length > 0 && (
              <Card title="Departments">
                <p className="m-0 text-sm">{company.company_profile!.org_departments!.join(', ')}</p>
              </Card>
            )}

          <Card title="Applications in use">
            {(company.company_systems || []).length === 0 ? (
              <EmptyState
                title="No client stack listed"
                description="Systems from the company questionnaire or platform stack tab will show here."
              />
            ) : (
              <ul className="m-0 list-none space-y-2 p-0 text-sm">
                {company.company_systems!.map((sys) => (
                  <li
                    key={`${sys.name}-${sys.category}`}
                    className="flex items-center justify-between gap-2 rounded-lg border border-border px-3 py-2"
                  >
                    <span className="font-medium">{sys.name}</span>
                    <Badge variant="info">{sys.category || 'other'}</Badge>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          {(company.web_research || []).length > 0 && (
            <Card title="Website research">
              <div className="space-y-3">
                {company.web_research!.map((entry) => (
                  <div key={entry.id} className="rounded-lg border border-border p-3 text-sm">
                    <p className="m-0 font-medium">{entry.title}</p>
                    <p className="m-0 mt-2 text-muted-foreground">{entry.content}</p>
                    {entry.url && (
                      <a
                        href={entry.url}
                        target="_blank"
                        rel="noreferrer"
                        className="mt-2 inline-block text-xs text-accent hover:underline"
                      >
                        {entry.url}
                      </a>
                    )}
                  </div>
                ))}
              </div>
            </Card>
          )}
        </div>
      )}

      {tab === 'overview' && (
        <div className="space-y-6">
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
                        <span className="capitalize">
                          {company.latest_report?.status.replace(/_/g, ' ')}
                        </span>
                      </p>
                      <div className="mt-2 flex items-center gap-2 text-sm">
                        Your review:
                        <Badge variant={reviewSubmitted ? 'success' : 'warning'}>
                          {label('reviewStatus', company.my_review_status ?? 'pending')}
                        </Badge>
                      </div>
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

              <Card title="Evidence explorer">
                <div className="flex flex-wrap items-center justify-between gap-4">
                  <p className="m-0 text-sm text-muted-foreground">
                    Explore how interviews, documents, signals, and recommendations connect.
                  </p>
                  <div className="flex flex-wrap gap-2">
                    <Link to={`/reviewer/companies/${companyId}/documents`}>
                      <Button variant="secondary" icon={<FileText className="h-4 w-4" />}>
                        Documents
                      </Button>
                    </Link>
                    <Link to={`/reviewer/companies/${companyId}/analysis`}>
                      <Button variant="secondary" icon={<ClipboardCheck className="h-4 w-4" />}>
                        Analysis
                      </Button>
                    </Link>
                    <Link to={`/reviewer/companies/${companyId}/catalog`}>
                      <Button variant="secondary" icon={<Package className="h-4 w-4" />}>
                        Catalog matches
                      </Button>
                    </Link>
                  </div>
                  <p className="m-0 mt-3 text-xs text-muted-foreground">
                    Endorse catalog tools or draft Agentic ideas from the company overview — those feed the next PDF.
                  </p>
                </div>
              </Card>
            </div>

            <div className="space-y-6">
              <Card title="Quick actions">
                <div className="flex flex-col gap-2">
                  <Link to={`/reviewer/companies/${companyId}/conversations`} className="w-full">
                    <Button
                      variant="secondary"
                      className="w-full justify-start"
                      icon={<Users className="h-4 w-4" />}
                    >
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
                    <Button
                      variant="secondary"
                      className="w-full justify-start"
                      icon={<MessagesSquare className="h-4 w-4" />}
                    >
                      Follow-ups &amp; inbox
                    </Button>
                  </Link>
                </div>
              </Card>

              <Card title="Collaboration">
                {hasCoReviewers ? (
                  <p className="m-0 text-sm text-muted-foreground">
                    {company.co_reviewer_count} co-reviewer{company.co_reviewer_count === 1 ? '' : 's'}{' '}
                    on {company.name}. Use co-reviewer chat to stay aligned before you submit.
                  </p>
                ) : (
                  <p className="m-0 text-sm text-muted-foreground">
                    You’re the only reviewer assigned to {company.name}. A second reviewer can be added
                    by the platform team when needed.
                  </p>
                )}
              </Card>
            </div>
          </div>
        </div>
      )}

      {tab === 'interviews' && (
        <div className="grid gap-6 lg:grid-cols-2">
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
                title={
                  signals.length > 0 || patterns.length > 0
                    ? 'Document baseline — no interviews yet'
                    : 'No interviews yet'
                }
                description={
                  signals.length > 0 || patterns.length > 0
                    ? 'This company has signals from internal documents. Review intelligence and reports; WhatsApp follow-ups become available after employees complete discovery.'
                    : 'Employee interviews shared by this company will show up here for you to review.'
                }
              />
            ) : (
              <>
                <p className="mb-3 text-sm text-muted-foreground">
                  {completedInterviews} of {conversations.length} completed · open a transcript to read
                  it or send a WhatsApp follow-up to that employee.
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
                          <Badge variant={c.status === 'completed' ? 'success' : 'info'}>
                            {c.status}
                          </Badge>
                          <ChevronRight className="h-4 w-4 text-muted-foreground" />
                        </span>
                      </Link>
                    </li>
                  ))}
                </ul>
              </>
            )}
          </Card>

          <Card title="Employees">
            {roster.length === 0 ? (
              <EmptyState
                title="No employees yet"
                description="Employee roster will appear once the company starts inviting participants."
              />
            ) : (
              <ul className="m-0 list-none space-y-2 p-0">
                {roster.slice(0, ROSTER_PREVIEW).map((employee) => {
                  const conversation = conversations.find((c) => c.employee_id === employee.id);
                  return (
                    <li key={employee.id} className="rounded-lg border border-border px-3 py-2.5">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <div>
                          <p className="m-0 text-sm font-medium text-foreground">
                            {employee.display_name || `Employee #${employee.id}`}
                          </p>
                          <p className="m-0 text-xs text-muted-foreground">
                            {employee.department || 'No department'} ·{' '}
                            {employee.last_active_at
                              ? new Date(employee.last_active_at).toLocaleString()
                              : 'No activity yet'}
                          </p>
                        </div>
                        <Badge
                          variant={
                            employee.participation_status === 'completed' ? 'success' : 'info'
                          }
                        >
                          {employee.participation_status.replace(/_/g, ' ')}
                        </Badge>
                      </div>
                      <div className="mt-2 flex flex-wrap items-center gap-3 text-sm">
                        <Link
                          to={`/reviewer/companies/${companyId}/employees/${employee.id}/followup`}
                          className="font-medium text-accent hover:underline"
                        >
                          Follow-up
                        </Link>
                        {conversation ? (
                          <Link
                            to={`/reviewer/companies/${companyId}/conversations/${conversation.id}`}
                            className="font-medium text-accent hover:underline"
                          >
                            Transcript
                          </Link>
                        ) : (
                          <span className="text-muted-foreground">Transcript unavailable</span>
                        )}
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
          </Card>
        </div>
      )}

      {tab === 'intelligence' && (
        <Card title="Intelligence preview">
          {signals.length === 0 && patterns.length === 0 && recommendations.length === 0 ? (
            <EmptyState
              title="No intelligence yet"
              description="Signals, patterns, and recommendations appear after enough interview evidence is available."
            />
          ) : (
            <div className="grid gap-6 lg:grid-cols-3">
              <div>
                <p className="mb-2 text-sm font-medium text-foreground">Top signals</p>
                {signals.length === 0 ? (
                  <p className="m-0 text-sm text-muted-foreground">None yet.</p>
                ) : (
                  signals.slice(0, 6).map((signal) => (
                    <div
                      key={signal.id}
                      className="mb-2 rounded-lg border border-border bg-muted px-3 py-2"
                    >
                      <p className="m-0 text-sm font-medium text-foreground">{signal.label}</p>
                      <p className="m-0 text-xs text-muted-foreground">
                        Strength {signal.strength} · {signal.evidence_count} evidence items
                      </p>
                    </div>
                  ))
                )}
              </div>

              <div>
                <p className="mb-2 text-sm font-medium text-foreground">Top patterns</p>
                {patterns.length === 0 ? (
                  <p className="m-0 text-sm text-muted-foreground">None yet.</p>
                ) : (
                  patterns.slice(0, 6).map((pattern) => (
                    <div
                      key={pattern.id}
                      className="mb-2 rounded-lg border border-border bg-muted px-3 py-2"
                    >
                      <p className="m-0 text-sm font-medium text-foreground">{pattern.title}</p>
                      <p className="m-0 text-xs text-muted-foreground">{pattern.description}</p>
                    </div>
                  ))
                )}
              </div>

              <div>
                <p className="mb-2 text-sm font-medium text-foreground">Priority recommendations</p>
                {recommendations.length === 0 ? (
                  <p className="m-0 text-sm text-muted-foreground">None yet.</p>
                ) : (
                  recommendations.slice(0, 6).map((rec) => (
                    <div
                      key={rec.id}
                      className="mb-2 rounded-lg border border-border bg-muted px-3 py-2"
                    >
                      <p className="m-0 text-sm font-medium text-foreground">{rec.title}</p>
                      <p className="m-0 text-xs text-muted-foreground">{rec.description}</p>
                    </div>
                  ))
                )}
              </div>
            </div>
          )}
        </Card>
      )}

      {tab === 'clarifications' && (
        <Card title="Ask company admin">
          <p className="mb-3 text-sm text-muted-foreground">
            Send a portal clarification directly to the company admin (CEO). No employee contact or
            approval gate.
          </p>
          <AskCompanyAdminPanel
            companyId={Number(companyId)}
            reportId={reportId}
            admins={company.company_admins || []}
          />
        </Card>
      )}

      {tab === 'ideas' && (
        <Card title="Agentic AI ideas">
          <p className="mb-3 text-sm text-muted-foreground">
            Draft and publish agentic opportunities for this company. Published ideas appear in the
            next generated PDF.
          </p>
          {token ? (
            <AgenticIdeasPanel token={token} companyId={Number(companyId)} mode="reviewer" />
          ) : null}
        </Card>
      )}

      <ReviewerChatDrawer companyId={Number(companyId)} open={chatOpen} onOpenChange={setChatOpen} />
    </div>
  );
}

function AskCompanyAdminPanel({
  companyId,
  reportId,
  admins,
}: {
  companyId: number;
  reportId?: number;
  admins: { id: number; name: string; email: string }[];
}) {
  const token = useReviewerToken();
  const [body, setBody] = useState('');
  const [recipientId, setRecipientId] = useState<number | ''>(admins[0]?.id ?? '');
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState<{ kind: 'success' | 'error'; text: string } | null>(null);
  const [outreaches, setOutreaches] = useState<
    Array<{
      id: number;
      body: string;
      status: string;
      recipient_type?: string;
      recipient_name?: string | null;
      sent_at?: string | null;
      replies?: Array<{
        id: number;
        channel: string;
        body: string;
        received_at: string;
      }>;
    }>
  >([]);

  const load = () => {
    if (!token) return;
    api
      .reviewerOutreaches(token, companyId)
      .then((d) => {
        const list = (d.outreaches as typeof outreaches).filter(
          (o) => o.recipient_type === 'company_admin'
        );
        setOutreaches(list);
      })
      .catch(() => setOutreaches([]));
  };

  useEffect(() => {
    load();
  }, [token, companyId]);

  useEffect(() => {
    if (admins.length && recipientId === '') {
      setRecipientId(admins[0].id);
    }
  }, [admins, recipientId]);

  const submit = async () => {
    if (!token || !body.trim()) return;
    setSaving(true);
    setNotice(null);
    try {
      await api.createReviewerOutreach(token, companyId, {
        body: body.trim(),
        purpose: 'clarification',
        channel: 'portal',
        recipient_type: 'company_admin',
        recipient_id: typeof recipientId === 'number' ? recipientId : undefined,
        report_id: reportId,
        reason: 'needs_info',
      });
      setBody('');
      setNotice({ kind: 'success', text: 'Sent to the company admin Clarifications inbox.' });
      load();
    } catch (err) {
      setNotice({
        kind: 'error',
        text: err instanceof Error ? err.message : 'Failed to send clarification',
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-4">
      {outreaches.length > 0 && (
        <ul className="space-y-3">
          {outreaches.slice(0, 6).map((o) => {
            const replies = o.replies || [];
            return (
              <li key={o.id} className="rounded-md border border-border px-3 py-2 text-sm">
                <div className="flex flex-wrap items-center gap-2">
                  <Badge
                    variant={
                      o.status === 'sent' || o.status === 'replied'
                        ? 'success'
                        : o.status === 'closed'
                          ? 'neutral'
                          : 'info'
                    }
                  >
                    {o.status}
                  </Badge>
                  {o.recipient_name && (
                    <span className="text-xs text-muted-foreground">{o.recipient_name}</span>
                  )}
                </div>
                <p className="mt-1 m-0 text-sm">{o.body}</p>
                {replies.length > 0 ? (
                  <div className="mt-3 space-y-2 border-t border-border pt-2">
                    <p className="m-0 text-xs font-medium uppercase tracking-wide text-muted-foreground">
                      Replies
                    </p>
                    {replies.map((r) => (
                      <div key={r.id} className="rounded-md border border-border bg-muted/40 px-2.5 py-2">
                        <p className="m-0 text-xs text-muted-foreground">
                          {r.channel} · {new Date(r.received_at).toLocaleString()}
                        </p>
                        <p className="m-0 mt-1 whitespace-pre-wrap text-sm text-foreground">{r.body}</p>
                      </div>
                    ))}
                  </div>
                ) : o.status === 'closed' || o.status === 'replied' ? (
                  <p className="mt-2 m-0 text-xs text-muted-foreground">No reply body recorded.</p>
                ) : null}
              </li>
            );
          })}
        </ul>
      )}

      <div className="space-y-3 border-t border-border pt-3">
        {admins.length > 1 && (
          <Select
            label="Recipient"
            value={recipientId === '' ? '' : String(recipientId)}
            onChange={(e) => setRecipientId(e.target.value ? Number(e.target.value) : '')}
            options={admins.map((a) => ({ value: String(a.id), label: `${a.name} (${a.email})` }))}
          />
        )}
        {admins.length === 1 && (
          <p className="m-0 text-xs text-muted-foreground">
            To: {admins[0].name} ({admins[0].email})
          </p>
        )}
        {admins.length === 0 && (
          <p className="m-0 text-xs text-muted-foreground">
            No active company admin on file — still sendable to default admin.
          </p>
        )}
        <Textarea
          label="Question"
          rows={3}
          value={body}
          onChange={(e) => setBody(e.target.value)}
          placeholder="Ask the company admin to clarify a finding, exception, or process gap…"
        />
        <Button size="sm" loading={saving} disabled={!body.trim()} onClick={submit}>
          Ask company admin
        </Button>
        {notice &&
          (notice.kind === 'success' ? (
            <p className="m-0 rounded-button bg-status-successBg px-3 py-2 text-xs text-status-success">
              {notice.text}
            </p>
          ) : (
            <p className="m-0 text-xs text-status-error">{notice.text}</p>
          ))}
      </div>
    </div>
  );
}
