import { useEffect, useState } from 'react';
import { api, type MediaAttachment } from '../lib/api';
import { Badge } from './ui';

const TYPE_LABELS: Record<string, string> = {
  audio: 'Voice note',
  image: 'Image',
  document: 'Document',
};

export function ConversationMediaCard({
  attachment,
  token,
  compact = false,
}: {
  attachment: MediaAttachment;
  token: string;
  compact?: boolean;
}) {
  const [blobUrl, setBlobUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!attachment.download_url || attachment.status !== 'ready' || !token) return;

    let active = true;
    setLoading(true);
    setError('');

    api
      .fetchMediaBlob(token, attachment.download_url)
      .then((url) => {
        if (active) setBlobUrl(url);
      })
      .catch((err) => {
        if (active) setError(err instanceof Error ? err.message : 'Failed to load media');
      })
      .finally(() => {
        if (active) setLoading(false);
      });

    return () => {
      active = false;
    };
  }, [attachment.download_url, attachment.status, token]);

  useEffect(() => {
    return () => {
      if (blobUrl) URL.revokeObjectURL(blobUrl);
    };
  }, [blobUrl]);

  const summary =
    (attachment.structured_insights?.summary as string | undefined) ||
    attachment.caption ||
    TYPE_LABELS[attachment.attachment_type] ||
    'Media';

  if (attachment.status === 'processing' || attachment.status === 'pending') {
    return (
      <div className="rounded-lg border border-border bg-surface-secondary p-3 text-sm text-text-secondary">
        Processing {TYPE_LABELS[attachment.attachment_type]?.toLowerCase() || 'media'}…
      </div>
    );
  }

  if (attachment.status === 'failed') {
    return (
      <div className="rounded-lg border border-status-error/30 bg-surface-secondary p-3 text-sm text-status-error">
        Could not process {TYPE_LABELS[attachment.attachment_type]?.toLowerCase() || 'media'}.
        {attachment.processing_error ? ` ${attachment.processing_error}` : ''}
      </div>
    );
  }

  return (
    <div className={`rounded-lg border border-border bg-surface-secondary ${compact ? 'p-2' : 'p-3'}`}>
      <div className="mb-2 flex flex-wrap items-center gap-2">
        <Badge variant="neutral">{TYPE_LABELS[attachment.attachment_type] || attachment.attachment_type}</Badge>
        {attachment.confidence != null && (
          <span className="text-xs text-text-secondary">{Math.round(attachment.confidence * 100)}% confidence</span>
        )}
      </div>

      {!compact && attachment.caption && (
        <p className="mb-2 text-sm text-text-primary">{attachment.caption}</p>
      )}

      {loading && <p className="text-sm text-text-secondary">Loading preview…</p>}
      {error && <p className="text-sm text-status-error">{error}</p>}

      {blobUrl && attachment.attachment_type === 'image' && (
        <img
          src={blobUrl}
          alt={summary}
          className={`mt-2 max-w-full rounded-md border border-border object-contain ${compact ? 'max-h-40' : 'max-h-64'}`}
        />
      )}

      {blobUrl && attachment.attachment_type === 'audio' && (
        <audio controls src={blobUrl} className="mt-2 w-full" preload="metadata" />
      )}

      {blobUrl && attachment.attachment_type === 'document' && (
        <a
          href={blobUrl}
          download={attachment.filename}
          className="mt-2 inline-flex text-sm font-medium text-accent hover:underline"
        >
          Download {attachment.filename}
        </a>
      )}

      {!compact && summary && attachment.attachment_type !== 'audio' && (
        <p className="mt-2 text-xs text-text-secondary">{summary}</p>
      )}
    </div>
  );
}

export function ConversationMediaList({
  attachments,
  token,
}: {
  attachments: MediaAttachment[];
  token: string;
}) {
  if (attachments.length === 0) {
    return <p className="text-sm text-text-secondary">No media shared yet.</p>;
  }

  return (
    <div className="space-y-3">
      {attachments.map((attachment) => (
        <ConversationMediaCard key={attachment.id} attachment={attachment} token={token} />
      ))}
    </div>
  );
}
