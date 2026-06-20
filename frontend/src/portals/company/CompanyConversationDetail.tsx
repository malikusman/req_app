import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ChatMessageList, type ChatMessageItem } from '../../components/motion';
import { ConversationMediaCard, ConversationMediaList } from '../../components/ConversationMediaCard';
import { api, type CompanyConversation, type CompanyConversationMessage, type MediaAttachment } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Badge, EmptyState, Skeleton } from '../../components/ui';

export function CompanyConversationDetail() {
  const { id } = useParams();
  const token = useCompanyToken();
  const [conversation, setConversation] = useState<CompanyConversation | null>(null);
  const [messages, setMessages] = useState<CompanyConversationMessage[]>([]);
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

      <div className="grid gap-6 lg:grid-cols-3">
        <div className="space-y-6 lg:col-span-1">
          <Card title="Details">
            <dl className="space-y-3 text-sm">
              <div>
                <dt className="text-text-secondary">Status</dt>
                <dd>
                  <Badge variant={conversation.status === 'completed' ? 'success' : 'info'}>
                    {conversation.status}
                  </Badge>
                </dd>
              </div>
              <div>
                <dt className="text-text-secondary">Questions</dt>
                <dd className="text-text-primary">{conversation.question_count ?? 0}</dd>
              </div>
              <div>
                <dt className="text-text-secondary">Last activity</dt>
                <dd className="text-text-primary">
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

        <Card title="Transcript" className="lg:col-span-2">
          {chatMessages.length === 0 ? (
            <EmptyState title="No messages yet" description="Messages appear once the interview starts." />
          ) : (
            <ChatMessageList messages={chatMessages} className="max-h-[480px]" />
          )}
        </Card>
      </div>
    </div>
  );
}
