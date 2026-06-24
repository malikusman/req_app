import { useEffect, useState, type FormEvent } from 'react';
import { useParams } from 'react-router-dom';
import { api, type DiscoveryProvenanceEntry, type DiscoveryState, type MediaAttachment } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { ChatMessageList, type ChatMessageItem } from '../../components/motion';
import { ConversationMediaCard, ConversationMediaList } from '../../components/ConversationMediaCard';
import {
  PageHeader,
  Card,
  Textarea,
  Button,
  Skeleton,
  DiscoveryProvenancePanel,
} from '../../components/ui';

export function ReviewerConversationDetail() {
  const { companyId, conversationId } = useParams();
  const token = useReviewerToken();
  const [messages, setMessages] = useState<ChatMessageItem[]>([]);
  const [discoveryState, setDiscoveryState] = useState<DiscoveryState | null>(null);
  const [discoveryProvenance, setDiscoveryProvenance] = useState<DiscoveryProvenanceEntry[]>([]);
  const [highlightedMessageId, setHighlightedMessageId] = useState<number | null>(null);
  const [mediaAttachments, setMediaAttachments] = useState<MediaAttachment[]>([]);
  const [employeeId, setEmployeeId] = useState<number | null>(null);
  const [followupBody, setFollowupBody] = useState('');
  const [loading, setLoading] = useState(true);
  const [sending, setSending] = useState(false);
  const [error, setError] = useState('');

  const load = () => {
    if (!token || !companyId || !conversationId) return Promise.resolve();
    return api.reviewerConversation(token, Number(companyId), Number(conversationId)).then((d) => {
      setMessages(
        d.messages.map((m) => ({
          id: m.id,
          direction: m.direction === 'outbound' ? 'outbound' : 'inbound',
          body: m.reviewer_followup ? `[Follow-up] ${m.body}` : m.body,
          timestamp: m.created_at,
          meta:
            m.media_attachment && token ? (
              <ConversationMediaCard attachment={m.media_attachment} token={token} compact />
            ) : undefined,
        }))
      );
      setDiscoveryProvenance(d.discovery_provenance || []);
      setDiscoveryState(d.conversation.discovery_state ?? null);
      setMediaAttachments(d.media_attachments || []);
      setEmployeeId(d.conversation.employee_id ?? null);
    });
  };

  useEffect(() => {
    if (!token || !companyId || !conversationId) return;
    setLoading(true);
    setError('');
    load()
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load conversation'))
      .finally(() => setLoading(false));
  }, [token, companyId, conversationId]);

  const sendFollowup = async (e: FormEvent) => {
    e.preventDefault();
    if (!token || !companyId || !employeeId || !followupBody.trim()) return;
    setSending(true);
    try {
      await api.sendReviewerFollowup(token, Number(companyId), employeeId, followupBody.trim());
      setFollowupBody('');
      await load();
    } finally {
      setSending(false);
    }
  };

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Conversation"
        breadcrumbs={[
          { label: 'Company', href: `/reviewer/companies/${companyId}` },
          { label: 'Conversations', href: `/reviewer/companies/${companyId}/conversations` },
          { label: 'Transcript' },
        ]}
      />

      {error && <p className="text-sm text-destructive">{error}</p>}

      {token && mediaAttachments.length > 0 && (
        <Card title="Shared media">
          <ConversationMediaList attachments={mediaAttachments} token={token} />
        </Card>
      )}

      <div className="grid min-w-0 gap-4 lg:grid-cols-[minmax(0,1fr)_320px] lg:items-start">
        <Card className="min-w-0">
          <ChatMessageList
            messages={messages}
            className="max-h-[520px]"
            showTyping={sending}
            highlightedMessageId={highlightedMessageId}
          />
        </Card>

        <Card title="Discovery provenance" className="min-w-0 lg:sticky lg:top-6">
          <DiscoveryProvenancePanel
            state={discoveryState}
            provenance={discoveryProvenance}
            selectedMessageId={highlightedMessageId}
            onSelectMessage={setHighlightedMessageId}
          />
        </Card>
      </div>

      {employeeId && (
        <Card title="WhatsApp follow-up">
          <form onSubmit={sendFollowup} className="space-y-4">
            <Textarea rows={4} value={followupBody} onChange={(e) => setFollowupBody(e.target.value)} />
            <Button type="submit" disabled={!followupBody.trim() || sending} loading={sending}>
              Send follow-up
            </Button>
          </form>
        </Card>
      )}
    </div>
  );
}
