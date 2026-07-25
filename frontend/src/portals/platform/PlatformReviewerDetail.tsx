import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { FileText } from 'lucide-react';
import { api, type ReviewerUser, type ReviewerPublicCard } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, Button, Badge, Skeleton } from '../../components/ui';
import { ExpertReviewerCard } from '../../components/ExpertReviewerCard';

function toPublicCard(reviewer: ReviewerUser): ReviewerPublicCard {
  if (reviewer.public_card) return reviewer.public_card;
  const p = reviewer.profile;
  return {
    id: reviewer.id,
    name: reviewer.name,
    headline: p?.headline ?? reviewer.headline ?? null,
    bio: p?.bio ?? null,
    avatar_url: p?.avatar_url ?? reviewer.avatar_url ?? null,
    expertise_tags: p?.expertise_tags ?? reviewer.expertise_tags ?? [],
    industries: p?.industries ?? [],
    years_experience: p?.years_experience ?? null,
    languages: p?.languages ?? [],
    location: p?.location ?? null,
    linkedin_url: p?.linkedin_url ?? null,
    profile_status: p?.profile_status ?? reviewer.profile_status ?? 'draft',
    platform_verified: Boolean(p?.platform_verified_at),
    experiences: p?.experiences ?? [],
  };
}

export function PlatformReviewerDetail() {
  const { id } = useParams();
  const reviewerId = Number(id);
  const token = usePlatformToken();
  const [reviewer, setReviewer] = useState<ReviewerUser | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [cvLoading, setCvLoading] = useState(false);

  useEffect(() => {
    if (!token || !reviewerId) return;
    setLoading(true);
    api
      .platformReviewer(token, reviewerId)
      .then((d) => setReviewer(d.reviewer))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load reviewer'))
      .finally(() => setLoading(false));
  }, [token, reviewerId]);

  const openCv = async () => {
    if (!token || !reviewerId) return;
    setCvLoading(true);
    setError('');
    try {
      const url = await api.platformReviewerCvUrl(token, reviewerId);
      window.open(url, '_blank', 'noopener,noreferrer');
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Could not open CV');
    } finally {
      setCvLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="space-y-4">
        <Skeleton variant="text" />
        <Skeleton variant="card" />
      </div>
    );
  }

  if (!reviewer) {
    return (
      <div className="space-y-4">
        <PageHeader title="Reviewer" description={error || 'Not found'} />
        <Link to="/platform/reviewers">
          <Button variant="secondary">Back to reviewers</Button>
        </Link>
      </div>
    );
  }

  const hasCv = Boolean(reviewer.has_cv || reviewer.profile?.has_cv);

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <PageHeader
        title={reviewer.name}
        description={reviewer.email}
        breadcrumbs={[
          { label: 'Reviewers', href: '/platform/reviewers' },
          { label: reviewer.name },
        ]}
        actions={
          <div className="flex flex-wrap gap-2">
            {hasCv ? (
              <Button variant="secondary" loading={cvLoading} onClick={openCv}>
                <FileText className="mr-1.5 h-4 w-4" />
                View CV
              </Button>
            ) : null}
            <Link to="/platform/reviewers">
              <Button variant="secondary">Back</Button>
            </Link>
          </div>
        }
      />

      {error ? <p className="text-sm text-status-error">{error}</p> : null}

      <div className="flex flex-wrap gap-2">
        <Badge variant={reviewer.status === 'active' ? 'success' : 'neutral'}>{reviewer.status}</Badge>
        {reviewer.profile_status === 'published' ? (
          <Badge variant="success">Published</Badge>
        ) : (
          <Badge variant="warning">Draft · {reviewer.profile_completeness_percent ?? 0}%</Badge>
        )}
        {hasCv ? <Badge variant="info">CV on file</Badge> : null}
      </div>

      <ExpertReviewerCard reviewer={toPublicCard(reviewer)} token={token} />

      {reviewer.assignments && reviewer.assignments.length > 0 ? (
        <Card title="Active company assignments">
          <ul className="m-0 space-y-2 p-0">
            {reviewer.assignments.map((a) => (
              <li key={a.company_id} className="list-none">
                <Link
                  to={`/platform/companies/${a.company_id}`}
                  className="text-sm font-medium text-primary hover:underline"
                >
                  {a.company_name}
                </Link>
              </li>
            ))}
          </ul>
        </Card>
      ) : (
        <Card title="Active company assignments">
          <p className="m-0 text-sm text-muted-foreground">Not assigned to any company.</p>
        </Card>
      )}
    </div>
  );
}
