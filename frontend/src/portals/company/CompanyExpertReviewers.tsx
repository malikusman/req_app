import { useEffect, useState } from 'react';
import { api, type ReviewerPublicCard } from '../../lib/api';
import { useCompanyToken } from '../../lib/auth';
import { Card } from '../../components/ui';
import { ExpertReviewerCard } from '../../components/ExpertReviewerCard';

export function CompanyExpertReviewers() {
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

  if (loading || reviewers.length === 0) return null;

  return (
    <Card title="Req expert reviewers">
      <p className="mb-4 text-sm text-text-secondary">
        Independent experts shaping your transformation report — verified by Req.
      </p>
      <div className="grid gap-4 md:grid-cols-2">
        {reviewers.map((r) => (
          <ExpertReviewerCard key={r.id} reviewer={r} />
        ))}
      </div>
    </Card>
  );
}
