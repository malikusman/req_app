import { CompanyExpertReviewers } from './CompanyExpertReviewers';
import { PageHeader } from '../../components/ui';

export function CompanyReviewersPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Your reviewer"
        description="The expert reviewing your discovery and shaping your report."
      />
      <CompanyExpertReviewers hideIntro />
    </div>
  );
}
