import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api } from '../../lib/api';
import { useReviewerToken } from '../../lib/auth';
import { PageHeader, Card, Badge, EmptyState } from '../../components/ui';

export function ReviewerFollowups() {
  const token = useReviewerToken();
  const [followups, setFollowups] = useState<
    {
      id: number;
      company_id: number;
      company_name: string;
      employee_id: number;
      employee_name: string;
      status: string;
      body: string;
      updated_at: string;
    }[]
  >([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!token) return;
    api
      .reviewerFollowups(token)
      .then((d) => setFollowups(d.followups))
      .catch(() => setFollowups([]))
      .finally(() => setLoading(false));
  }, [token]);

  return (
    <div className="space-y-6">
      <PageHeader
        title="Follow-ups"
        description="WhatsApp follow-up threads with employees across your assigned companies."
      />

      {loading ? (
        <p className="text-sm text-text-secondary">Loading…</p>
      ) : followups.length === 0 ? (
        <EmptyState title="No follow-ups" description="Follow-up threads appear when you request clarification." />
      ) : (
        <div className="space-y-3">
          {followups.map((f) => (
            <Card key={f.id}>
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div>
                  <p className="m-0 font-medium text-text-primary">
                    {f.employee_name} · {f.company_name}
                  </p>
                  <p className="mt-1 text-sm text-text-secondary line-clamp-2">{f.body}</p>
                  <p className="mt-2 text-xs text-text-secondary">
                    Updated {new Date(f.updated_at).toLocaleString()}
                  </p>
                </div>
                <div className="flex flex-col items-end gap-2">
                  <Badge variant={f.status === 'answered' ? 'success' : 'info'}>{f.status}</Badge>
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
