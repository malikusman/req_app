import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { ConversationMediaCard } from '../../components/ConversationMediaCard';
import { api, type MediaAttachment } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, EmptyState } from '../../components/ui';

export function CompanyMediaLibrary() {
  const token = useCompanyToken();
  const [attachments, setAttachments] = useState<MediaAttachment[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    api
      .companyMediaAttachments(token)
      .then((d) => setAttachments(d.media_attachments))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load media'))
      .finally(() => setLoading(false));
  }, [token]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="WhatsApp media"
        description="Voice notes, screenshots, and documents shared during discovery interviews."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      <Card>
        <DataTable
          loading={loading}
          columns={[
            {
              key: 'type',
              header: 'Type',
              render: (a) => <Badge variant="neutral">{a.attachment_type}</Badge>,
            },
            {
              key: 'employee',
              header: 'Employee',
              render: (a) => a.employee_name || '—',
            },
            {
              key: 'caption',
              header: 'Caption',
              render: (a) => a.caption || (a.structured_insights?.summary as string) || '—',
            },
            {
              key: 'conversation',
              header: 'Conversation',
              render: (a) =>
                a.conversation_id ? (
                  <Link to={`/company/conversations/${a.conversation_id}`} className="text-accent hover:underline">
                    View transcript
                  </Link>
                ) : (
                  '—'
                ),
            },
            {
              key: 'created',
              header: 'Shared',
              render: (a) => new Date(a.created_at).toLocaleString(),
            },
          ]}
          rows={attachments}
          emptyState={
            <EmptyState
              title="No media yet"
              description="Media appears here when employees share voice notes, screenshots, or documents on WhatsApp."
            />
          }
        />
      </Card>

      {attachments.length > 0 && token && (
        <div className="grid gap-4 md:grid-cols-2">
          {attachments.slice(0, 6).map((attachment) => (
            <ConversationMediaCard key={attachment.id} attachment={attachment} token={token} compact />
          ))}
        </div>
      )}
    </div>
  );
}
