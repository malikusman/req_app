import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import type {
  CompanyConversationMessage,
  DiscoveryProvenanceEntry,
  DiscoveryState,
  MediaAttachment,
  ReviewDiscussion,
} from '../../../lib/api';
import { ChatMessageList, type ChatMessageItem } from '../../../components/motion';
import { ConversationMediaCard, ConversationMediaList } from '../../../components/ConversationMediaCard';
import { Card, Button, Textarea, DiscoveryProvenancePanel } from '../../../components/ui';
import { EvidenceAskBubble } from './EvidenceAskBubble';

export function ReviewerTranscriptPanel({
  companyId,
  conversationId,
  employeeId,
  employeeName,
  messages,
  discoveryState,
  discoveryProvenance,
  mediaAttachments,
  token,
  highlightedMessageId,
  onHighlightMessage,
  onSendFollowup,
  sendingFollowup,
  discussions,
  coReviewers,
  onAskReviewer,
  onAskEmployee,
}: {
  companyId: number;
  conversationId: number;
  employeeId: number;
  employeeName: string | null;
  messages: CompanyConversationMessage[];
  discoveryState: DiscoveryState | null;
  discoveryProvenance: DiscoveryProvenanceEntry[];
  mediaAttachments: MediaAttachment[];
  token: string;
  highlightedMessageId: number | null;
  onHighlightMessage: (id: number | null) => void;
  onSendFollowup?: (body: string) => Promise<void>;
  sendingFollowup?: boolean;
  discussions?: ReviewDiscussion[];
  coReviewers?: { reviewer_user_id: number; reviewer_name: string }[];
  onAskReviewer?: (targetReviewerUserId: number, body: string, anchorType: 'message', anchorId: string, messageId: number) => Promise<void>;
  onAskEmployee?: (body: string, messageId: number) => Promise<void>;
}) {
  const [followupBody, setFollowupBody] = useState('');
  const threadDiscussions = discussions ?? [];
  const reviewers = coReviewers ?? [];

  const chatItems: ChatMessageItem[] = messages.map((m) => ({
    id: m.id,
    direction: m.direction === 'outbound' ? 'outbound' : 'inbound',
    body: m.reviewer_followup ? `[Follow-up] ${m.body}` : m.body,
    timestamp: m.created_at,
    meta:
      m.media_attachment && token ? (
        <ConversationMediaCard attachment={m.media_attachment} token={token} compact />
      ) : undefined,
    actions:
      onAskReviewer && reviewers.length > 0 ? (
        <EvidenceAskBubble
          anchorType="message"
          anchorId={String(m.id)}
          coReviewers={reviewers}
          employeeId={employeeId}
          conversationId={conversationId}
          discussions={threadDiscussions}
          onAskReviewer={(targetId, body) => onAskReviewer(targetId, body, 'message', String(m.id), m.id)}
          onAskEmployee={
            onAskEmployee ? (body) => onAskEmployee(body, m.id) : undefined
          }
        />
      ) : undefined,
  }));

  const handleFollowup = async (e: FormEvent) => {
    e.preventDefault();
    if (!onSendFollowup || !followupBody.trim()) return;
    await onSendFollowup(followupBody.trim());
    setFollowupBody('');
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between gap-3">
        <h3 className="m-0 text-base font-semibold text-foreground">{employeeName || 'Employee'} — transcript</h3>
        <Link
          to={`/reviewer/companies/${companyId}/conversations/${conversationId}`}
          className="text-sm font-medium text-accent hover:underline"
        >
          Open full screen
        </Link>
      </div>

      {mediaAttachments.length > 0 && (
        <Card title="Shared media">
          <ConversationMediaList attachments={mediaAttachments} token={token} />
        </Card>
      )}

      <div className="grid min-w-0 gap-4 lg:grid-cols-[minmax(0,1fr)_300px] lg:items-start">
        <Card className="min-w-0 overflow-visible">
          <ChatMessageList
            messages={chatItems}
            className="max-h-[520px] min-h-[320px]"
            showTyping={sendingFollowup}
            highlightedMessageId={highlightedMessageId}
          />
        </Card>

        <Card title="Question timeline" className="min-w-0 lg:sticky lg:top-4">
          <DiscoveryProvenancePanel
            state={discoveryState}
            provenance={discoveryProvenance}
            selectedMessageId={highlightedMessageId}
            onSelectMessage={onHighlightMessage}
          />
        </Card>
      </div>

      {onSendFollowup && (
        <Card title="Employee follow-up">
          <form onSubmit={handleFollowup} className="space-y-3">
            <Textarea
              rows={3}
              value={followupBody}
              onChange={(e) => setFollowupBody(e.target.value)}
              placeholder="Ask a clarifying question via WhatsApp…"
            />
            <Button type="submit" disabled={!followupBody.trim() || sendingFollowup} loading={sendingFollowup}>
              Send follow-up
            </Button>
          </form>
        </Card>
      )}
    </div>
  );
}
