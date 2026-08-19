import { useState, type FormEvent } from 'react';
import { MessageSquare, Pencil, Trash2 } from 'lucide-react';
import type { ReviewCommentPayload } from '../../../lib/api';
import { Badge, Button, Card, Input, Select } from '../../../components/ui';
import { cn } from '../../../lib/cn';
import { coReviewerActivityLabel, coReviewerActivityVariant } from './coReviewerActivity';
import { REPORT_SECTIONS, SECTION_STATUS_OPTIONS, type ReportSectionKey } from './workspaceSteps';

type CoReviewerReview = {
  reviewer_name: string;
  status: string;
  activity?: string;
  activity_detail?: string;
  comments: { section_key: string; body: string }[];
};

export function ReviewerAnnotationRail({
  activeSection,
  onSectionChange,
  sectionStates,
  sectionComments,
  currentReviewerUserId,
  coReviewerReviews,
  submitted,
  commentBody,
  onCommentBodyChange,
  onAddComment,
  onUpdateComment,
  onDeleteComment,
  onResolveComment,
  onSectionStatusChange,
  showSectionNav,
  showStatus = true,
  showChat = true,
  onOpenChat,
  chatUnread,
  chatUnreadCount,
}: {
  activeSection: ReportSectionKey;
  onSectionChange: (section: ReportSectionKey) => void;
  sectionStates: { section_key: string; status: string }[];
  sectionComments: ReviewCommentPayload[];
  currentReviewerUserId: number | null;
  coReviewerReviews: CoReviewerReview[];
  submitted: boolean;
  commentBody: string;
  onCommentBodyChange: (value: string) => void;
  onAddComment: (e: FormEvent) => void;
  onUpdateComment: (commentId: number, body: string) => Promise<void>;
  onDeleteComment: (commentId: number) => Promise<void>;
  onResolveComment: (commentId: number, resolved: boolean) => Promise<void>;
  onSectionStatusChange: (status: string) => void;
  showSectionNav: boolean;
  showStatus?: boolean;
  showChat?: boolean;
  onOpenChat: () => void;
  chatUnread?: boolean;
  chatUnreadCount?: number;
}) {
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editBody, setEditBody] = useState('');
  const [busyId, setBusyId] = useState<number | null>(null);

  const filteredComments = sectionComments.filter((c) => c.section_key === activeSection);
  const currentStatus = sectionStates.find((s) => s.section_key === activeSection)?.status || 'pending';
  const suggestionsMode = currentStatus === 'needs_info';

  const startEdit = (comment: ReviewCommentPayload) => {
    setEditingId(comment.id);
    setEditBody(comment.body);
  };

  const saveEdit = async (commentId: number) => {
    if (!editBody.trim()) return;
    setBusyId(commentId);
    try {
      await onUpdateComment(commentId, editBody.trim());
      setEditingId(null);
      setEditBody('');
    } finally {
      setBusyId(null);
    }
  };

  const handleDelete = async (commentId: number) => {
    setBusyId(commentId);
    try {
      await onDeleteComment(commentId);
      if (editingId === commentId) setEditingId(null);
    } finally {
      setBusyId(null);
    }
  };

  const handleResolve = async (commentId: number, resolved: boolean) => {
    setBusyId(commentId);
    try {
      await onResolveComment(commentId, resolved);
    } finally {
      setBusyId(null);
    }
  };

  return (
    <aside className="flex h-full min-h-0 flex-col gap-4">
      {showSectionNav && (
        <Card padding={false} className="shrink-0 p-2">
          <p className="px-3 pb-2 pt-2 text-xs font-medium uppercase tracking-wide text-muted-foreground">
            Report sections
          </p>
          <ul className="m-0 list-none p-0">
            {REPORT_SECTIONS.map((key) => {
              const state = sectionStates.find((s) => s.section_key === key)?.status || 'pending';
              const openSuggestions = sectionComments.filter(
                (c) => c.section_key === key && !c.resolved
              ).length;
              return (
                <li key={key}>
                  <button
                    type="button"
                    onClick={() => onSectionChange(key)}
                    className={cn(
                      'w-full rounded-lg px-3 py-2 text-left text-sm transition-colors',
                      activeSection === key
                        ? 'bg-accent-muted font-medium text-accent'
                        : 'text-muted-foreground hover:bg-muted hover:text-foreground'
                    )}
                  >
                    <span className="flex items-center justify-between gap-2">
                      <span className="capitalize">{key.replace(/_/g, ' ')}</span>
                      {openSuggestions > 0 && state === 'needs_info' && (
                        <Badge variant="warning">{openSuggestions}</Badge>
                      )}
                    </span>
                    <span className="text-xs opacity-70">{state.replace(/_/g, ' ')}</span>
                  </button>
                </li>
              );
            })}
          </ul>
        </Card>
      )}

      <Card
        title={suggestionsMode ? 'Suggested changes' : 'Notes'}
        className="min-h-0 shrink-0"
      >
        {suggestionsMode && (
          <p className="mb-3 text-xs text-muted-foreground">
            Marked as needs clarification — comments here are change requests for the platform team on approval.
          </p>
        )}

        {!submitted && showSectionNav && showStatus && (
          <div className="mb-4">
            <Select
              label="Section status"
              value={currentStatus}
              onChange={(e) => onSectionStatusChange(e.target.value)}
              options={[...SECTION_STATUS_OPTIONS]}
            />
          </div>
        )}

        <ul className="mb-4 max-h-48 space-y-2 overflow-y-auto">
          {filteredComments.length === 0 ? (
            <li className="text-sm text-muted-foreground">
              {suggestionsMode ? 'No suggestions yet — add a comment describing the change needed.' : 'No comments on this section yet.'}
            </li>
          ) : (
            filteredComments.map((c) => {
              const isMine = currentReviewerUserId != null && c.reviewer_user_id === currentReviewerUserId;
              const isEditing = editingId === c.id;
              return (
                <li
                  key={c.id}
                  className={cn(
                    'rounded-lg border p-3 text-sm',
                    c.resolved ? 'border-border bg-muted/20 opacity-80' : 'border-border bg-muted/40'
                  )}
                >
                  <div className="mb-1 flex flex-wrap items-center gap-2">
                    <p className="m-0 text-xs text-muted-foreground">{c.reviewer_name}</p>
                    {c.resolved && <Badge variant="success">Resolved</Badge>}
                    {suggestionsMode && !c.resolved && <Badge variant="warning">Suggestion</Badge>}
                  </div>
                  {isEditing ? (
                    <div className="space-y-2">
                      <Input value={editBody} onChange={(e) => setEditBody(e.target.value)} />
                      <div className="flex gap-2">
                        <Button size="sm" loading={busyId === c.id} onClick={() => saveEdit(c.id)}>
                          Save
                        </Button>
                        <Button size="sm" variant="ghost" onClick={() => setEditingId(null)}>
                          Cancel
                        </Button>
                      </div>
                    </div>
                  ) : (
                    <p className="m-0 mt-1 text-foreground">{c.body}</p>
                  )}
                  {!submitted && isMine && !isEditing && (
                    <div className="mt-2 flex flex-wrap gap-1">
                      <Button size="sm" variant="ghost" icon={<Pencil className="h-3 w-3" aria-hidden />} onClick={() => startEdit(c)} aria-label="Edit comment">
                        Edit
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        loading={busyId === c.id}
                        onClick={() => handleResolve(c.id, !c.resolved)}
                      >
                        {c.resolved ? 'Reopen' : 'Resolve'}
                      </Button>
                      <Button
                        size="sm"
                        variant="ghost"
                        icon={<Trash2 className="h-3 w-3" aria-hidden />}
                        loading={busyId === c.id}
                        onClick={() => handleDelete(c.id)}
                        aria-label="Delete comment"
                      >
                        Delete
                      </Button>
                    </div>
                  )}
                </li>
              );
            })
          )}
        </ul>

        {!submitted && showSectionNav && (
          <form onSubmit={onAddComment} className="space-y-2">
            <Input
              value={commentBody}
              onChange={(e) => onCommentBodyChange(e.target.value)}
              placeholder={
                suggestionsMode
                  ? 'Describe the change needed for this section…'
                  : 'Add a comment on this section…'
              }
            />
            <Button type="submit" variant="secondary" size="sm" disabled={!commentBody.trim()}>
              {suggestionsMode ? 'Add suggestion' : 'Add comment'}
            </Button>
          </form>
        )}
      </Card>

      {coReviewerReviews.length > 0 && (
        <Card title="Co-reviewer progress" className="min-h-0 flex-1 overflow-y-auto">
          {coReviewerReviews.map((cr) => {
            const activity = cr.activity || cr.status;
            return (
              <div key={cr.reviewer_name} className="border-t border-border py-3 first:border-0 first:pt-0">
                <p className="m-0 text-sm font-medium">
                  {cr.reviewer_name}{' '}
                  <Badge variant={coReviewerActivityVariant(activity)}>{coReviewerActivityLabel(activity)}</Badge>
                </p>
                {cr.activity_detail && (
                  <p className="mt-1 text-xs text-muted-foreground">{cr.activity_detail}</p>
                )}
                {cr.comments.length > 0 ? (
                  <ul className="mt-2 space-y-1 text-sm text-muted-foreground">
                    {cr.comments.map((c, i) => (
                      <li key={i}>
                        <span className="capitalize">{c.section_key.replace(/_/g, ' ')}:</span> {c.body}
                      </li>
                    ))}
                  </ul>
                ) : activity === 'not_started' || activity === 'pending' ? (
                  <p className="mt-1 text-xs text-muted-foreground">No activity yet.</p>
                ) : null}
              </div>
            );
          })}
        </Card>
      )}

      {showChat && (
        <Button
          variant="secondary"
          className="relative w-full shrink-0"
          icon={<MessageSquare className="h-4 w-4" />}
          onClick={onOpenChat}
        >
          Co-reviewer chat
          {chatUnread && chatUnreadCount && chatUnreadCount > 0 ? (
            <span className="absolute right-3 top-1/2 flex h-5 min-w-5 -translate-y-1/2 items-center justify-center rounded-full bg-accent px-1.5 text-xs text-accent-foreground">
              {chatUnreadCount > 9 ? '9+' : chatUnreadCount}
            </span>
          ) : chatUnread ? (
            <span className="absolute right-3 top-1/2 h-2 w-2 -translate-y-1/2 rounded-full bg-accent" />
          ) : null}
        </Button>
      )}
    </aside>
  );
}
