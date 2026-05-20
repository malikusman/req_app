import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type ReviewerCompanySummary } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, Badge, EmptyState, Skeleton } from '../../components/ui';

export function ReviewerDashboard() {
  const token = useReviewerToken();
  const [companies, setCompanies] = useState<ReviewerCompanySummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    setError('');
    api
      .reviewerCompanies(token)
      .then((d) => setCompanies(d.companies))
      .catch(() => setError('Could not load assigned companies.'))
      .finally(() => setLoading(false));
  }, [token]);

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <div className="grid gap-4 md:grid-cols-2">
          <Skeleton variant="card" />
          <Skeleton variant="card" />
        </div>
      </div>
    );
  }

  if (error && companies.length === 0) {
    return (
      <div className="space-y-6">
        <PageHeader
          title="Assigned companies"
          description="Review reports and discovery data for your assigned clients."
        />
        <EmptyState title="Unable to load assignments" description={error} />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Assigned companies"
        description="Review reports and discovery data for your assigned clients."
      />

      {error && (
        <div className="rounded-card border border-status-warning/30 bg-status-warningBg px-4 py-3 text-sm">
          {error}
        </div>
      )}

      {companies.length === 0 ? (
        <EmptyState
          title="No companies assigned yet"
          description="No companies assigned yet. Contact your platform administrator."
        />
      ) : (
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
          {companies.map((c) => (
            <Link key={c.id} to={`/reviewer/companies/${c.id}`} className="block no-underline">
              <Card className="transition-shadow hover:shadow-md">
                <h3 className="m-0 font-medium text-text-primary">{c.name}</h3>
                <div className="mt-3 flex flex-wrap gap-2">
                  <Badge variant="info">{c.report_readiness_score}% readiness</Badge>
                  <Badge variant="neutral">
                    {c.completed_count}/{c.invited_count} completed
                  </Badge>
                </div>
                <p className="mt-3 text-sm font-medium text-accent">Open company →</p>
              </Card>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
