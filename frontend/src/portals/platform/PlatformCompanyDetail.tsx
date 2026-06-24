import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ChatMessageList, type ChatMessageItem } from '../../components/motion';
import {
  api,
  type Company,
  type CompanyConversation,
  type CompanyConversationMessage,
  type DiscoveryProvenanceEntry,
  type MediaAttachment,
  type CompanyPattern,
  type CompanySignal,
  type IntelligenceSnapshot,
  type PlatformAuditLogEntry,
  type PlatformReport,
  type Recommendation,
  type TimelineEvent,
} from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import {
  PageHeader,
  Tabs,
  Card,
  Badge,
  DataTable,
  EmptyState,
  Button,
  Skeleton,
  StrengthBar,
  Timeline,
  ReadinessGauge,
  ParticipationSummary,
  DiscoveryProvenancePanel,
} from '../../components/ui';
import { PlatformCompanyReviewers } from './PlatformCompanyReviewers';
import { ConversationMediaCard, ConversationMediaList } from '../../components/ConversationMediaCard';

export function PlatformCompanyDetail() {
  const { id } = useParams();
  const companyId = Number(id);
  const token = usePlatformToken();
  const [company, setCompany] = useState<Company | null>(null);
  const [reports, setReports] = useState<PlatformReport[]>([]);
  const [conversations, setConversations] = useState<CompanyConversation[]>([]);
  const [selectedConversation, setSelectedConversation] = useState<CompanyConversation | null>(null);
  const [conversationMessages, setConversationMessages] = useState<CompanyConversationMessage[]>([]);
  const [conversationProvenance, setConversationProvenance] = useState<DiscoveryProvenanceEntry[]>([]);
  const [highlightedMessageId, setHighlightedMessageId] = useState<number | null>(null);
  const [conversationMedia, setConversationMedia] = useState<MediaAttachment[]>([]);
  const [conversationsLoading, setConversationsLoading] = useState(false);
  const [conversationDetailLoading, setConversationDetailLoading] = useState(false);
  const [conversationsError, setConversationsError] = useState('');
  const [auditLogs, setAuditLogs] = useState<PlatformAuditLogEntry[]>([]);
  const [auditPage, setAuditPage] = useState(1);
  const [auditTotal, setAuditTotal] = useState(0);
  const [intelligenceSubTab, setIntelligenceSubTab] = useState('snapshot');
  const [intelSnapshot, setIntelSnapshot] = useState<IntelligenceSnapshot | null>(null);
  const [intelScore, setIntelScore] = useState(0);
  const [intelBreakdown, setIntelBreakdown] = useState<Record<string, number>>({});
  const [intelSignals, setIntelSignals] = useState<CompanySignal[]>([]);
  const [intelPatterns, setIntelPatterns] = useState<CompanyPattern[]>([]);
  const [intelRecommendations, setIntelRecommendations] = useState<Recommendation[]>([]);
  const [intelTimeline, setIntelTimeline] = useState<TimelineEvent[]>([]);
  const [intelligenceLoading, setIntelligenceLoading] = useState(false);
  const [intelligenceError, setIntelligenceError] = useState('');
  const [tab, setTab] = useState('overview');
  const [loading, setLoading] = useState(true);
  const [approvingId, setApprovingId] = useState<number | null>(null);
  const [selectedReportId, setSelectedReportId] = useState<number | null>(null);
  const [reportPreviewUrl, setReportPreviewUrl] = useState<string | null>(null);
  const [actionError, setActionError] = useState('');

  const loadReports = () => {
    if (!token || !companyId) return Promise.resolve([]);
    return api
      .platformCompanyReports(token, companyId)
      .then((d) => {
        setReports(d.reports);
        return d.reports;
      })
      .catch(() => {
        setReports([]);
        return [];
      });
  };

  useEffect(() => {
    if (!token || !companyId) return;
    setLoading(true);
    Promise.all([api.platformCompany(token, companyId).then((d) => d.company), loadReports()])
      .then(([c]) => setCompany(c))
      .catch(() => setCompany(null))
      .finally(() => setLoading(false));
  }, [token, companyId]);

  useEffect(() => {
    if (!token || !companyId || tab !== 'audit') return;
    api
      .platformAuditLogs(token, { company_id: companyId, page: auditPage })
      .then((d) => {
        setAuditLogs(d.audit_logs);
        setAuditTotal(d.pagination.total);
      })
      .catch(() => setAuditLogs([]));
  }, [token, companyId, tab, auditPage]);

  useEffect(() => {
    if (!token || !companyId || tab !== 'conversations') return;
    setConversationsLoading(true);
    setConversationsError('');
    setSelectedConversation(null);
    setConversationMessages([]);
    setConversationMedia([]);
    api
      .platformCompanyConversations(token, companyId)
      .then((d) => setConversations(d.conversations))
      .catch((err) => {
        setConversations([]);
        setConversationsError(err instanceof Error ? err.message : 'Failed to load conversations');
      })
      .finally(() => setConversationsLoading(false));
  }, [token, companyId, tab]);

  useEffect(() => {
    if (!token || !companyId || tab !== 'intelligence') return;
    setIntelligenceLoading(true);
    setIntelligenceError('');

    const loaders: Record<string, () => Promise<void>> = {
      snapshot: () =>
        api.platformCompanyIntelligenceSnapshot(token, companyId).then((d) => {
          setIntelSnapshot(d.snapshot);
          setIntelScore(Math.round(d.report_readiness_score));
          setIntelBreakdown(d.report_readiness_breakdown as Record<string, number>);
        }),
      signals: () =>
        api.platformCompanyIntelligenceSignals(token, companyId).then((d) => setIntelSignals(d.signals)),
      patterns: () =>
        api.platformCompanyIntelligencePatterns(token, companyId).then((d) => setIntelPatterns(d.patterns)),
      recommendations: () =>
        api.platformCompanyIntelligenceRecommendations(token, companyId).then((d) =>
          setIntelRecommendations(d.recommendations)
        ),
      timeline: () =>
        api.platformCompanyIntelligenceTimeline(token, companyId).then((d) => setIntelTimeline(d.events)),
    };

    loaders[intelligenceSubTab]()
      .catch((err) => {
        setIntelligenceError(err instanceof Error ? err.message : 'Failed to load intelligence');
      })
      .finally(() => setIntelligenceLoading(false));
  }, [token, companyId, tab, intelligenceSubTab]);

  const loadConversationDetail = (conversation: CompanyConversation) => {
    if (!token) return;
    setSelectedConversation(conversation);
    setConversationDetailLoading(true);
    setConversationMessages([]);
    setConversationProvenance([]);
    setHighlightedMessageId(null);
    setConversationMedia([]);
    api
      .platformCompanyConversation(token, companyId, conversation.id)
      .then((d) => {
        setSelectedConversation(d.conversation);
        setConversationMessages(d.messages);
        setConversationProvenance(d.discovery_provenance || []);
        setConversationMedia(d.media_attachments || []);
      })
      .catch((err) => {
        setConversationsError(err instanceof Error ? err.message : 'Failed to load transcript');
      })
      .finally(() => setConversationDetailLoading(false));
  };

  const chatMessages: ChatMessageItem[] = conversationMessages.map((m) => ({
    id: m.id,
    direction: m.direction as 'inbound' | 'outbound',
    body: m.body,
    timestamp: m.created_at,
    meta:
      token && m.media_attachment ? (
        <ConversationMediaCard attachment={m.media_attachment} token={token} compact />
      ) : undefined,
  }));

  const approveReport = async (reportId: number) => {
    if (!token) return;
    setActionError('');
    setApprovingId(reportId);
    try {
      await api.approvePlatformReport(token, companyId, reportId);
      await loadReports();
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Approval failed');
    } finally {
      setApprovingId(null);
    }
  };

  const canApprove = (report: PlatformReport) =>
    report.status === 'ready' &&
    report.review_workflow_status !== 'platform_approved' &&
    report.review_workflow_status !== 'awaiting_reviewers' &&
    report.review_workflow_status !== 'in_review';

  const selectedReport = reports.find((r) => r.id === selectedReportId) ?? null;

  useEffect(() => {
    if (!token || !selectedReport || selectedReport.status !== 'ready') {
      setReportPreviewUrl(null);
      return;
    }

    let objectUrl: string | null = null;
    api
      .previewPlatformReport(token, companyId, selectedReport.id)
      .then((url) => {
        objectUrl = url;
        setReportPreviewUrl(url);
      })
      .catch(() => setReportPreviewUrl(null));

    return () => {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [token, companyId, selectedReport?.id, selectedReport?.status]);

  const auditTotalPages = Math.max(1, Math.ceil(auditTotal / 50));

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  if (!company) {
    return <EmptyState title="Company not found" description="This company may have been removed." />;
  }

  const name = company.display_name || company.name;

  return (
    <div className="space-y-6">
      <PageHeader
        title={name}
        description={company.slug}
        breadcrumbs={[
          { label: 'Companies', href: '/platform/companies' },
          { label: name },
        ]}
        actions={
          <Link to="/platform/companies">
            <Button variant="secondary">Back</Button>
          </Link>
        }
      />

      <Tabs
        tabs={[
          { value: 'overview', label: 'Overview' },
          { value: 'conversations', label: 'Conversations' },
          { value: 'intelligence', label: 'Intelligence' },
          { value: 'reports', label: 'Reports' },
          { value: 'reviewers', label: 'Reviewers' },
          { value: 'audit', label: 'Audit' },
        ]}
        value={tab}
        onChange={setTab}
      />

      {tab === 'overview' && (
        <div className="grid gap-4 md:grid-cols-3">
          <Card title="Readiness">
            <p className="m-0 text-3xl font-semibold text-text-primary">{Math.round(company.report_readiness_score)}%</p>
          </Card>
          <Card title="Subscription">
            <p className="m-0 text-sm text-text-primary">
              {company.subscription ? `${company.subscription.plan} · ${company.subscription.status}` : 'None'}
            </p>
          </Card>
          <Card title="Onboarding">
            <Badge variant={company.portal_onboarding_completed_at ? 'success' : 'warning'}>
              {company.portal_onboarding_completed_at ? 'Complete' : 'Pending'}
            </Badge>
          </Card>
        </div>
      )}

      {tab === 'conversations' && (
        <div className="space-y-6">
          {conversationsError && <p className="text-sm text-status-error">{conversationsError}</p>}
          <DataTable
            loading={conversationsLoading}
            columns={[
              {
                key: 'employee',
                header: 'Employee',
                render: (c) => c.employee_name || `Employee #${c.employee_id}`,
              },
              { key: 'department', header: 'Department', render: (c) => c.department || '—' },
              {
                key: 'status',
                header: 'Status',
                render: (c) => (
                  <Badge variant={c.status === 'completed' ? 'success' : 'info'}>{c.status}</Badge>
                ),
              },
              {
                key: 'questions',
                header: 'Questions',
                render: (c) => c.question_count ?? 0,
              },
              {
                key: 'last_activity',
                header: 'Last activity',
                render: (c) => (c.last_activity_at ? new Date(c.last_activity_at).toLocaleString() : '—'),
              },
            ]}
            rows={conversations}
            onRowClick={loadConversationDetail}
            emptyState={
              <EmptyState
                title="No conversations"
                description="Discovery sessions appear here once employees start interviews."
              />
            }
          />

          {selectedConversation && (
            <div className="grid gap-4 lg:grid-cols-2 lg:items-start">
              <Card
                title={`Transcript · ${selectedConversation.employee_name || `Employee #${selectedConversation.employee_id}`}`}
                className="min-h-0"
              >
                {conversationDetailLoading ? (
                  <Skeleton variant="card" />
                ) : chatMessages.length === 0 ? (
                  <EmptyState title="No messages yet" description="Messages appear once the interview starts." />
                ) : (
                  <ChatMessageList
                    messages={chatMessages}
                    className="max-h-[520px]"
                    highlightedMessageId={highlightedMessageId}
                  />
                )}
              </Card>

              <div className="space-y-4">
                {token && conversationMedia.length > 0 && (
                  <Card title="Shared media">
                    {conversationDetailLoading ? (
                      <Skeleton variant="card" />
                    ) : (
                      <ConversationMediaList attachments={conversationMedia} token={token} />
                    )}
                  </Card>
                )}

              <Card title="Discovery provenance">
                {conversationDetailLoading ? (
                  <Skeleton variant="card" />
                ) : (
                  <DiscoveryProvenancePanel
                    state={selectedConversation.discovery_state}
                    provenance={conversationProvenance}
                    selectedMessageId={highlightedMessageId}
                    onSelectMessage={setHighlightedMessageId}
                  />
                )}
              </Card>
              </div>
            </div>
          )}
        </div>
      )}

      {tab === 'intelligence' && (
        <div className="space-y-6">
          {intelligenceError && <p className="text-sm text-status-error">{intelligenceError}</p>}
          <Tabs
            tabs={[
              { value: 'snapshot', label: 'Snapshot' },
              { value: 'signals', label: 'Signals' },
              { value: 'patterns', label: 'Patterns' },
              { value: 'recommendations', label: 'Recommendations' },
              { value: 'timeline', label: 'Timeline' },
            ]}
            value={intelligenceSubTab}
            onChange={setIntelligenceSubTab}
          />

          {intelligenceLoading ? (
            <Skeleton variant="card" />
          ) : intelligenceSubTab === 'snapshot' && intelSnapshot ? (
            <div className="space-y-4">
              <div className="grid gap-4 lg:grid-cols-3">
                <Card title="Readiness" className="lg:col-span-1">
                  <ReadinessGauge score={intelScore} breakdown={intelBreakdown} />
                </Card>
                <Card title="Participation" className="lg:col-span-2">
                  <ParticipationSummary
                    participation={intelSnapshot.participation}
                    departmentCoverage={intelSnapshot.department_coverage}
                  />
                </Card>
              </div>
              <Card title="Top pain points">
                {intelSnapshot.top_pain_points.length === 0 ? (
                  <EmptyState title="No signals yet" />
                ) : (
                  <ul className="space-y-3">
                    {intelSnapshot.top_pain_points.map((s) => (
                      <li key={s.id} className="flex items-center justify-between gap-4">
                        <span className="text-sm text-text-primary">{s.label}</span>
                        <StrengthBar strength={s.strength} />
                      </li>
                    ))}
                  </ul>
                )}
              </Card>
            </div>
          ) : intelligenceSubTab === 'signals' ? (
            <DataTable
              columns={[
                { key: 'label', header: 'Signal' },
                {
                  key: 'strength',
                  header: 'Strength',
                  render: (s) => (
                    <div className="min-w-[120px]">
                      <StrengthBar strength={s.strength} />
                    </div>
                  ),
                },
                { key: 'departments', header: 'Departments', render: (s) => s.departments.join(', ') || '—' },
                { key: 'evidence', header: 'Evidence', render: (s) => s.evidence_count },
              ]}
              rows={intelSignals}
              emptyState={<EmptyState title="No signals" />}
            />
          ) : intelligenceSubTab === 'patterns' ? (
            <DataTable
              columns={[
                { key: 'title', header: 'Pattern' },
                { key: 'confidence', header: 'Confidence', render: (p) => `${Math.round(p.confidence * 100)}%` },
                { key: 'departments', header: 'Departments', render: (p) => p.departments.join(', ') || '—' },
              ]}
              rows={intelPatterns}
              emptyState={<EmptyState title="No patterns" />}
            />
          ) : intelligenceSubTab === 'recommendations' ? (
            <DataTable
              columns={[
                { key: 'title', header: 'Recommendation' },
                { key: 'priority', header: 'Priority', render: (r) => <Badge variant="info">{r.priority}</Badge> },
                {
                  key: 'description',
                  header: 'Description',
                  render: (r) => <span className="text-sm text-text-secondary">{r.description || '—'}</span>,
                },
              ]}
              rows={intelRecommendations}
              emptyState={<EmptyState title="No recommendations" />}
            />
          ) : intelligenceSubTab === 'timeline' ? (
            intelTimeline.length === 0 ? (
              <EmptyState title="No timeline events" />
            ) : (
              <Timeline
                events={intelTimeline.map((e) => ({
                  id: String(e.id),
                  title: e.title,
                  summary: e.summary || undefined,
                  occurredAt: e.occurred_at,
                }))}
              />
            )
          ) : (
            <EmptyState title="No intelligence data" />
          )}
        </div>
      )}

      {tab === 'reports' && (
        <>
          {actionError && <p className="text-sm text-status-error">{actionError}</p>}
          <DataTable
            columns={[
              { key: 'version', header: 'Version', render: (r) => `v${r.version}` },
              {
                key: 'status',
                header: 'Status',
                render: (r) => (
                  <Badge variant={r.status === 'ready' ? 'success' : r.status === 'failed' ? 'error' : 'info'}>
                    {r.status}
                  </Badge>
                ),
              },
              {
                key: 'review',
                header: 'Review',
                render: (r) => String(r.review_workflow_status || '—'),
              },
              {
                key: 'notes',
                header: 'Reviewer notes',
                render: (r) => {
                  const count =
                    (r.reviewer_feedback || []).reduce((sum, review) => sum + review.comments.length, 0) +
                    (r.reviewer_feedback || []).filter((review) => review.overall_note).length;
                  return count > 0 ? `${count} note${count === 1 ? '' : 's'}` : '—';
                },
              },
              {
                key: 'generated',
                header: 'Generated',
                render: (r) => (r.generated_at ? new Date(r.generated_at).toLocaleString() : '—'),
              },
              {
                key: 'actions',
                header: 'Actions',
                render: (r) =>
                  canApprove(r) ? (
                    <Button
                      size="sm"
                      loading={approvingId === r.id}
                      onClick={() => approveReport(r.id)}
                    >
                      Approve
                    </Button>
                  ) : r.review_workflow_status === 'platform_approved' ? (
                    <Badge variant="success">Approved</Badge>
                  ) : null,
              },
            ]}
            rows={reports}
            onRowClick={(r) => setSelectedReportId((current) => (current === r.id ? null : r.id))}
            emptyState={<EmptyState title="No reports" description="This company has not generated a report yet." />}
          />

          {selectedReport && (
            <div className="grid gap-4 lg:grid-cols-2">
              <Card title={`Reviewer feedback · v${selectedReport.version}`}>
                {(selectedReport.reviewer_feedback || []).length === 0 ? (
                  <p className="text-sm text-muted-foreground">No reviewer comments yet.</p>
                ) : (
                  <div className="space-y-4">
                    {selectedReport.reviewer_feedback!.map((review) => (
                      <div key={review.reviewer_name} className="rounded-lg border border-border p-3">
                        <p className="m-0 text-sm font-medium text-foreground">
                          {review.reviewer_name}{' '}
                          <Badge variant="neutral">{review.status}</Badge>
                        </p>
                        {review.overall_note && (
                          <p className="m-0 mt-2 text-sm text-muted-foreground">{review.overall_note}</p>
                        )}
                        {review.comments.length > 0 && (
                          <ul className="m-0 mt-2 list-none space-y-2 p-0">
                            {review.comments.map((comment) => (
                              <li key={comment.id} className="text-sm">
                                <span className="font-medium capitalize text-foreground">
                                  {comment.section_key.replace(/_/g, ' ')}:
                                </span>{' '}
                                <span className="text-muted-foreground">{comment.body}</span>
                              </li>
                            ))}
                          </ul>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </Card>

              {reportPreviewUrl && (
                <Card title="Report preview">
                  <iframe
                    src={reportPreviewUrl}
                    title="Report PDF preview"
                    className="h-[520px] w-full rounded-lg border border-border bg-muted/30"
                  />
                </Card>
              )}
            </div>
          )}
        </>
      )}

      {tab === 'reviewers' && (
        <PlatformCompanyReviewers companyId={companyId} companyName={name} embedded />
      )}

      {tab === 'audit' && (
        <div className="space-y-4">
          <DataTable
            columns={[
              { key: 'created_at', header: 'When', render: (r) => new Date(r.created_at).toLocaleString() },
              { key: 'actor', header: 'Actor' },
              {
                key: 'action',
                header: 'Action',
                render: (r) => <Badge variant="info">{r.action.replace(/_/g, ' ')}</Badge>,
              },
              { key: 'target', header: 'Target' },
              { key: 'ip', header: 'IP', render: (r) => r.ip || '—' },
            ]}
            rows={auditLogs}
            emptyState={<EmptyState title="No audit events" description="No platform actions recorded for this company yet." />}
          />
          {auditTotalPages > 1 && (
            <div className="flex items-center justify-end gap-2">
              <Button variant="secondary" size="sm" disabled={auditPage <= 1} onClick={() => setAuditPage((p) => p - 1)}>
                Previous
              </Button>
              <span className="text-sm text-text-secondary">
                Page {auditPage} of {auditTotalPages}
              </span>
              <Button
                variant="secondary"
                size="sm"
                disabled={auditPage >= auditTotalPages}
                onClick={() => setAuditPage((p) => p + 1)}
              >
                Next
              </Button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
