import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { ReviewerChatDrawer } from './workspace/ReviewerChatDrawer';
import { PageHeader, Button } from '../../components/ui';
import { MessageSquare } from 'lucide-react';

export function ReviewerChat() {
  const { companyId } = useParams();
  const [open, setOpen] = useState(true);

  useEffect(() => {
    setOpen(true);
  }, [companyId]);

  if (!companyId) return null;

  return (
    <div className="space-y-6">
      <PageHeader
        title="Co-reviewer chat"
        description="Private channel with co-reviewers on this assignment."
        breadcrumbs={[
          { label: 'Dashboard', href: '/reviewer/dashboard' },
          { label: 'Company', href: `/reviewer/companies/${companyId}` },
          { label: 'Chat' },
        ]}
      />
      {!open && (
        <Button onClick={() => setOpen(true)} icon={<MessageSquare className="h-4 w-4" />}>
          Open chat
        </Button>
      )}
      <ReviewerChatDrawer companyId={Number(companyId)} open={open} onOpenChange={setOpen} />
    </div>
  );
}
