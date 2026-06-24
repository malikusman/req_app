import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ChatMessageList, type ChatMessageItem } from '../../components/motion';
import { ConversationMediaCard, ConversationMediaList } from '../../components/ConversationMediaCard';
import {
  api,
  type CompanyConversation,
  type CompanyConversationMessage,
  type DiscoveryProvenanceEntry,
  type MediaAttachment,
} from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import {
  PageHeader,
  Card,
  Badge,
  EmptyState,
  Skeleton,
  DiscoveryProvenancePanel,
} from '../../components/ui';

export function CompanyConversationDetail() {
  const { id } = useParams();
  const token = useCompanyToken();
  const [conversation, setConversation] = useState<CompanyConversation | null>(null);
  const [messages, setMessages] = useState<CompanyConversationMessage[]>([]);
  const [discoveryProvenance, setDiscoveryProvenance] = useState<DiscoveryProvenanceEntry[]>([]);
  const [highlightedMessageId, setHighlightedMessageId] = useState<number | null>(null);
  const [mediaAttachments, setMediaAttachments] = useState<MediaAttachment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token || !id) return;
    setLoading(true);
    api
      .companyConversation(token, Number(id))
      .then((d) => {
        setConversation(d.conversation);
        setMessages(d.messages);
        setDiscoveryProvenance(d.discovery_provenance || []);
        setMediaAttachments(d.media_attachments || []);
      })
      .catch((err) => {
        setConversation(null);
        setError(err instanceof Error ? err.message : 'Failed to load conversation');
      })
      .finally(() => setLoading(false));
  }, [token, id]);

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  if (!conversation) {
    return (
      <EmptyState
        title="Conversation not found"
        description={error || 'This conversation may no longer exist.'}
      />
    );
  }

  const chatMessages: ChatMessageItem[] = messages.map((m) => ({
    id: m.id,
    direction: m.direction as 'inbound' | 'outbound',
    body: m.body,
    timestamp: m.created_at,
    meta:
      token && m.media_attachment ? (
        <ConversationMediaCard attachment={m.media_attachment} token={token} compact />
      ) : undefined,
  }));

  const employeeName = conversation.employee_name || `Employee #${conversation.employee_id}`;

  return (
    <div className="space-y-6">
      <PageHeader
        title={employeeName}
        description={`${conversation.department || 'General'} · discovery interview`}
        breadcrumbs={[
          { label: 'Conversations', href: '/company/conversations' },
          { label: employeeName },
        ]}
        actions={
          <Link to="/company/conversations">
            <Badge variant="neutral">Back</Badge>
          </Link>
        }
      />

      <div className="grid min-w-0 gap-6 lg:grid-cols-[240px_minmax(0,1fr)_300px]">
        <div className="space-y-6">
          <Card title="Details">
            <dl className="space-y-3 text-sm">
              <div>
                <dt className="text-muted-foreground">Status</dt>
                <dd>
                  <Badge variant={conversation.status === 'completed' ? 'success' : 'info'}>
                    {conversation.status}
                  </Badge>
                </dd>
              </div>
              <div>
                <dt className="text-muted-foreground">Questions</dt>
                <dd className="text-foreground">{conversation.question_count ?? 0}</dd>
              </div>
              <div>
                <dt className="text-muted-foreground">Last activity</dt>
                <dd className="text-foreground">
                  {conversation.last_activity_at
                    ? new Date(conversation.last_activity_at).toLocaleString()
                    : '—'}
                </dd>
              </div>
            </dl>
          </Card>

          <Card title="Shared media">
            {token ? (
              <ConversationMediaList attachments={mediaAttachments} token={token} />
            ) : (
              <EmptyState title="Sign in required" description="Media previews require an active session." />
            )}
          </Card>
        </div>

        <Card title="Transcript" className="min-w-0">
          {chatMessages.length === 0 ? (
            <EmptyState title="No messages yet" description="Messages appear once the interview starts." />
          ) : (
            <ChatMessageList
              messages={chatMessages}
              className="max-h-[520px]"
              highlightedMessageId={highlightedMessageId}
            />
          )}
        </Card>

        <Card title="Discovery provenance" className="min-w-0 lg:sticky lg:top-6">
          <DiscoveryProvenancePanel
            state={conversation.discovery_state}
            provenance={discoveryProvenance}
            selectedMessageId={highlightedMessageId}
            onSelectMessage={setHighlightedMessageId}
          />
        </Card>
      </div>
    </div>
  );
}
