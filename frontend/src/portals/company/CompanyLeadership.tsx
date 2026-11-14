import { useMemo } from 'react';
import { PageHeader } from '../../components/ui';
import { useCompanyToken } from '../../lib/auth';
import { LeadershipChat } from '../shared/conversation/LeadershipChat';

/** The key user's own conversation with leadership (Doc 08), in the portal. */
export function CompanyLeadership() {
  const token = useCompanyToken();
  const door = useMemo(() => ({ base: '/api/v1/company/leadership', token }), [token]);

  return (
    <div className="flex min-h-[calc(100dvh-8rem)] flex-col gap-6">
      <PageHeader
        title="Your conversation with Mjadi"
        description="Where you're taking the business, what gets in the way, and where we should look first."
      />
      {token && <LeadershipChat door={door} keyUserToken={token} />}
    </div>
  );
}
