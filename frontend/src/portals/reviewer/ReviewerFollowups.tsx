import { Link } from 'react-router-dom';
import { PageHeader, Card, Badge, EmptyState } from '../../components/ui';

const mockFollowups = [
  {
    companyId: 1,
    companyName: 'Acme Corp',
    employeeId: 12,
    employeeName: 'Jordan Lee',
    status: 'awaiting_reply',
    lastMessage: 'Could you clarify the approval workflow for POs over $10k?',
    updatedAt: '2026-05-18T14:00:00Z',
  },
  {
    companyId: 1,
    companyName: 'Acme Corp',
    employeeId: 15,
    employeeName: 'Sam Rivera',
    status: 'open',
    lastMessage: 'Following up on the inventory reconciliation thread.',
    updatedAt: '2026-05-19T08:30:00Z',
  },
];

export function ReviewerFollowups() {
  return (
    <div className="space-y-6">
      <PageHeader
        title="Follow-ups"
        description="WhatsApp follow-up threads with employees across your assigned companies."
      />

      {mockFollowups.length === 0 ? (
        <EmptyState title="No follow-ups" description="Follow-up threads appear when you request clarification." />
      ) : (
        <div className="space-y-3">
          {mockFollowups.map((f) => (
            <Card key={`${f.companyId}-${f.employeeId}`}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="m-0 text-sm text-text-secondary">{f.companyName}</p>
                  <h3 className="m-0 font-medium text-text-primary">{f.employeeName}</h3>
                  <p className="mt-2 text-sm text-text-secondary">{f.lastMessage}</p>
                </div>
                <div className="flex flex-col items-end gap-2">
                  <Badge variant={f.status === 'awaiting_reply' ? 'warning' : 'info'}>
                    {f.status.replace(/_/g, ' ')}
                  </Badge>
                  <span className="text-xs text-text-secondary">
                    {new Date(f.updatedAt).toLocaleString()}
                  </span>
                  <Link
                    to={`/reviewer/companies/${f.companyId}/employees/${f.employeeId}/followup`}
                    className="text-sm font-medium text-accent hover:underline"
                  >
                    Open thread →
                  </Link>
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
