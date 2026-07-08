import type { FormEvent } from 'react';
import { MessageSquare } from 'lucide-react';
import { Badge, Button, Card, Input, Select } from '../../../components/ui';
import { cn } from '../../../lib/cn';
import { coReviewerActivityLabel, coReviewerActivityVariant } from './coReviewerActivity';
import { REPORT_SECTIONS, SECTION_STATUS_OPTIONS, type ReportSectionKey } from './workspaceSteps';

type ReviewComment = {
  id: number;
  section_key: string;
  body: string;
  reviewer_name: string;
};

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
  coReviewerReviews,
  submitted,
  commentBody,
  onCommentBodyChange,
  onAddComment,
  onSectionStatusChange,
  showSectionNav,
  showChat = true,
  onOpenChat,
  chatUnread,
}: {
  activeSection: ReportSectionKey;
  onSectionChange: (section: ReportSectionKey) => void;
  sectionStates: { section_key: string; status: string }[];
  sectionComments: ReviewComment[];
  coReviewerReviews: CoReviewerReview[];
  submitted: boolean;
  commentBody: string;
  onCommentBodyChange: (value: string) => void;
  onAddComment: (e: FormEvent) => void;
  onSectionStatusChange: (status: string) => void;
  showSectionNav: boolean;
  showChat?: boolean;
  onOpenChat: () => void;
  chatUnread?: boolean;
}) {
  const filteredComments = sectionComments.filter((c) => c.section_key === activeSection);
  const currentStatus = sectionStates.find((s) => s.section_key === activeSection)?.status || 'pending';

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
                    <span className="block capitalize">{key.replace(/_/g, ' ')}</span>
                    <span className="text-xs opacity-70">{state.replace(/_/g, ' ')}</span>
                  </button>
                </li>
              );
            })}
          </ul>
        </Card>
      )}

      <Card title="Section review" className="min-h-0 shrink-0">
        {!submitted && showSectionNav && (
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
            <li className="text-sm text-muted-foreground">No comments on this section yet.</li>
          ) : (
            filteredComments.map((c) => (
              <li key={c.id} className="rounded-lg border border-border bg-muted/40 p-3 text-sm">
                <p className="m-0 text-xs text-muted-foreground">{c.reviewer_name}</p>
                <p className="m-0 mt-1 text-foreground">{c.body}</p>
              </li>
            ))
          )}
        </ul>

        {!submitted && showSectionNav && (
          <form onSubmit={onAddComment} className="space-y-2">
            <Input
              value={commentBody}
              onChange={(e) => onCommentBodyChange(e.target.value)}
              placeholder="Add a comment on this section…"
            />
            <Button type="submit" variant="secondary" size="sm" disabled={!commentBody.trim()}>
              Add comment
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
          {chatUnread && (
            <span className="absolute right-3 top-1/2 h-2 w-2 -translate-y-1/2 rounded-full bg-accent" />
          )}
        </Button>
      )}
    </aside>
  );
}
