import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom';
import { Check, ChevronRight, Circle, FileText, MessageSquare } from 'lucide-react';
import { api, type ReviewerReportWorkspacePayload } from '../../../lib/api';
import { useAuth, useReviewerToken } from '../../../lib/auth';
import { Badge, Button, Card, ConfirmDialog, EmptyState, PageHeader, Skeleton, StatCard, Textarea } from '../../../components/ui';
import { AnimatedNumber } from '../../../components/motion';
import { cn } from '../../../lib/cn';
import { ReviewerAnnotationRail } from './ReviewerAnnotationRail';
import { ReviewerChatDrawer } from './ReviewerChatDrawer';
import { ReviewerEmployeeProfileCard } from './ReviewerEmployeeProfileCard';
import { ReviewerPdfDrawer } from './ReviewerPdfDrawer';
import { ReviewerSectionContent } from './ReviewerSectionContent';
import { ReviewerSectionEditorPanel } from './ReviewerSectionEditorPanel';
import { ReviewerSharedFindingsPanel } from './ReviewerSharedFindingsPanel';
import { ReviewerStructuredFindingsPanel } from './ReviewerStructuredFindingsPanel';
import { ReviewerTranscriptPanel } from './ReviewerTranscriptPanel';
import { EvidenceAskBubble } from './EvidenceAskBubble';
import { ReviewDiscussionThreadList } from './ReviewDiscussionThreadList';
import { coReviewerActivityLabel, coReviewerActivityVariant } from './coReviewerActivity';
import {
  REPORT_SECTIONS,
  WORKSPACE_STEPS,
  parseReportSection,
  parseWorkspaceStep,
  type ReportSectionKey,
  type WorkspaceStepId,
} from './workspaceSteps';

function stepIndex(step: WorkspaceStepId) {
  return WORKSPACE_STEPS.findIndex((s) => s.id === step);
}

function sectionsComplete(states: { section_key: string; status: string }[]) {
  return REPORT_SECTIONS.every((key) => {
    const status = states.find((s) => s.section_key === key)?.status || 'pending';
    return status === 'approved' || status === 'needs_info';
  });
}

export function ReviewerReportWorkspace() {
  const { companyId, reportId } = useParams();
  const navigate = useNavigate();
  const token = useReviewerToken();
  const { session } = useAuth();
  const currentReviewerUserId =
    session?.portal === 'reviewer' ? session.user.id : null;
  const [searchParams, setSearchParams] = useSearchParams();

  const activeStep = parseWorkspaceStep(searchParams.get('step'));
  const activeSection = parseReportSection(searchParams.get('section'));

  const [workspace, setWorkspace] = useState<ReviewerReportWorkspacePayload | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');
  const [commentBody, setCommentBody] = useState('');
  const [activeConversationIndex, setActiveConversationIndex] = useState(0);
  const [highlightedMessageId, setHighlightedMessageId] = useState<number | null>(null);
  const [pdfOpen, setPdfOpen] = useState(false);
  const [chatOpen, setChatOpen] = useState(false);
  const [chatUnread, setChatUnread] = useState(false);
  const [chatUnreadCount, setChatUnreadCount] = useState(0);
  const lastSeenChatMessageId = useRef<number | null>(null);
  const lastSyncAt = useRef<string | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [sendingFollowup, setSendingFollowup] = useState(false);
  const [confirmSubmitOpen, setConfirmSubmitOpen] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const noteSeeded = useRef(false);
  const [visited, setVisited] = useState<Set<WorkspaceStepId>>(() => new Set<WorkspaceStepId>(['context']));

  useEffect(() => {
    setVisited((prev) => (prev.has(activeStep) ? prev : new Set(prev).add(activeStep)));
  }, [activeStep]);

  const setStep = (step: WorkspaceStepId) => {
    const next = new URLSearchParams(searchParams);
    next.set('step', step);
    setSearchParams(next, { replace: true });
  };

  const setSection = (section: ReportSectionKey) => {
    const next = new URLSearchParams(searchParams);
    next.set('section', section);
    if (activeStep !== 'sections') next.set('step', 'sections');
    setSearchParams(next, { replace: true });
  };

  const load = useCallback(async () => {
    if (!token || !companyId || !reportId) return;
    const data = await api.reviewerReportWorkspace(token, Number(companyId), Number(reportId));
    setWorkspace(data);
    // Seed the note only once, so the 15s poll never clobbers in-progress edits.
    if (!noteSeeded.current) {
      setNote(data.review.overall_note || '');
      noteSeeded.current = true;
    }
  }, [token, companyId, reportId, setNote]);

  useEffect(() => {
    if (!token || !companyId || !reportId) return;
    setLoading(true);
    setError('');
    load()
      .catch((e) => setError(e instanceof Error ? e.message : 'Failed to load workspace'))
      .finally(() => setLoading(false));
  }, [token, companyId, reportId, load]);

  useEffect(() => {
    if (searchParams.get('chat') === '1') {
      setChatOpen(true);
    }
    const anchor = searchParams.get('anchor');
    if (anchor?.startsWith('message:')) {
      const messageId = Number(anchor.split(':')[1]);
      if (!Number.isNaN(messageId)) {
        setHighlightedMessageId(messageId);
        setStep('evidence');
      }
    }
  }, [searchParams]);

  useEffect(() => {
    if (!token || !companyId) return;
    const pollChat = () => {
      api
        .reviewerChatMessages(token, Number(companyId))
        .then((data) => {
          const unseen = data.messages.filter(
            (m) =>
              !m.mine &&
              (lastSeenChatMessageId.current == null || m.id > lastSeenChatMessageId.current)
          );
          if (!chatOpen && unseen.length > 0) {
            setChatUnread(true);
            setChatUnreadCount(unseen.length);
          }
        })
        .catch(() => {});
    };
    pollChat();
    const interval = setInterval(pollChat, 15000);
    return () => clearInterval(interval);
  }, [token, companyId, chatOpen]);

  const handleChatOpenChange = (open: boolean) => {
    setChatOpen(open);
    if (open) {
      setChatUnread(false);
      setChatUnreadCount(0);
    }
  };

  const handleChatMessagesLoaded = (latestId: number | null) => {
    if (chatOpen && latestId != null) {
      lastSeenChatMessageId.current = latestId;
      setChatUnread(false);
      setChatUnreadCount(0);
    } else if (lastSeenChatMessageId.current == null && latestId != null) {
      lastSeenChatMessageId.current = latestId;
    }
  };

  const syncCollaboration = useCallback(async () => {
    if (!token || !companyId || !reportId) return;
    const since = lastSyncAt.current ?? new Date(Date.now() - 60_000).toISOString();
    try {
      const [sync, discussionsRes] = await Promise.all([
        api.reviewerReviewSync(token, Number(companyId), Number(reportId), since),
        api.reviewerDiscussions(token, Number(companyId), Number(reportId)),
      ]);
      lastSyncAt.current = sync.synced_at;
      setWorkspace((prev) => {
        if (!prev) return prev;
        const coReviews = prev.co_reviewer_reviews.map((cr) => {
          const syncReview = sync.reviews.find((r) => r.reviewer_user_id === cr.reviewer_user_id);
          const remoteComments = sync.comments.filter((c) => c.reviewer_user_id === cr.reviewer_user_id);
          const remoteStates = sync.section_states.filter((s) => s.reviewer_user_id === cr.reviewer_user_id);
          if (!syncReview && remoteComments.length === 0 && remoteStates.length === 0) return cr;
          const commentsByKey = new Map(cr.comments.map((c) => [`${c.section_key}:${c.body}`, c]));
          for (const c of remoteComments) {
            commentsByKey.set(`${c.section_key}:${c.body}`, { section_key: c.section_key, body: c.body });
          }
          const statesByKey = new Map(cr.section_states.map((s) => [s.section_key, s]));
          for (const s of remoteStates) {
            statesByKey.set(s.section_key, { section_key: s.section_key, status: s.status });
          }
          return {
            ...cr,
            status: syncReview?.status ?? cr.status,
            comments: Array.from(commentsByKey.values()),
            section_states: Array.from(statesByKey.values()),
          };
        });
        return { ...prev, co_reviewer_reviews: coReviews, discussions: discussionsRes.discussions };
      });
    } catch {
      // ignore background sync errors
    }
  }, [token, companyId, reportId]);

  useEffect(() => {
    if (!token || !companyId || !reportId) return;
    lastSyncAt.current = new Date().toISOString();
    const interval = setInterval(() => {
      void syncCollaboration();
    }, 15000);
    return () => clearInterval(interval);
  }, [token, companyId, reportId, syncCollaboration]);

  useEffect(() => {
    if (!token || !companyId || !reportId || !workspace?.report.storage_key) {
      setPreviewUrl(null);
      return;
    }
    let objectUrl: string | null = null;
    api
      .previewReviewerReport(token, Number(companyId), Number(reportId))
      .then((url) => {
        objectUrl = url;
        setPreviewUrl(url);
      })
      .catch(() => setPreviewUrl(null));
    return () => {
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [token, companyId, reportId, workspace?.report.storage_key]);

  const activeConversation = workspace?.conversations[activeConversationIndex] ?? null;
  const submitted = Boolean(workspace?.review.submitted_at);
  const snapshot = workspace?.report.report_snapshot ?? {};
  const readiness = snapshot.readiness as { score?: number } | undefined;
  const participation = snapshot.participation as Record<string, number> | undefined;

  const jumpToMessage = (messageId: number) => {
    setHighlightedMessageId(messageId);
    setStep('evidence');
  };

  const handleSectionStatus = async (status: string) => {
    if (!token || !companyId || !reportId) return;
    await api.updateSectionState(token, Number(companyId), Number(reportId), activeSection, status);
    await load();
  };

  const handleAddComment = async (e: FormEvent) => {
    e.preventDefault();
    if (!token || !companyId || !reportId || !commentBody.trim()) return;
    await api.addReviewComment(token, Number(companyId), Number(reportId), {
      section_key: activeSection,
      body: commentBody.trim(),
    });
    setCommentBody('');
    await load();
  };

  const handleUpdateComment = async (commentId: number, body: string) => {
    if (!token || !companyId || !reportId) return;
    await api.updateReviewComment(token, Number(companyId), Number(reportId), commentId, { body });
    await load();
  };

  const handleDeleteComment = async (commentId: number) => {
    if (!token || !companyId || !reportId) return;
    await api.deleteReviewComment(token, Number(companyId), Number(reportId), commentId);
    await load();
  };

  const handleResolveComment = async (commentId: number, resolved: boolean) => {
    if (!token || !companyId || !reportId) return;
    await api.updateReviewComment(token, Number(companyId), Number(reportId), commentId, { resolved });
    await load();
  };

  const handleReplyDiscussion = async (discussionId: number, body: string) => {
    if (!token || !companyId || !reportId) return;
    await api.replyReviewDiscussion(token, Number(companyId), Number(reportId), discussionId, body);
    await load();
  };

  const handleResolveDiscussion = async (discussionId: number) => {
    if (!token || !companyId || !reportId) return;
    await api.resolveReviewDiscussion(token, Number(companyId), Number(reportId), discussionId);
    await load();
  };

  const handleSaveNote = async () => {
    if (!token || !companyId || !reportId) return;
    await api.updateReviewerReportReview(token, Number(companyId), Number(reportId), { overall_note: note });
    await load();
  };

  const handleSubmit = async () => {
    if (!token || !companyId || !reportId) return;
    setSubmitting(true);
    try {
      await api.submitReviewerReportReview(token, Number(companyId), Number(reportId));
      await load();
      setConfirmSubmitOpen(false);
    } finally {
      setSubmitting(false);
    }
  };

  const handleFollowup = async (body: string) => {
    if (!token || !companyId || !activeConversation) return;
    setSendingFollowup(true);
    try {
      await api.sendReviewerFollowup(token, Number(companyId), activeConversation.employee_id, body);
      await load();
    } finally {
      setSendingFollowup(false);
    }
  };

  const coReviewers = useMemo(
    () =>
      (workspace?.co_reviewer_reviews ?? [])
        .filter((cr) => cr.reviewer_user_id != null)
        .map((cr) => ({
          reviewer_user_id: cr.reviewer_user_id as number,
          reviewer_name: cr.reviewer_name,
        })),
    [workspace?.co_reviewer_reviews]
  );

  const hasCoReviewers = coReviewers.length > 0;

  const handleAskReviewer = async (
    targetReviewerUserId: number,
    body: string,
    anchorType: 'message' | 'finding' | 'section',
    anchorId: string,
    messageId?: number,
    employeeId?: number,
    conversationId?: number
  ) => {
    if (!token || !companyId || !reportId) return;
    await api.createReviewDiscussion(token, Number(companyId), Number(reportId), {
      target_type: 'reviewer',
      target_reviewer_user_id: targetReviewerUserId,
      anchor_type: anchorType,
      anchor_id: anchorId,
      body,
      message_id: messageId,
      employee_id: employeeId,
      conversation_id: conversationId,
    });
    await load();
  };

  const handleAskEmployee = async (
    body: string,
    anchorType: 'message' | 'finding' | 'section',
    anchorId: string,
    messageId?: number,
    employeeId?: number,
    conversationId?: number
  ) => {
    if (!token || !companyId || !reportId) return;
    if (anchorType === 'section') {
      await api.createReviewDiscussion(token, Number(companyId), Number(reportId), {
        target_type: 'employee',
        employee_id: employeeId,
        conversation_id: conversationId,
        anchor_type: 'section',
        anchor_id: anchorId,
        body,
      });
    } else if (!employeeId || !conversationId) {
      return;
    } else {
      await api.createReviewDiscussion(token, Number(companyId), Number(reportId), {
        target_type: 'employee',
        employee_id: employeeId,
        conversation_id: conversationId,
        anchor_type: anchorType,
        anchor_id: anchorId,
        body,
        message_id: messageId,
      });
    }
    await load();
  };

  const stepComplete = useMemo(() => {
    if (!workspace) return {} as Record<WorkspaceStepId, boolean>;
    const states = workspace.review.section_states;
    return {
      // Exploratory steps are "done" once the reviewer has actually opened them,
      // not merely because data exists — otherwise every step shows pre-checked.
      context: visited.has('context'),
      evidence: visited.has('evidence'),
      synthesis: visited.has('synthesis'),
      sections: sectionsComplete(states),
      collaborate:
        !hasCoReviewers ||
        workspace.co_reviewer_reviews.some(
          (cr) => cr.comments.length > 0 || (cr.activity && cr.activity !== 'not_started')
        ),
      submit: submitted,
    } satisfies Record<WorkspaceStepId, boolean>;
  }, [workspace, submitted, visited, hasCoReviewers]);

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton variant="text" />
        <div className="grid min-h-[480px] grid-cols-1 gap-4 lg:grid-cols-[240px_minmax(0,1fr)_360px]">
          <Skeleton variant="card" className="hidden min-h-[400px] lg:block" />
          <Skeleton variant="card" className="min-h-[400px]" />
          <Skeleton variant="card" className="hidden min-h-[400px] lg:block" />
        </div>
      </div>
    );
  }

  if (!workspace) {
    return <p className="text-destructive">{error || 'Workspace not found'}</p>;
  }

  const currentStepIndex = stepIndex(activeStep);
  // The annotation rail (section status + comments) only earns its column on the
  // sections step; elsewhere the main column carries the content and can breathe.
  const showRail = activeStep === 'sections';

  return (
    <div className="flex h-full min-h-0 flex-col overflow-hidden">
      <div className="shrink-0 border-b border-border bg-card/80 px-4 py-3 backdrop-blur-sm">
        <PageHeader
          className="mb-0"
          title={`${workspace.company.name} · v${workspace.report.version}`}
          description={`Step ${currentStepIndex + 1} of ${WORKSPACE_STEPS.length} — ${WORKSPACE_STEPS[currentStepIndex]?.label}`}
          breadcrumbs={[
            { label: 'Dashboard', href: '/reviewer/dashboard' },
            { label: workspace.company.name, href: `/reviewer/companies/${companyId}` },
            { label: 'Report workspace' },
          ]}
          actions={
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant={submitted ? 'success' : 'warning'} className="hidden sm:inline-flex">
                {workspace.review.status}
              </Badge>
              {hasCoReviewers && (
                <Button
                  variant="secondary"
                  size="sm"
                  onClick={() => handleChatOpenChange(true)}
                  icon={<MessageSquare className="h-4 w-4" aria-hidden />}
                  className="relative"
                  aria-label={chatUnread ? `Open co-reviewer chat, ${chatUnreadCount} unread` : 'Open co-reviewer chat'}
                >
                  <span className="hidden sm:inline">Chat</span>
                  {chatUnread && chatUnreadCount > 0 ? (
                    <span className="absolute -right-1 -top-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-accent px-1 text-xs text-accent-foreground">
                      {chatUnreadCount > 9 ? '9+' : chatUnreadCount}
                    </span>
                  ) : chatUnread ? (
                    <span className="absolute -right-1 -top-1 h-2.5 w-2.5 rounded-full bg-accent" />
                  ) : null}
                </Button>
              )}
              <Button
                variant="secondary"
                size="sm"
                onClick={() => setPdfOpen(true)}
                icon={<FileText className="h-4 w-4" />}
              >
                <span className="hidden sm:inline">Client PDF</span>
              </Button>
              {!submitted && activeStep === 'submit' && (
                <Button size="sm" onClick={() => setConfirmSubmitOpen(true)}>
                  Submit
                </Button>
              )}
            </div>
          }
        />
      </div>

      <div
        className={cn(
          'grid min-h-0 flex-1 grid-cols-1',
          showRail ? 'lg:grid-cols-[240px_minmax(0,1fr)_360px]' : 'lg:grid-cols-[240px_minmax(0,1fr)]'
        )}
      >
        <nav className="hidden shrink-0 overflow-y-auto border-r border-border bg-muted/20 p-3 lg:block">
          <ol className="m-0 list-none space-y-1 p-0">
            {WORKSPACE_STEPS.map((step, index) => {
              const done = stepComplete[step.id];
              const active = step.id === activeStep;
              return (
                <li key={step.id}>
                  <button
                    type="button"
                    onClick={() => setStep(step.id)}
                    className={cn(
                      'flex w-full items-start gap-2 rounded-lg px-3 py-2.5 text-left transition-colors',
                      active ? 'bg-accent-muted text-accent' : 'text-muted-foreground hover:bg-muted hover:text-foreground'
                    )}
                  >
                    <span
                      className={cn(
                        'mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-xs',
                        done ? 'bg-status-successBg text-status-success' : 'bg-muted text-muted-foreground'
                      )}
                    >
                      {done ? <Check className="h-3 w-3" /> : index + 1}
                    </span>
                    <span>
                      <span className="block text-sm font-medium">{step.label}</span>
                      <span className="block text-xs opacity-80">{step.description}</span>
                    </span>
                  </button>
                </li>
              );
            })}
          </ol>
        </nav>

        <main className="min-h-0 overflow-y-auto p-4">
          <div className="mb-4 flex gap-2 overflow-x-auto lg:hidden">
            {WORKSPACE_STEPS.map((step) => (
              <button
                key={step.id}
                type="button"
                onClick={() => setStep(step.id)}
                className={cn(
                  'shrink-0 rounded-full px-3 py-1.5 text-xs font-medium',
                  step.id === activeStep ? 'bg-accent text-accent-foreground' : 'bg-muted text-muted-foreground'
                )}
              >
                {step.label}
              </button>
            ))}
          </div>

          {activeStep === 'context' && (
            <div className="space-y-4">
              <Card title="Engagement context">
                <div className="grid gap-4 md:grid-cols-3">
                  <StatCard label="Readiness" value={<AnimatedNumber value={readiness?.score ?? 0} suffix="%" />} />
                  <StatCard label="Completed" value={<AnimatedNumber value={participation?.completed ?? workspace.conversations.filter((c) => c.status === 'completed').length} />} />
                  <StatCard label="Invited" value={<AnimatedNumber value={participation?.invited ?? workspace.conversations.length} />} />
                </div>
                {workspace.report.generated_at && (
                  <p className="mt-4 text-sm text-muted-foreground">
                    Generated {new Date(workspace.report.generated_at).toLocaleString()}
                  </p>
                )}
              </Card>
              <Card title="Interview roster">
                {workspace.conversations.length === 0 ? (
                  <EmptyState
                    title="No interviews yet — docs-first baseline"
                    description="This report was built from documents. Source evidence and agent synthesis steps stay empty until employees complete discovery. Review Documents, Intelligence, Catalog matches, and Agentic ideas from the company overview."
                    action={{
                      label: 'Open company overview',
                      onClick: () => navigate(`/reviewer/companies/${companyId}`),
                    }}
                  />
                ) : (
                <ul className="m-0 list-none space-y-2 p-0">
                  {workspace.conversations.map((c, index) => (
                    <li key={c.id}>
                      <button
                        type="button"
                        onClick={() => {
                          setActiveConversationIndex(index);
                          setStep('evidence');
                        }}
                        className="flex w-full items-center justify-between rounded-lg border border-border px-3 py-2 text-left hover:bg-muted/50"
                      >
                        <span>
                          <span className="block text-sm font-medium">{c.employee_name || `Employee #${c.employee_id}`}</span>
                          <span className="text-xs text-muted-foreground">
                            {c.department || '—'} · {c.question_count} questions
                          </span>
                        </span>
                        <span className="flex items-center gap-2">
                          <Badge variant={c.status === 'completed' ? 'success' : 'info'}>{c.status}</Badge>
                          <ChevronRight className="h-4 w-4 text-muted-foreground" />
                        </span>
                      </button>
                    </li>
                  ))}
                </ul>
                )}
              </Card>
            </div>
          )}

          {activeStep === 'evidence' && !activeConversation && (
            <EmptyState
              title="No interview transcripts yet"
              description="Source evidence shows employee profiles and WhatsApp/web discovery transcripts. This company is still on a document baseline — open Documents or Intelligence from the company page, or wait for interviews to complete."
              action={{
                label: 'Browse documents',
                onClick: () => navigate(`/reviewer/companies/${companyId}/documents`),
              }}
            />
          )}

          {activeStep === 'evidence' && activeConversation && token && (            <div className="space-y-4">
              <ReviewerEmployeeProfileCard
                employeeName={activeConversation.employee_name}
                department={activeConversation.department}
                profile={activeConversation.discovery_state.profile}
              />
              {workspace.conversations.length > 1 && (
                <div className="flex flex-wrap gap-2">
                  {workspace.conversations.map((c, index) => (
                    <button
                      key={c.id}
                      type="button"
                      onClick={() => setActiveConversationIndex(index)}
                      className={cn(
                        'rounded-full px-3 py-1 text-xs font-medium',
                        index === activeConversationIndex ? 'bg-accent text-accent-foreground' : 'bg-muted'
                      )}
                    >
                      {c.employee_name || `Employee ${c.employee_id}`}
                    </button>
                  ))}
                </div>
              )}
              <ReviewerTranscriptPanel
                companyId={Number(companyId)}
                conversationId={activeConversation.id}
                employeeId={activeConversation.employee_id}
                employeeName={activeConversation.employee_name}
                messages={activeConversation.messages}
                discoveryState={activeConversation.discovery_state}
                discoveryProvenance={activeConversation.discovery_provenance}
                mediaAttachments={activeConversation.media_attachments}
                token={token}
                highlightedMessageId={highlightedMessageId}
                onHighlightMessage={setHighlightedMessageId}
                onSendFollowup={handleFollowup}
                sendingFollowup={sendingFollowup}
                discussions={workspace.discussions}
                coReviewers={coReviewers}
                currentReviewerUserId={currentReviewerUserId}
                onAskReviewer={(targetId, body, anchorType, anchorId, messageId) =>
                  handleAskReviewer(
                    targetId,
                    body,
                    anchorType,
                    anchorId,
                    messageId,
                    activeConversation.employee_id,
                    activeConversation.id
                  )
                }
                onAskEmployee={(body, messageId) =>
                  handleAskEmployee(
                    body,
                    'message',
                    String(messageId),
                    messageId,
                    activeConversation.employee_id,
                    activeConversation.id
                  )
                }
                onReplyDiscussion={handleReplyDiscussion}
                onResolveDiscussion={handleResolveDiscussion}
                readOnly={submitted}
              />
            </div>
          )}

          {activeStep === 'synthesis' && !activeConversation && (
            <EmptyState
              title="No agent synthesis from interviews"
              description="Shared findings and conversation reasoning appear after discovery interviews. For this docs-first report, use Report sections, Catalog (endorse matched tools), and Agentic ideas on the company overview."
              action={{
                label: 'Open catalog matches',
                onClick: () => navigate(`/reviewer/companies/${companyId}/catalog`),
              }}
            />
          )}

          {activeStep === 'synthesis' && activeConversation && (
            <div className="space-y-4">
              {workspace.conversations.length > 1 && (
                <div className="flex flex-wrap gap-2">
                  {workspace.conversations.map((c, index) => (
                    <button
                      key={c.id}
                      type="button"
                      onClick={() => setActiveConversationIndex(index)}
                      className={cn(
                        'rounded-full px-3 py-1 text-xs font-medium',
                        index === activeConversationIndex ? 'bg-accent text-accent-foreground' : 'bg-muted'
                      )}
                    >
                      {c.employee_name || `Employee ${c.employee_id}`}
                    </button>
                  ))}
                </div>
              )}
              <ReviewerSharedFindingsPanel
                findings={activeConversation.discovery_state.shared_findings}
                conversationSummary={activeConversation.discovery_state.conversation_summary}
                discussions={workspace.discussions}
                coReviewers={coReviewers}
                employeeId={activeConversation.employee_id}
                conversationId={activeConversation.id}
                currentReviewerUserId={currentReviewerUserId}
                onAskReviewer={(targetId, body, anchorId) =>
                  handleAskReviewer(
                    targetId,
                    body,
                    'finding',
                    anchorId,
                    undefined,
                    activeConversation.employee_id,
                    activeConversation.id
                  )
                }
                onAskEmployee={(body, anchorId) =>
                  handleAskEmployee(
                    body,
                    'finding',
                    anchorId,
                    undefined,
                    activeConversation.employee_id,
                    activeConversation.id
                  )
                }
                onReplyDiscussion={handleReplyDiscussion}
                onResolveDiscussion={handleResolveDiscussion}
                readOnly={submitted}
              />
              {token && (
                <ReviewerTranscriptPanel
                  companyId={Number(companyId)}
                  conversationId={activeConversation.id}
                  employeeId={activeConversation.employee_id}
                  employeeName={activeConversation.employee_name}
                  messages={activeConversation.messages}
                  discoveryState={activeConversation.discovery_state}
                  discoveryProvenance={activeConversation.discovery_provenance}
                  mediaAttachments={[]}
                  token={token}
                  highlightedMessageId={highlightedMessageId}
                  onHighlightMessage={setHighlightedMessageId}
                  discussions={workspace.discussions}
                  coReviewers={coReviewers}
                  currentReviewerUserId={currentReviewerUserId}
                  onAskReviewer={(targetId, body, anchorType, anchorId, messageId) =>
                    handleAskReviewer(
                      targetId,
                      body,
                      anchorType,
                      anchorId,
                      messageId,
                      activeConversation.employee_id,
                      activeConversation.id
                    )
                  }
                  onAskEmployee={(body, messageId) =>
                    handleAskEmployee(
                      body,
                      'message',
                      String(messageId),
                      messageId,
                      activeConversation.employee_id,
                      activeConversation.id
                    )
                  }
                  onReplyDiscussion={handleReplyDiscussion}
                  onResolveDiscussion={handleResolveDiscussion}
                  readOnly={submitted}
                />
              )}
            </div>
          )}

          {activeStep === 'sections' && (
            <div className="space-y-4">
              <Card
                title={activeSection.replace(/_/g, ' ')}
                action={
                  !submitted && (hasCoReviewers || activeConversation) ? (
                    <EvidenceAskBubble
                      anchorType="section"
                      anchorId={activeSection}
                      coReviewers={coReviewers}
                      employeeId={activeConversation?.employee_id}
                      conversationId={activeConversation?.id}
                      discussions={workspace.discussions}
                      onAskReviewer={(targetId, body) =>
                        handleAskReviewer(targetId, body, 'section', activeSection)
                      }
                      onAskEmployee={
                        activeConversation
                          ? (body) =>
                              handleAskEmployee(
                                body,
                                'section',
                                activeSection,
                                undefined,
                                activeConversation.employee_id,
                                activeConversation.id
                              )
                          : undefined
                      }
                    />
                  ) : undefined
                }
              >
                <p className="mb-4 text-sm text-muted-foreground">
                  Cross-check this section against agent findings and the employee transcript.
                </p>
                <ReviewerSectionContent
                  section={activeSection}
                  snapshot={snapshot}
                  onJumpToMessage={jumpToMessage}
                />
              </Card>
              <Card title="Section discussions">
                <ReviewDiscussionThreadList
                  discussions={workspace.discussions.filter(
                    (d) => d.anchor_type === 'section' && d.anchor_id === activeSection
                  )}
                  currentReviewerUserId={currentReviewerUserId}
                  onReply={handleReplyDiscussion}
                  onResolve={handleResolveDiscussion}
                  disabled={submitted}
                  emptyMessage="No questions on this section yet. Use + to ask a co-reviewer or employee."
                />
              </Card>
              {token && companyId && reportId && (
                <ReviewerSectionEditorPanel
                  token={token}
                  companyId={Number(companyId)}
                  reportId={Number(reportId)}
                  disabled={submitted}
                />
              )}
              <div className="flex justify-between">
                <Button variant="secondary" size="sm" onClick={() => setStep('synthesis')}>
                  Back to synthesis
                </Button>
                <Button variant="secondary" size="sm" onClick={() => setStep('collaborate')}>
                  Continue to collaborate
                </Button>
              </div>
            </div>
          )}

          {activeStep === 'collaborate' && (
            <div className="space-y-4">
              {hasCoReviewers ? (
                <Card title="Co-reviewer alignment">
                  <p className="text-sm text-muted-foreground">
                    Compare section comments in the right rail and use co-reviewer chat for real-time discussion — without leaving this workspace.
                  </p>
                  <Button className="mt-4" onClick={() => handleChatOpenChange(true)} icon={<MessageSquare className="h-4 w-4" />}>
                    Open co-reviewer chat
                  </Button>
                </Card>
              ) : (
                <Card title="Co-reviewer alignment">
                  <p className="text-sm text-muted-foreground">
                    You’re the only reviewer assigned to this company, so there’s nothing to align on here. If a
                    second reviewer is added, their progress and a chat channel will appear on this step.
                  </p>
                </Card>
              )}
              {workspace.co_reviewer_reviews.map((cr) => {
                const activity = cr.activity || cr.status;
                return (
                  <Card key={cr.reviewer_name} title={cr.reviewer_name}>
                    <p className="mb-2 text-sm">
                      <Badge variant={coReviewerActivityVariant(activity)}>{coReviewerActivityLabel(activity)}</Badge>
                    </p>
                    {cr.activity_detail && (
                      <p className="mb-2 text-xs text-muted-foreground">{cr.activity_detail}</p>
                    )}
                    {cr.comments.length === 0 ? (
                      <p className="text-sm text-muted-foreground">No section comments yet.</p>
                    ) : (
                      <ul className="space-y-2 text-sm">
                        {cr.comments.map((c, i) => (
                          <li key={i} className="rounded-lg border border-border p-3">
                            <span className="text-xs uppercase text-muted-foreground">{c.section_key.replace(/_/g, ' ')}</span>
                            <p className="m-0 mt-1">{c.body}</p>
                          </li>
                        ))}
                      </ul>
                    )}
                  </Card>
                );
              })}
            </div>
          )}

          {activeStep === 'submit' && (
            <div className="space-y-4">
              <Card title="Submit checklist">
                <ul className="space-y-2 text-sm">
                  {[
                    {
                      done: sectionsComplete(workspace.review.section_states),
                      label: 'All sections marked reviewed or needs clarification',
                    },
                    { done: !!workspace.review.overall_note, label: 'Overall conclusion saved' },
                    {
                      done: workspace.co_reviewer_reviews.every((cr) => cr.status === 'submitted'),
                      label: 'Co-reviewers submitted',
                    },
                  ].map((item) => (
                    <li key={item.label} className="flex items-center gap-2">
                      {item.done ? (
                        <Check className="h-4 w-4 shrink-0 text-status-success" />
                      ) : (
                        <Circle className="h-4 w-4 shrink-0 text-muted-foreground" />
                      )}
                      <span>{item.label}</span>
                    </li>
                  ))}
                </ul>
              </Card>
              <ReviewerStructuredFindingsPanel
                companyId={Number(companyId)}
                reportId={Number(reportId)}
                readOnly={submitted}
              />
              <Card title="Overall note">
                <Textarea rows={5} value={note} disabled={submitted} onChange={(e) => setNote(e.target.value)} />
                {!submitted && (
                  <Button variant="secondary" size="sm" className="mt-3" onClick={handleSaveNote}>
                    Save note
                  </Button>
                )}
              </Card>
              {!submitted && (
                <Button onClick={() => setConfirmSubmitOpen(true)}>Submit review</Button>
              )}
              {submitted && (
                <p className="text-sm text-status-success">Review submitted — platform team will be notified.</p>
              )}
            </div>
          )}
        </main>

        {showRail && (
          <div className="min-h-0 overflow-y-auto border-t border-border bg-muted/10 p-4 lg:border-l lg:border-t-0">
            <ReviewerAnnotationRail
              activeSection={activeSection}
              onSectionChange={setSection}
              sectionStates={workspace.review.section_states}
              sectionComments={workspace.review.comments}
              currentReviewerUserId={currentReviewerUserId}
              coReviewerReviews={workspace.co_reviewer_reviews}
              submitted={submitted}
              commentBody={commentBody}
              onCommentBodyChange={setCommentBody}
              onAddComment={handleAddComment}
              onUpdateComment={handleUpdateComment}
              onDeleteComment={handleDeleteComment}
              onResolveComment={handleResolveComment}
              onSectionStatusChange={handleSectionStatus}
              showSectionNav={activeStep === 'sections'}
              showChat={hasCoReviewers}
              onOpenChat={() => handleChatOpenChange(true)}
              chatUnread={chatUnread}
              chatUnreadCount={chatUnreadCount}
            />
          </div>
        )}
      </div>

      <ConfirmDialog
        open={confirmSubmitOpen}
        onClose={() => setConfirmSubmitOpen(false)}
        onConfirm={handleSubmit}
        title="Submit your review?"
        description="This hands your review to the platform team for approval. You can still view co-reviewer notes and the transcript afterwards, but your section decisions and note will be locked."
        confirmLabel="Submit review"
        variant="primary"
        loading={submitting}
      />

      <ReviewerPdfDrawer
        open={pdfOpen}
        onOpenChange={setPdfOpen}
        previewUrl={previewUrl}
        downloadUrl={previewUrl}
      />

      <ReviewerChatDrawer
        companyId={Number(companyId)}
        open={chatOpen}
        onOpenChange={handleChatOpenChange}
        coReviewerNames={workspace.co_reviewer_reviews.map((cr) => cr.reviewer_name)}
        onMessagesLoaded={handleChatMessagesLoaded}
      />

      <Link
        to={`/reviewer/companies/${companyId}`}
        className="shrink-0 border-t border-border px-4 py-2 text-sm font-medium text-accent hover:underline"
      >
        ← Back to company
      </Link>
    </div>
  );
}
