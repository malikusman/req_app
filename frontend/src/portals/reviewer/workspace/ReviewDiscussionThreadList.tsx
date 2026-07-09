import { useState, type FormEvent } from 'react';
import type { ReviewDiscussion } from '../../../lib/api';
import { Badge, Button, Textarea } from '../../../components/ui';

function targetLabel(thread: ReviewDiscussion) {
  if (thread.target_type === 'employee') return 'Employee (WhatsApp)';
  return thread.target_reviewer_name ? `Co-reviewer: ${thread.target_reviewer_name}` : 'Co-reviewer';
}

function DiscussionItem({
  discussion,
  depth,
  currentReviewerUserId,
  onReply,
  onResolve,
  disabled,
}: {
  discussion: ReviewDiscussion;
  depth: number;
  currentReviewerUserId: number | null;
  onReply: (discussionId: number, body: string) => Promise<void>;
  onResolve: (discussionId: number) => Promise<void>;
  disabled?: boolean;
}) {
  const [replyBody, setReplyBody] = useState('');
  const [replying, setReplying] = useState(false);
  const [resolving, setResolving] = useState(false);
  const isRoot = depth === 0;
  const canResolve =
    isRoot &&
    discussion.status === 'open' &&
    !disabled &&
    (currentReviewerUserId == null || discussion.author_reviewer_user_id === currentReviewerUserId);

  const submitReply = async (e: FormEvent) => {
    e.preventDefault();
    if (!replyBody.trim()) return;
    setReplying(true);
    try {
      await onReply(discussion.id, replyBody.trim());
      setReplyBody('');
    } finally {
      setReplying(false);
    }
  };

  const handleResolve = async () => {
    setResolving(true);
    try {
      await onResolve(discussion.id);
    } finally {
      setResolving(false);
    }
  };

  return (
    <li className={depth > 0 ? 'ml-4 border-l border-border pl-3' : undefined}>
      <div className="rounded-lg border border-border bg-muted/30 p-3">
        <div className="mb-1 flex flex-wrap items-center gap-2">
          <span className="text-xs font-medium text-foreground">{discussion.author_name}</span>
          {isRoot && (
            <>
              <Badge variant={discussion.status === 'resolved' ? 'success' : 'info'}>{discussion.status}</Badge>
              <span className="text-xs text-muted-foreground">{targetLabel(discussion)}</span>
            </>
          )}
        </div>
        <p className="m-0 text-sm text-foreground">{discussion.body}</p>
        {isRoot && discussion.status === 'open' && !disabled && (
          <div className="mt-2 flex flex-wrap gap-2">
            {canResolve && (
              <Button size="sm" variant="secondary" loading={resolving} onClick={handleResolve}>
                Mark resolved
              </Button>
            )}
          </div>
        )}
      </div>

      {isRoot && discussion.status === 'open' && !disabled && (
        <form onSubmit={submitReply} className="mt-2 space-y-2">
          <Textarea
            rows={2}
            value={replyBody}
            onChange={(e) => setReplyBody(e.target.value)}
            placeholder="Reply to this thread…"
          />
          <Button size="sm" type="submit" disabled={!replyBody.trim()} loading={replying}>
            Reply
          </Button>
        </form>
      )}

      {discussion.replies.length > 0 && (
        <ul className="mt-2 space-y-2">
          {discussion.replies.map((reply) => (
            <DiscussionItem
              key={reply.id}
              discussion={reply}
              depth={depth + 1}
              currentReviewerUserId={currentReviewerUserId}
              onReply={onReply}
              onResolve={onResolve}
              disabled={disabled}
            />
          ))}
        </ul>
      )}
    </li>
  );
}

export function ReviewDiscussionThreadList({
  discussions,
  currentReviewerUserId,
  onReply,
  onResolve,
  emptyMessage = 'No discussions yet.',
  disabled,
}: {
  discussions: ReviewDiscussion[];
  currentReviewerUserId: number | null;
  onReply: (discussionId: number, body: string) => Promise<void>;
  onResolve: (discussionId: number) => Promise<void>;
  emptyMessage?: string;
  disabled?: boolean;
}) {
  if (discussions.length === 0) {
    return <p className="m-0 text-sm text-muted-foreground">{emptyMessage}</p>;
  }

  return (
    <ul className="m-0 list-none space-y-3 p-0">
      {discussions.map((thread) => (
        <DiscussionItem
          key={thread.id}
          discussion={thread}
          depth={0}
          currentReviewerUserId={currentReviewerUserId}
          onReply={onReply}
          onResolve={onResolve}
          disabled={disabled}
        />
      ))}
    </ul>
  );
}
