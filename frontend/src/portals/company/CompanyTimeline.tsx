import { useEffect, useState } from 'react';
import { api, type TimelineEvent } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';

export function CompanyTimeline() {
  const token = useCompanyToken();
  const [events, setEvents] = useState<TimelineEvent[]>([]);

  useEffect(() => {
    if (!token) return;
    api.intelligenceTimeline(token).then((d) => setEvents(d.events));
  }, [token]);

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Insights timeline</h1>
      <p style={{ color: '#64748b' }}>How your operational picture built up over time.</p>

      <div className="card">
        {events.length === 0 ? (
          <p style={{ color: '#94a3b8' }}>No events yet. Complete interviews or upload documents to populate the timeline.</p>
        ) : (
          <ul style={{ listStyle: 'none', margin: 0, padding: 0 }}>
            {events.map((e) => (
              <li key={e.id} style={{ padding: '1rem 0', borderBottom: '1px solid #e2e8f0' }}>
                <div style={{ fontSize: '0.8rem', color: '#94a3b8', textTransform: 'uppercase' }}>{e.event_type.replace(/_/g, ' ')}</div>
                <strong style={{ display: 'block', marginTop: 4 }}>{e.title}</strong>
                {e.summary && <p style={{ margin: '0.25rem 0 0', color: '#64748b' }}>{e.summary}</p>}
                <small style={{ color: '#94a3b8' }}>{new Date(e.occurred_at).toLocaleString()}</small>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}
