import { Link, useParams } from 'react-router-dom';
import { ChatMessageList, type ChatMessageItem } from '../../components/motion';
import { PageHeader, Card, Badge, EmptyState } from '../../components/ui';
import { mockConversations } from '../../lib/mocks/companyConversations';

const mockMessages: ChatMessageItem[] = [
  { id: 1, direction: 'inbound', body: 'Hi, I received the invite for the discovery interview.', timestamp: '2026-05-19T09:00:00Z' },
  { id: 2, direction: 'outbound', body: 'Welcome! Please share your access code to begin.', timestamp: '2026-05-19T09:01:00Z' },
  { id: 3, direction: 'inbound', body: 'Done — ready to talk about our month-end close process.', timestamp: '2026-05-19T09:02:00Z' },
];

export function CompanyConversationDetail() {
  const { id } = useParams();
  const conversation = mockConversations.find((c) => c.id === Number(id));

  if (!conversation) {
    return <EmptyState title="Conversation not found" description="This conversation may no longer exist." />;
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title={conversation.employee_name}
        description={`${conversation.department} · discovery interview`}
        breadcrumbs={[
          { label: 'Conversations', href: '/company/conversations' },
          { label: conversation.employee_name },
        ]}
        actions={
          <Link to="/company/conversations">
            <Badge variant="neutral">Back</Badge>
          </Link>
        }
      />

      <div className="grid gap-6 lg:grid-cols-3">
        <Card title="Details" className="lg:col-span-1">
          <dl className="space-y-3 text-sm">
            <div>
              <dt className="text-text-secondary">Status</dt>
              <dd>
                <Badge variant={conversation.status === 'completed' ? 'success' : 'info'}>{conversation.status}</Badge>
              </dd>
            </div>
            <div>
              <dt className="text-text-secondary">Last activity</dt>
              <dd className="text-text-primary">{new Date(conversation.last_activity_at).toLocaleString()}</dd>
            </div>
          </dl>
        </Card>

        <Card title="Transcript" className="lg:col-span-2">
          <ChatMessageList messages={mockMessages} className="max-h-[480px]" />
        </Card>
      </div>
    </div>
  );
}
