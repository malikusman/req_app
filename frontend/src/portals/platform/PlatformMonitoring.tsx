import { useEffect, useState } from 'react';
import { api, type PlatformMonitoring } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';

export function PlatformMonitoringPage() {
  const token = usePlatformToken();
  const [data, setData] = useState<PlatformMonitoring | null>(null);

  useEffect(() => {
    if (!token) return;
    api.platformMonitoring(token).then(setData);
  }, [token]);

  if (!data) return <p>Loading…</p>;

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Monitoring</h1>
      <p style={{ color: '#64748b' }}>Cross-tenant metrics for operations and billing health.</p>

      <div className="grid-2" style={{ marginTop: '1.5rem' }}>
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Companies</h3>
          <p>Total: <strong>{data.companies.total}</strong></p>
          <p>Onboarded: <strong>{data.companies.onboarded}</strong></p>
          <p>Avg readiness: <strong>{data.companies.avg_readiness}%</strong></p>
        </div>
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Subscriptions</h3>
          {Object.entries(data.subscriptions.by_status).map(([status, count]) => (
            <p key={status}>
              {status}: <strong>{count}</strong>
            </p>
          ))}
          <p>Trials expiring (7d): <strong>{data.subscriptions.trials_expiring_7d}</strong></p>
          <p>At conversation limit: <strong>{data.subscriptions.at_conversation_limit}</strong></p>
        </div>
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Discovery</h3>
          <p>Active conversations: <strong>{data.discovery.active_conversations}</strong></p>
          <p>Completed employees: <strong>{data.discovery.completed_employees}</strong></p>
          <p>New conversations (24h): <strong>{data.discovery.conversations_last_24h}</strong></p>
        </div>
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Reports</h3>
          <p>Ready: <strong>{data.reports.ready}</strong></p>
          <p>Generating: <strong>{data.reports.generating}</strong></p>
          <p>Failed: <strong>{data.reports.failed}</strong></p>
        </div>
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Impersonation</h3>
          <p>Active sessions: <strong>{data.impersonations.active_sessions}</strong></p>
          <p>Sessions started (24h): <strong>{data.impersonations.last_24h}</strong></p>
        </div>
      </div>
    </div>
  );
}
