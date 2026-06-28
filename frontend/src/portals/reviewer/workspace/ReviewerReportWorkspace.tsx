import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { Check, ChevronRight, FileText, MessageSquare } from 'lucide-react';
import { api, type ReviewerReportWorkspacePayload } from '../../../lib/api';
import { useReviewerToken } from '../../../lib/auth';
import { Badge, Button, Card, Skeleton, StatCard, Textarea } from '../../../components/ui';
import { cn } from '../../../lib/cn';
import { ReviewerAnnotationRail } from './ReviewerAnnotationRail';
import { ReviewerChatDrawer } from './ReviewerChatDrawer';
import { ReviewerEmployeeProfileCard } from './ReviewerEmployeeProfileCard';
import { ReviewerPdfDrawer } from './ReviewerPdfDrawer';
import { ReviewerSectionContent } from './ReviewerSectionContent';
import { ReviewerSharedFindingsPanel } from './ReviewerSharedFindingsPanel';
import { ReviewerTranscriptPanel } from './ReviewerTranscriptPanel';
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
  const token = useReviewerToken();
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
  const lastSeenChatMessageId = useRef<number | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [sendingFollowup, setSendingFollowup] = useState(false);

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
    setNote(data.review.overall_note || '');
  }, [token, companyId, reportId, setNote, setWorkspace]);

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
          const latestId = data.messages.length > 0 ? data.messages[data.messages.length - 1].id : null;
          const hasUnread =
            latestId != null &&
            (lastSeenChatMessageId.current == null || latestId > lastSeenChatMessageId.current) &&
            data.messages.some((m) => !m.mine && m.id === latestId);
          if (!chatOpen && hasUnread) setChatUnread(true);
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
    }
  };

  const handleChatMessagesLoaded = (latestId: number | null) => {
    if (chatOpen && latestId != null) {
      lastSeenChatMessageId.current = latestId;
      setChatUnread(false);
    } else if (lastSeenChatMessageId.current == null && latestId != null) {
      lastSeenChatMessageId.current = latestId;
    }
  };

  useEffect(() => {
    const interval = setInterval(() => {
      void load();
    }, 15000);
    return () => clearInterval(interval);
  }, [load]);

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

  const handleSaveNote = async () => {
    if (!token || !companyId || !reportId) return;
    await api.updateReviewerReportReview(token, Number(companyId), Number(reportId), { overall_note: note });
    await load();
  };

  const handleSubmit = async () => {
    if (!token || !companyId || !reportId) return;
    if (!window.confirm('Submit your review? You can still view co-reviewer notes.')) return;
    await api.submitReviewerReportReview(token, Number(companyId), Number(reportId));
    await load();
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
    anchorType: 'message' | 'finding',
    anchorId: string,
    messageId?: number,
    employeeId?: number,
    conversationId?: number
  ) => {
    if (!token || !companyId || !reportId || !employeeId || !conversationId) return;
    await api.createReviewDiscussion(token, Number(companyId), Number(reportId), {
      target_type: 'employee',
      employee_id: employeeId,
      conversation_id: conversationId,
      anchor_type: anchorType,
      anchor_id: anchorId,
      body,
      message_id: messageId,
    });
    await load();
  };

  const stepComplete = useMemo(() => {
    if (!workspace) return {} as Record<WorkspaceStepId, boolean>;
    const states = workspace.review.section_states;
    return {
      context: true,
      evidence: workspace.conversations.length > 0,
      synthesis: workspace.conversations.some((c) => c.discovery_state.shared_findings.length > 0),
      sections: sectionsComplete(states),
      collaborate: workspace.co_reviewer_reviews.some(
        (cr) =>
          cr.comments.length > 0 ||
          (cr.activity && cr.activity !== 'not_started')
      ),
      submit: submitted,
    } satisfies Record<WorkspaceStepId, boolean>;
  }, [workspace, submitted]);

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  if (!workspace) {
    return <p className="text-destructive">{error || 'Workspace not found'}</p>;
  }

  const currentStepIndex = stepIndex(activeStep);

  return (
    <div className="flex h-full min-h-0 flex-col overflow-hidden">
      <header className="shrink-0 border-b border-border bg-card/80 px-4 py-3 backdrop-blur-sm">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="m-0 text-xs font-medium uppercase tracking-wide text-muted-foreground">Report review workspace</p>
            <h1 className="truncate text-lg font-semibold text-foreground">
              {workspace.company.name} · v{workspace.report.version}
            </h1>
            <p className="m-0 text-sm text-muted-foreground">
              Step {currentStepIndex + 1} of {WORKSPACE_STEPS.length} — {WORKSPACE_STEPS[currentStepIndex]?.label}
            </p>
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant={submitted ? 'success' : 'warning'}>{workspace.review.status}</Badge>
            <Button
              variant="secondary"
              size="sm"
              onClick={() => handleChatOpenChange(true)}
              icon={<MessageSquare className="h-4 w-4" />}
              className="relative"
            >
              Chat
              {chatUnread && <span className="absolute -right-1 -top-1 h-2.5 w-2.5 rounded-full bg-accent" />}
            </Button>
            <Button variant="secondary" size="sm" onClick={() => setPdfOpen(true)} icon={<FileText className="h-4 w-4" />}>
              Client PDF
            </Button>
            {!submitted && activeStep === 'submit' && (
              <Button size="sm" onClick={handleSubmit}>
                Submit review
              </Button>
            )}
          </div>
        </div>
      </header>

      <div className="grid min-h-0 flex-1 grid-cols-1 lg:grid-cols-[240px_minmax(0,1fr)_360px]">
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
                        done ? 'bg-emerald-100 text-emerald-700' : 'bg-muted text-muted-foreground'
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
                  <StatCard label="Readiness" value={`${readiness?.score ?? 0}%`} />
                  <StatCard label="Completed" value={participation?.completed ?? workspace.conversations.filter((c) => c.status === 'completed').length} />
                  <StatCard label="Invited" value={participation?.invited ?? workspace.conversations.length} />
                </div>
                {workspace.report.generated_at && (
                  <p className="mt-4 text-sm text-muted-foreground">
                    Generated {new Date(workspace.report.generated_at).toLocaleString()}
                  </p>
                )}
              </Card>
              <Card title="Interview roster">
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
              </Card>
            </div>
          )}

          {activeStep === 'evidence' && activeConversation && token && (
            <div className="space-y-4">
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
              />
            </div>
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
                />
              )}
            </div>
          )}

          {activeStep === 'sections' && (
            <div className="space-y-4">
              <Card title={activeSection.replace(/_/g, ' ')}>
                <p className="mb-4 text-sm text-muted-foreground">
                  Cross-check this section against agent findings and the employee transcript.
                </p>
                <ReviewerSectionContent
                  section={activeSection}
                  snapshot={snapshot}
                  onJumpToMessage={jumpToMessage}
                />
              </Card>
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
              <Card title="Co-reviewer alignment">
                <p className="text-sm text-muted-foreground">
                  Compare section comments in the right rail and use co-reviewer chat for real-time discussion — without leaving this workspace.
                </p>
                <Button className="mt-4" onClick={() => handleChatOpenChange(true)} icon={<MessageSquare className="h-4 w-4" />}>
                  Open co-reviewer chat
                </Button>
              </Card>
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
                  <li>{sectionsComplete(workspace.review.section_states) ? '✓' : '○'} All sections marked reviewed or needs clarification</li>
                  <li>{workspace.review.overall_note ? '✓' : '○'} Overall note saved (optional but recommended)</li>
                  <li>{workspace.co_reviewer_reviews.every((cr) => cr.status === 'submitted') ? '✓' : '○'} Co-reviewers submitted</li>
                </ul>
              </Card>
              <Card title="Overall note">
                <Textarea rows={5} value={note} disabled={submitted} onChange={(e) => setNote(e.target.value)} />
                {!submitted && (
                  <Button variant="secondary" size="sm" className="mt-3" onClick={handleSaveNote}>
                    Save note
                  </Button>
                )}
              </Card>
              {!submitted && (
                <Button onClick={handleSubmit}>Submit review</Button>
              )}
              {submitted && (
                <p className="text-sm text-emerald-700">Review submitted — platform team will be notified.</p>
              )}
            </div>
          )}
        </main>

        <div className="hidden min-h-0 overflow-y-auto border-l border-border bg-muted/10 p-4 lg:block">
          <ReviewerAnnotationRail
            activeSection={activeSection}
            onSectionChange={setSection}
            sectionStates={workspace.review.section_states}
            sectionComments={workspace.review.comments}
            coReviewerReviews={workspace.co_reviewer_reviews}
            submitted={submitted}
            commentBody={commentBody}
            onCommentBodyChange={setCommentBody}
            onAddComment={handleAddComment}
            onSectionStatusChange={handleSectionStatus}
            showSectionNav={activeStep === 'sections' || activeStep === 'collaborate' || activeStep === 'submit'}
            onOpenChat={() => handleChatOpenChange(true)}
            chatUnread={chatUnread}
          />
        </div>
      </div>

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
