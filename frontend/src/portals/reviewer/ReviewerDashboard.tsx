import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type ReviewerCompanySummary } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';

export function ReviewerDashboard() {
  const token = useReviewerToken();
  const [companies, setCompanies] = useState<ReviewerCompanySummary[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    api.reviewerCompanies(token).then((d) => setCompanies(d.companies)).finally(() => setLoading(false));
  }, [token]);

  if (loading) return <p>Loading…</p>;

  return (
    <div>
      <h1>Assigned companies</h1>
      <p style={{ color: '#64748b' }}>Review reports and discovery data for your assigned clients.</p>
      <div className="card" style={{ marginTop: '1rem' }}>
        {companies.length === 0 ? (
          <p>No company assignments yet. Contact the platform team.</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>Company</th>
                <th>Readiness</th>
                <th>Participation</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {companies.map((c) => (
                <tr key={c.id}>
                  <td>{c.name}</td>
                  <td>{c.report_readiness_score}%</td>
                  <td>
                    {c.completed_count}/{c.invited_count}
                  </td>
                  <td>
                    <Link to={`/reviewer/companies/${c.id}`} className="btn btn-secondary btn-sm">
                      Open
                    </Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
