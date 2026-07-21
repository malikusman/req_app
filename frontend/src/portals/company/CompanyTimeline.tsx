import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { api, type TimelineEvent } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Timeline, EmptyState, Skeleton, Button } from '../../components/ui';

export function CompanyTimeline() {
  const token = useCompanyToken();
  const navigate = useNavigate();
  const [events, setEvents] = useState<TimelineEvent[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');

  const load = () => {
    if (!token) return;
    setLoadError('');
    api
      .intelligenceTimeline(token)
      .then((d) => setEvents(d.events))
      .catch(() => setLoadError('Could not load the timeline.'))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

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
        title="Insights timeline"
        description="How your operational picture built up over time."
      />

      {loadError && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-button border border-status-error/30 bg-status-errorBg px-4 py-3 text-sm text-status-error">
          <span>{loadError}</span>
          <Button size="sm" variant="secondary" onClick={load}>
            Retry
          </Button>
        </div>
      )}

      <Card>
        {events.length === 0 ? (
          loadError ? (
            <p className="text-sm text-text-secondary">Timeline events could not be loaded.</p>
          ) : (
            <EmptyState
              title="No events yet"
              description="Complete interviews or upload documents to populate the timeline."
              action={{ label: 'Upload documents', onClick: () => navigate('/company/documents') }}
              secondaryAction={{ label: 'Invite employees', onClick: () => navigate('/company/employees') }}
            />
          )
        ) : (
          <Timeline
            events={events.map((e) => ({
              id: String(e.id),
              title: e.title,
              summary: e.summary ?? undefined,
              occurredAt: e.occurred_at,
            }))}
          />
        )}
      </Card>
    </div>
  );
}
