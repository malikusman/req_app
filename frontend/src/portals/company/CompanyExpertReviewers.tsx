import { useEffect, useState } from 'react';
import { api, type ReviewerPublicCard } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { Card } from '../../components/ui';
import { ExpertReviewerCard } from '../../components/ExpertReviewerCard';

export function CompanyExpertReviewers({ hideIntro = false }: { hideIntro?: boolean }) {
  const token = useCompanyToken();
  const [reviewers, setReviewers] = useState<ReviewerPublicCard[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    api
      .companyExpertReviewers(token)
      .then((d) => setReviewers(d.expert_reviewers))
      .catch(() => setReviewers([]))
      .finally(() => setLoading(false));
  }, [token]);

  if (loading) return null;

  return (
    <Card title={hideIntro ? undefined : 'Assigned reviewers'}>
      {!hideIntro ? (
        <p className="mb-4 text-sm text-text-secondary">
          {reviewers.length === 0
            ? 'Reviewers appear here when Worktruth assigns experts to your company and they publish their profile.'
            : 'Independent experts shaping your transformation report — verified by Worktruth.'}
        </p>
      ) : null}
      {reviewers.length > 0 ? (
        <div className="grid gap-4 lg:grid-cols-2">
          {reviewers.map((r) => (
            <ExpertReviewerCard key={r.id} reviewer={r} token={token} />
          ))}
        </div>
      ) : (
        <p className="m-0 text-sm text-muted-foreground">
          No reviewer assigned yet — we'll introduce your expert here once they're matched to you.
        </p>
      )}
    </Card>
  );
}
