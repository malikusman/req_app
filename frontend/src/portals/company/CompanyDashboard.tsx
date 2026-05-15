import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type IntelligenceSnapshot } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';

export function CompanyDashboard() {
  const token = useCompanyToken();
  const [snapshot, setSnapshot] = useState<IntelligenceSnapshot | null>(null);
  const [score, setScore] = useState(0);
  const [breakdown, setBreakdown] = useState<Record<string, number>>({});

  useEffect(() => {
    if (!token) return;
    api.intelligenceSnapshot(token).then((d) => {
      setSnapshot(d.snapshot);
      setScore(Math.round(d.report_readiness_score));
      setBreakdown(d.report_readiness_breakdown as Record<string, number>);
    });
  }, [token]);

  if (!snapshot) return <p>Loading…</p>;

  const participation = snapshot.participation;

  return (
    <div>
      <h1 style={{ marginTop: 0 }}>Discovery intelligence</h1>
      <p style={{ color: '#64748b' }}>Live operational snapshot — signals, patterns, and recommendations from your discovery program.</p>

      <div className="grid-2" style={{ marginTop: '1.5rem' }}>
        <div className="card stat">
          <div className="stat-value">{score}%</div>
          <div className="stat-label">Report readiness</div>
          <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', marginTop: '0.75rem' }}>
            <span className="badge" style={{ background: '#e2e8f0', color: '#334155' }}>
              employees: {breakdown.employees_interviewed || 0}
            </span>
            <span className="badge" style={{ background: '#e2e8f0', color: '#334155' }}>
              patterns: {breakdown.confirmed_patterns || 0}
            </span>
            <span className="badge" style={{ background: '#e2e8f0', color: '#334155' }}>
              multimodal: {breakdown.multimodal_contributions || 0}
            </span>
          </div>
        </div>
        <div className="card stat">
          <div className="stat-value">{participation.completed}</div>
          <div className="stat-label">Interviews completed</div>
          <p style={{ margin: '0.5rem 0 0', color: '#64748b', fontSize: '0.85rem' }}>
            {participation.invited} invited · {Math.round(participation.completion_rate * 100)}% completion
          </p>
        </div>
      </div>

      <div className="grid-2" style={{ marginTop: '1rem' }}>
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Top pain points</h3>
          {snapshot.top_pain_points.length === 0 ? (
            <p style={{ color: '#94a3b8' }}>Complete more interviews to surface signals.</p>
          ) : (
            snapshot.top_pain_points.map((s) => (
              <div key={s.id} style={{ marginBottom: '0.75rem' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '0.9rem' }}>
                  <strong>{s.label}</strong>
                  <span>{Math.round(s.strength * 100)}%</span>
                </div>
                <div style={{ height: 6, background: '#e2e8f0', borderRadius: 4, marginTop: 4 }}>
                  <div style={{ width: `${s.strength * 100}%`, height: '100%', background: '#3b82f6', borderRadius: 4 }} />
                </div>
                <small style={{ color: '#94a3b8' }}>{s.departments.join(', ') || s.signal_type}</small>
              </div>
            ))
          )}
        </div>

        <div className="card">
          <h3 style={{ marginTop: 0 }}>Emerging patterns</h3>
          {snapshot.emerging_patterns.length === 0 ? (
            <p style={{ color: '#94a3b8' }}>Patterns emerge as signals strengthen across teams.</p>
          ) : (
            snapshot.emerging_patterns.map((p) => (
              <div key={p.id} style={{ marginBottom: '0.75rem', paddingBottom: '0.75rem', borderBottom: '1px solid #e2e8f0' }}>
                <strong>{p.title}</strong>
                <br />
                <small style={{ color: '#64748b' }}>Confidence {Math.round(p.confidence * 100)}% · {p.departments.join(', ')}</small>
              </div>
            ))
          )}
        </div>
      </div>

      <div className="card" style={{ marginTop: '1rem' }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h3 style={{ margin: 0 }}>Insights over time</h3>
          <Link to="/company/intelligence/timeline">View full timeline</Link>
        </div>
        <ul style={{ margin: '1rem 0 0', paddingLeft: '1.25rem', color: '#475569' }}>
          {snapshot.recent_timeline.slice(0, 5).map((e, i) => (
            <li key={i} style={{ marginBottom: '0.5rem' }}>
              <strong>{e.title}</strong>
              <br />
              <small>{new Date(e.occurred_at).toLocaleString()}</small>
            </li>
          ))}
          {snapshot.recent_timeline.length === 0 && <li>No timeline events yet.</li>}
        </ul>
      </div>

      <div style={{ display: 'flex', gap: '0.75rem', marginTop: '1rem', flexWrap: 'wrap' }}>
        <Link to="/company/recommendations" className="btn btn-primary">
          Recommendations ({snapshot.recommendation_count})
        </Link>
        <Link to="/company/discovery-questions" className="btn btn-secondary">
          Discovery questions
        </Link>
        <Link to="/company/employees" className="btn btn-secondary">
          Manage employees
        </Link>
      </div>
    </div>
  );
}
