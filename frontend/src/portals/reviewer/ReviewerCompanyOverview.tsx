import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { api, type ReviewerCompanyDetail } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, StatCard, Button, Badge, Skeleton, EmptyState } from '../../components/ui';
import { FileBarChart, Users, UserPlus } from 'lucide-react';

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

  if (loading) {
    return (
      <div className="space-y-6">
        <Skeleton variant="text" />
        <div className="grid gap-4 md:grid-cols-3">
          {[1, 2, 3].map((i) => (
            <Skeleton key={i} variant="card" />
          ))}
        </div>
      </div>
    );
  }

  if (!company) {
    return (
      <div className="space-y-6">
        <PageHeader title="Company" description="Company overview and report review." />
        <EmptyState title="Company not found" description="This company may no longer be assigned to you." />
      </div>
    );
  }

  const reportId = company.latest_report?.id;

  return (
    <div className="space-y-6">
      <PageHeader title={company.name} description="Company overview and report review." />

      <div className="grid gap-4 md:grid-cols-3">
        <StatCard
          label="Readiness"
          value={`${company.report_readiness_score}%`}
          icon={<FileBarChart className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Participation"
          value={`${company.completed_count} / ${company.invited_count}`}
          icon={<Users className="h-5 w-5 text-accent" />}
        />
        <StatCard
          label="Co-reviewers"
          value={company.co_reviewer_count}
          icon={<UserPlus className="h-5 w-5 text-accent" />}
        />
      </div>

      {reportId && (
        <Card title={`Latest report (v${company.latest_report?.version})`}>
          <p className="text-sm text-text-secondary">
            Your review:{' '}
            <Badge variant={company.my_review_status === 'submitted' ? 'success' : 'warning'}>
              {company.my_review_status || 'pending'}
            </Badge>
          </p>
          <Link to={`/reviewer/companies/${companyId}/reports/${reportId}/review`}>
            <Button className="mt-4">Open report review</Button>
          </Link>
        </Card>
      )}

      <div className="flex flex-wrap gap-3">
        <Link to={`/reviewer/companies/${companyId}/conversations`}>
          <Button variant="secondary">Conversations</Button>
        </Link>
        <Link to={`/reviewer/companies/${companyId}/chat`}>
          <Button variant="secondary">Co-reviewer chat</Button>
        </Link>
      </div>
    </div>
  );
}
