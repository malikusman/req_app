import { CompanyExpertConsultants } from './CompanyExpertConsultants';
import { PageHeader } from '../../components/ui';

export function CompanyConsultantsPage() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Your consultant"
        description="The expert reviewing your discovery and shaping your report."
      />
      <CompanyExpertConsultants hideIntro />
    </div>
  );
}
