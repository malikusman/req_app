import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api, type ReviewerCompanyDetail } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';

export function ReviewerCompanyOverview() {
  const { companyId } = useParams();
  const token = useReviewerToken();
  const [company, setCompany] = useState<ReviewerCompanyDetail | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token || !companyId) return;
    api
      .reviewerCompany(token, Number(companyId))
      .then((d) => setCompany(d.company))
      .finally(() => setLoading(false));
  }, [token, companyId]);

  if (loading) return <p>Loading…</p>;
  if (!company) return <p>Company not found</p>;

  const reportId = company.latest_report?.id;

  return (
    <div>
      <h1>{company.name}</h1>
      <div style={{ display: 'flex', gap: '1rem', flexWrap: 'wrap', marginBottom: '1.5rem' }}>
        <div className="card" style={{ flex: '1 1 200px' }}>
          <h3 style={{ marginTop: 0 }}>Readiness</h3>
          <p style={{ fontSize: '2rem', margin: 0 }}>{company.report_readiness_score}%</p>
        </div>
        <div className="card" style={{ flex: '1 1 200px' }}>
          <h3 style={{ marginTop: 0 }}>Participation</h3>
          <p style={{ margin: 0 }}>
            {company.completed_count} / {company.invited_count} completed
          </p>
        </div>
        <div className="card" style={{ flex: '1 1 200px' }}>
          <h3 style={{ marginTop: 0 }}>Co-reviewers</h3>
          <p style={{ margin: 0 }}>{company.co_reviewer_count}</p>
        </div>
      </div>

      {reportId && (
        <div className="card">
          <h3 style={{ marginTop: 0 }}>Latest report (v{company.latest_report?.version})</h3>
          <p>
            Your review: <strong>{company.my_review_status || 'pending'}</strong>
          </p>
          <Link to={`/reviewer/companies/${companyId}/reports/${reportId}/review`} className="btn btn-primary">
            Open report review
          </Link>
        </div>
      )}

      <div style={{ marginTop: '1rem', display: 'flex', gap: '0.5rem' }}>
        <Link to={`/reviewer/companies/${companyId}/conversations`} className="btn btn-secondary">
          Conversations
        </Link>
        <Link to={`/reviewer/companies/${companyId}/chat`} className="btn btn-secondary">
          Co-reviewer chat
        </Link>
      </div>
    </div>
  );
}
