import { useState, type FormEvent } from 'react';
import type { ReviewDiscussion } from '../../../lib/api';
import { Badge, Button, Textarea } from '../../../components/ui';

function targetLabel(thread: ReviewDiscussion) {
  if (thread.target_type === 'employee') return 'Employee (WhatsApp)';
  return thread.target_consultant_name ? `Co-consultant: ${thread.target_consultant_name}` : 'Co-consultant';
}

function DiscussionItem({
  discussion,
  depth,
  currentConsultantUserId,
  onReply,
  onResolve,
  disabled,
}: {
  discussion: ReviewDiscussion;
  depth: number;
  currentConsultantUserId: number | null;
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
    (currentConsultantUserId == null || discussion.author_consultant_user_id === currentConsultantUserId);

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
              currentConsultantUserId={currentConsultantUserId}
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
  currentConsultantUserId,
  onReply,
  onResolve,
  emptyMessage = 'No discussions yet.',
  disabled,
}: {
  discussions: ReviewDiscussion[];
  currentConsultantUserId: number | null;
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
          currentConsultantUserId={currentConsultantUserId}
          onReply={onReply}
          onResolve={onResolve}
          disabled={disabled}
        />
      ))}
    </ul>
  );
}
