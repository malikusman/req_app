import { useEffect, useState } from 'react';
import { api, type Recommendation } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';

export function CompanyRecommendations() {
  const token = useCompanyToken();
  const [recs, setRecs] = useState<Recommendation[]>([]);

  useEffect(() => {
    if (!token) return;
    api.companyRecommendations(token).then((d) => setRecs(d.recommendations));
  }, [token]);

  const submitFeedback = async (id: number, feedback: string) => {
    if (!token) return;
    await api.recommendationFeedback(token, id, feedback);
    api.companyRecommendations(token).then((d) => setRecs(d.recommendations));
  };

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Recommendations</h1>
      <p style={{ color: '#64748b' }}>AI-generated opportunities with matched solutions from our catalog.</p>

      {recs.map((r) => (
        <div className="card" key={r.id} style={{ marginBottom: '1rem' }}>
          <h3 style={{ margin: '0 0 0.5rem' }}>{r.title}</h3>
          <span className={`badge badge-${r.priority === 'high' ? 'completed' : 'invited'}`}>{r.priority}</span>
          <p style={{ color: '#475569' }}>{r.description}</p>
          {r.implementation_outline && <p style={{ fontSize: '0.9rem' }}>{r.implementation_outline}</p>}
          {r.catalog_matches?.length > 0 && (
            <div style={{ marginTop: '0.75rem' }}>
              <strong>Suggested tools:</strong>
              <ul>
                {r.catalog_matches.map((c, i) => (
                  <li key={i}>
                    {c.name}
                    {c.vendor ? ` (${c.vendor})` : ''}
                  </li>
                ))}
              </ul>
            </div>
          )}
          <div style={{ marginTop: '1rem', display: 'flex', gap: '0.5rem', flexWrap: 'wrap' }}>
            {['interested', 'already_doing', 'not_relevant'].map((f) => (
              <button
                key={f}
                type="button"
                className={r.company_feedback === f ? 'btn btn-primary' : 'btn btn-secondary'}
                onClick={() => submitFeedback(r.id, f)}
              >
                {f.replace(/_/g, ' ')}
              </button>
            ))}
          </div>
        </div>
      ))}
      {recs.length === 0 && <p style={{ color: '#94a3b8' }}>Complete discovery interviews to generate recommendations.</p>}
    </div>
  );
}
