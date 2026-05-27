import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type ReviewerCompanySummary } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { AnimatedCard, Stagger } from '../../components/motion';
import { PageHeader, Card, Badge, EmptyState, Skeleton } from '../../components/ui';

export function ReviewerDashboard() {
  const token = useReviewerToken();
  const [companies, setCompanies] = useState<ReviewerCompanySummary[]>([]);
  const [profilePercent, setProfilePercent] = useState<number | null>(null);
  const [profilePublished, setProfilePublished] = useState(true);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    setLoading(true);
    setError('');
    Promise.all([api.reviewerCompanies(token), api.reviewerMe(token)])
      .then(([companiesRes, meRes]) => {
        setCompanies(companiesRes.companies);
        setProfilePercent(meRes.profile_completeness_percent);
        setProfilePublished(meRes.profile.profile_status === 'published');
      })
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

      {!profilePublished && profilePercent != null && (
        <div className="rounded-card border border-accent/30 bg-surface-muted px-4 py-3 text-sm text-text-primary">
          Your expert profile is {profilePercent}% complete.{' '}
          <Link to="/reviewer/profile" className="font-medium text-accent hover:underline">
            Complete your profile →
          </Link>
        </div>
      )}

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
        <Stagger className="grid gap-4 md:grid-cols-2 lg:grid-cols-3" staggerDelay={0.08}>
          {companies.map((c) => (
            <Link key={c.id} to={`/reviewer/companies/${c.id}`} className="block no-underline">
              <AnimatedCard>
                <Card className="h-full transition-shadow hover:shadow-md">
                  <h3 className="m-0 font-medium text-text-primary">{c.name}</h3>
                  <div className="mt-3 flex flex-wrap gap-2">
                    <Badge variant="info">{c.report_readiness_score}% readiness</Badge>
                    <Badge variant="neutral">
                      {c.completed_count}/{c.invited_count} completed
                    </Badge>
                  </div>
                  <p className="mt-3 text-sm font-medium text-accent">Open company →</p>
                </Card>
              </AnimatedCard>
            </Link>
          ))}
        </Stagger>
      )}
    </div>
  );
}
