import { useEffect, useState } from 'react';
import { usePlatformToken } from '../../lib/auth';

const API_URL = import.meta.env.VITE_API_URL || '';

type TrialRow = {
  company: { id: number; name: string; report_readiness_score: number; completed_count: number; invited_count: number };
  subscription: { trial_ends_at: string; days_remaining: number };
};

export function PlatformTrials() {
  const token = usePlatformToken();
  const [trials, setTrials] = useState<TrialRow[]>([]);
  const [loading, setLoading] = useState(true);

  const load = () => {
    if (!token) return;
    fetch(`${API_URL}/api/v1/platform/trials`, {
      headers: { Authorization: `Bearer ${token}` },
    })
      .then((r) => r.json())
      .then((d) => setTrials(d.trials || []))
      .finally(() => setLoading(false));
  };

  useEffect(() => {
    load();
  }, [token]);

  const extendTrial = async (companyId: number, days: number) => {
    if (!token) return;
    await fetch(`${API_URL}/api/v1/platform/trials/${companyId}/extend`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ days }),
    });
    load();
  };

  if (loading) return <p>Loading…</p>;

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Trials expiring soon</h1>
      <p style={{ color: '#64748b' }}>Companies with trials ending within 7 days.</p>
      <div className="card" style={{ marginTop: '1.5rem' }}>
        <table>
          <thead>
            <tr>
              <th>Company</th>
              <th>Readiness</th>
              <th>Participation</th>
              <th>Trial ends</th>
              <th>Actions</th>
            </tr>
          </thead>
          <tbody>
            {trials.map((t) => (
              <tr key={t.company.id}>
                <td>{t.company.name}</td>
                <td>{Math.round(t.company.report_readiness_score)}%</td>
                <td>
                  {t.company.completed_count} / {t.company.invited_count} completed
                </td>
                <td>
                  {t.subscription.days_remaining} days left
                </td>
                <td>
                  <button type="button" className="btn btn-secondary" onClick={() => extendTrial(t.company.id, 7)}>
                    +7 days
                  </button>
                  <button
                    type="button"
                    className="btn btn-secondary"
                    style={{ marginLeft: '0.5rem' }}
                    onClick={() => extendTrial(t.company.id, 14)}
                  >
                    +14 days
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {trials.length === 0 && <p style={{ color: '#64748b' }}>No trials expiring in the next 7 days.</p>}
      </div>
    </div>
  );
}
