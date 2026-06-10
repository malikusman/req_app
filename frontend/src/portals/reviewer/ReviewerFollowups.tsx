import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, type ReviewerFollowupRow } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, Badge, EmptyState } from '../../components/ui';

export function ReviewerFollowups() {
  const token = useReviewerToken();
  const [followups, setFollowups] = useState<ReviewerFollowupRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    if (!token) return;
    api
      .reviewerFollowups(token)
      .then((d) => setFollowups(d.followups))
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load follow-ups'))
      .finally(() => setLoading(false));
  }, [token]);

  if (loading) {
    return (
      <div className="space-y-6">
        <PageHeader title="Follow-ups" description="Loading…" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <PageHeader
        title="Follow-ups"
        description="WhatsApp follow-up threads with employees across your assigned companies."
      />

      {error && <p className="text-sm text-status-error">{error}</p>}

      {followups.length === 0 ? (
        <EmptyState title="No follow-ups" description="Follow-up threads appear when you request clarification." />
      ) : (
        <div className="space-y-3">
          {followups.map((f) => (
            <Card key={f.id}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="m-0 text-sm text-text-secondary">{f.company_name}</p>
                  <h3 className="m-0 font-medium text-text-primary">
                    {f.employee_name || `Employee #${f.employee_id}`}
                  </h3>
                  <p className="mt-2 text-sm text-text-secondary">{f.last_message}</p>
                </div>
                <div className="flex flex-col items-end gap-2">
                  <Badge variant={f.status === 'awaiting_reply' ? 'warning' : 'info'}>
                    {f.status.replace(/_/g, ' ')}
                  </Badge>
                  <span className="text-xs text-text-secondary">
                    {new Date(f.updated_at).toLocaleString()}
                  </span>
                  <Link
                    to={`/reviewer/companies/${f.company_id}/employees/${f.employee_id}/followup`}
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
