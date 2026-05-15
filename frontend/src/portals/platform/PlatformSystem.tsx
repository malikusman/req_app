import { useEffect, useState } from 'react';
import { api, type PlatformSystemHealth } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';

export function PlatformSystem() {
  const token = usePlatformToken();
  const [health, setHealth] = useState<PlatformSystemHealth | null>(null);

  useEffect(() => {
    if (!token) return;
    api.platformSystem(token).then(setHealth);
  }, [token]);

  if (!health) return <p>Loading…</p>;

  const wa = health.whatsapp_delivery;

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>System health</h1>
      <p style={{ color: '#64748b' }}>Service status and WhatsApp delivery metrics (last 24h).</p>

      <div className="grid-2" style={{ marginTop: '1.5rem' }}>
        {Object.entries(health.services).map(([name, svc]) => (
          <div className="card" key={name}>
            <h3 style={{ marginTop: 0, textTransform: 'capitalize' }}>{name}</h3>
            <span className={`badge badge-${svc.status === 'ok' ? 'completed' : 'invited'}`}>{svc.status}</span>
          </div>
        ))}
      </div>

      <div className="card" style={{ marginTop: '1rem' }}>
        <h3 style={{ marginTop: 0 }}>WhatsApp delivery health</h3>
        <table>
          <tbody>
            <tr>
              <td>Templates sent</td>
              <td>{wa.template_sent}</td>
            </tr>
            <tr>
              <td>Template failures</td>
              <td>{wa.template_failed}</td>
            </tr>
            <tr>
              <td>API errors</td>
              <td>{wa.api_errors}</td>
            </tr>
            <tr>
              <td>Failure rate</td>
              <td>{wa.failure_rate}%</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  );
}
