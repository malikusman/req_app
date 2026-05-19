import { useEffect, useState } from 'react';
import { api, type TimelineEvent } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { PageHeader, Card, Timeline, EmptyState, Skeleton } from '../../components/ui';

export function CompanyTimeline() {
  const token = useCompanyToken();
  const [events, setEvents] = useState<TimelineEvent[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    api
      .intelligenceTimeline(token)
      .then((d) => setEvents(d.events))
      .finally(() => setLoading(false));
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

      <Card>
        {events.length === 0 ? (
          <EmptyState
            title="No events yet"
            description="Complete interviews or upload documents to populate the timeline."
          />
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
