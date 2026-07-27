import { CompanyExpertReviewers } from './CompanyExpertReviewers';
import { PageHeader } from '../../components/ui';

export function CompanyReviewersPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Reviewers"
        description="Experts assigned to your company. Their published profiles help you understand who is shaping your report."
      />
      <CompanyExpertReviewers hideIntro />
    </div>
  );
}
