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
import { PageHeader, Card, StatCard, Button, Badge, Skeleton, EmptyState, Select, Textarea } from '../../components/ui';
import { ReviewerChatDrawer } from './workspace/ReviewerChatDrawer';
import { AgenticIdeasPanel } from '../shared/AgenticIdeasPanel';

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
  const [signals, setSignals] = useState<CompanySignal[]>([]);
  const [patterns, setPatterns] = useState<CompanyPattern[]>([]);
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [employees, setEmployees] = useState<Employee[]>([]);

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
  const roster = employees.length > 0 ? employees : conversations.map((c) => ({
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
                <Link to={`/reviewer/companies/${companyId}/catalog`}>
                  <Button variant="secondary" icon={<Package className="h-4 w-4" />}>
                    Catalog
                  </Button>
                </Link>
              </div>
            </div>
          </Card>

          <Card title="Meetings">
            <p className="mb-3 text-sm text-muted-foreground">
              Submit a call request for company-admin approval. Approved meetings show schedule and link here.
            </p>
            <MeetingRequestsPanel companyId={Number(companyId)} reportId={reportId} />
          </Card>

          <Card title="Ask company admin">
            <p className="mb-3 text-sm text-muted-foreground">
              Send a portal clarification directly to the company admin (CEO). No employee contact or approval gate.
            </p>
            <AskCompanyAdminPanel
              companyId={Number(companyId)}
              reportId={reportId}
              admins={company.company_admins || []}
            />
          </Card>

          <Card title="Agentic AI ideas">
            <p className="mb-3 text-sm text-muted-foreground">
              Draft and publish agentic opportunities for this company. Published ideas appear in the next generated PDF.
            </p>
            {token ? (
              <AgenticIdeasPanel token={token} companyId={Number(companyId)} mode="reviewer" />
            ) : null}
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
                title={signals.length > 0 || patterns.length > 0 ? 'Document baseline — no interviews yet' : 'No interviews yet'}
                description={
                  signals.length > 0 || patterns.length > 0
                    ? 'This company has signals from internal documents. Review intelligence and reports; WhatsApp follow-ups become available after employees complete discovery.'
                    : 'Employee interviews shared by this company will show up here for you to review.'
                }
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

          <Card title="Employees">
            {roster.length === 0 ? (
              <EmptyState
                title="No employees yet"
                description="Employee roster will appear once the company starts inviting participants."
              />
            ) : (
              <ul className="m-0 list-none space-y-2 p-0">
                {roster.slice(0, 8).map((employee) => {
                  const conversation = conversations.find((c) => c.employee_id === employee.id);
                  return (
                    <li key={employee.id} className="rounded-lg border border-border px-3 py-2.5">
                      <div className="flex flex-wrap items-center justify-between gap-2">
                        <div>
                          <p className="m-0 text-sm font-medium text-foreground">
                            {employee.display_name || `Employee #${employee.id}`}
                          </p>
                          <p className="m-0 text-xs text-muted-foreground">
                            {employee.department || 'No department'} · {employee.last_active_at ? new Date(employee.last_active_at).toLocaleString() : 'No activity yet'}
                          </p>
                        </div>
                        <Badge variant={employee.participation_status === 'completed' ? 'success' : 'info'}>
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

          <Card title="Intelligence preview">
            {signals.length === 0 && patterns.length === 0 && recommendations.length === 0 ? (
              <EmptyState
                title="No intelligence yet"
                description="Signals, patterns, and recommendations appear after enough interview evidence is available."
              />
            ) : (
              <div className="space-y-4">
                <div>
                  <p className="mb-2 text-sm font-medium text-foreground">Top signals</p>
                  {signals.slice(0, 2).map((signal) => (
                    <div key={signal.id} className="mb-2 rounded-lg border border-border bg-muted px-3 py-2">
                      <p className="m-0 text-sm font-medium text-foreground">{signal.label}</p>
                      <p className="m-0 text-xs text-muted-foreground">
                        Strength {signal.strength} · {signal.evidence_count} evidence items
                      </p>
                    </div>
                  ))}
                </div>

                <div>
                  <p className="mb-2 text-sm font-medium text-foreground">Top patterns</p>
                  {patterns.slice(0, 2).map((pattern) => (
                    <div key={pattern.id} className="mb-2 rounded-lg border border-border bg-muted px-3 py-2">
                      <p className="m-0 text-sm font-medium text-foreground">{pattern.title}</p>
                      <p className="m-0 text-xs text-muted-foreground">{pattern.description}</p>
                    </div>
                  ))}
                </div>

                <div>
                  <p className="mb-2 text-sm font-medium text-foreground">Priority recommendations</p>
                  {recommendations.slice(0, 2).map((rec) => (
                    <div key={rec.id} className="mb-2 rounded-lg border border-border bg-muted px-3 py-2">
                      <p className="m-0 text-sm font-medium text-foreground">{rec.title}</p>
                      <p className="m-0 text-xs text-muted-foreground">{rec.description}</p>
                    </div>
                  ))}
                </div>
              </div>
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
                {company.co_reviewer_count} co-reviewer{company.co_reviewer_count === 1 ? '' : 's'} on{' '}
                {company.name}. Use co-reviewer chat to stay aligned before you submit.
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
    }>
  >([]);

  const load = () => {
    if (!token) return;
    api
      .reviewerOutreaches(token, companyId)
      .then((d) => {
        const list = (d.outreaches as typeof outreaches).filter((o) => o.recipient_type === 'company_admin');
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
        <ul className="space-y-2">
          {outreaches.slice(0, 6).map((o) => (
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
            </li>
          ))}
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
          <p className="m-0 text-xs text-muted-foreground">No active company admin on file — still sendable to default admin.</p>
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

function MeetingRequestsPanel({ companyId, reportId }: { companyId: number; reportId?: number }) {
  const token = useReviewerToken();
  const [purpose, setPurpose] = useState('');
  const [saving, setSaving] = useState(false);
  const [notice, setNotice] = useState<{ kind: 'success' | 'error'; text: string } | null>(null);
  const [meetings, setMeetings] = useState<
    Array<{
      id: number;
      purpose: string;
      status: string;
      scheduled_at?: string | null;
      meeting_link?: string | null;
      admin_note?: string | null;
      duration_minutes?: number;
    }>
  >([]);

  const load = () => {
    if (!token) return;
    api
      .reviewerMeetingRequests(token, companyId)
      .then((d) => setMeetings(d.meeting_requests as typeof meetings))
      .catch(() => setMeetings([]));
  };

  useEffect(() => {
    load();
  }, [token, companyId]);

  const submit = async () => {
    if (!token || !purpose.trim()) return;
    setSaving(true);
    setNotice(null);
    try {
      await api.createReviewerMeetingRequest(token, companyId, {
        purpose: purpose.trim(),
        report_id: reportId,
        duration_minutes: 30,
        urgency: 'normal',
      });
      setPurpose('');
      setNotice({ kind: 'success', text: 'Meeting request submitted for company admin approval.' });
      load();
    } catch (err) {
      setNotice({
        kind: 'error',
        text: err instanceof Error ? err.message : 'Failed to submit meeting request',
      });
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="space-y-4">
      {meetings.length > 0 && (
        <ul className="space-y-2">
          {meetings.slice(0, 8).map((m) => (
            <li key={m.id} className="rounded-md border border-border px-3 py-2 text-sm">
              <div className="flex flex-wrap items-center gap-2">
                <Badge
                  variant={
                    m.status === 'pending_admin'
                      ? 'info'
                      : m.status === 'declined'
                        ? 'error'
                        : m.status === 'scheduled' || m.status === 'approved'
                          ? 'success'
                          : 'neutral'
                  }
                >
                  {m.status}
                </Badge>
                {m.duration_minutes ? (
                  <span className="text-xs text-muted-foreground">{m.duration_minutes} min</span>
                ) : null}
              </div>
              <p className="mt-1 m-0 text-sm">{m.purpose}</p>
              {m.scheduled_at && (
                <p className="mt-1 m-0 text-xs text-muted-foreground">
                  Scheduled: {new Date(m.scheduled_at).toLocaleString()}
                </p>
              )}
              {m.meeting_link && (
                <a
                  className="mt-1 inline-block text-xs text-primary hover:underline"
                  href={m.meeting_link}
                  target="_blank"
                  rel="noreferrer"
                >
                  Join link
                </a>
              )}
              {m.admin_note && <p className="mt-1 m-0 text-xs text-muted-foreground">Note: {m.admin_note}</p>}
            </li>
          ))}
        </ul>
      )}

      <div className="space-y-3 border-t border-border pt-3">
        <Textarea
          label="Purpose"
          rows={3}
          value={purpose}
          onChange={(e) => setPurpose(e.target.value)}
          placeholder="Purpose, desired roles, and evidence gap to resolve…"
        />
        <Button size="sm" loading={saving} disabled={!purpose.trim()} onClick={submit}>
          Request meeting
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
