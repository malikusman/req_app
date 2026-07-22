import { useEffect, useState } from 'react';
import { api, type CompanyRegistrationRow, type ReviewerApplicationRow } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, EmptyState, Textarea } from '../../components/ui';

export function PlatformRegistrations() {
  const token = usePlatformToken();
  const [companies, setCompanies] = useState<CompanyRegistrationRow[]>([]);
  const [reviewers, setReviewers] = useState<ReviewerApplicationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [note, setNote] = useState('');
  const [acting, setActing] = useState<string | null>(null);

  const load = () => {
    if (!token) return;
    setLoading(true);
    setError('');
    api
      .platformRegistrations(token, 'pending')
      .then((data) => {
        setCompanies(data.company_registrations.filter((r) => r.status === 'pending'));
        setReviewers(data.reviewer_applications.filter((r) => r.status === 'pending'));
      })
      .catch((err) => setError(err instanceof Error ? err.message : 'Failed to load'))
      .finally(() => setLoading(false));
  };

  useEffect(load, [token]);

  const actCompany = async (id: number, action: 'approve' | 'reject') => {
    if (!token) return;
    setActing(`c-${id}-${action}`);
    try {
      if (action === 'approve') await api.approveCompanyRegistration(token, id, note || undefined);
      else await api.rejectCompanyRegistration(token, id, note || undefined);
      setNote('');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Action failed');
    } finally {
      setActing(null);
    }
  };

  const actReviewer = async (id: number, action: 'approve' | 'reject') => {
    if (!token) return;
    setActing(`r-${id}-${action}`);
    try {
      if (action === 'approve') await api.approveReviewerApplication(token, id, note || undefined);
      else await api.rejectReviewerApplication(token, id, note || undefined);
      setNote('');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Action failed');
    } finally {
      setActing(null);
    }
  };

  return (
    <div className="space-y-6">
      <PageHeader
        title="Registrations"
        description="Approve or reject company signups and reviewer applications."
      />

      {error ? (
        <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
          {error}
        </div>
      ) : null}

      <Card>
        <label className="mb-4 block text-sm text-text-secondary">
          Review note (optional, applied to the next action)
          <Textarea className="mt-1" value={note} onChange={(e) => setNote(e.target.value)} rows={2} />
        </label>
      </Card>

      <Card>
        <h2 className="font-display m-0 mb-4 text-lg text-text-primary">Company signups</h2>
        {loading ? (
          <p className="text-sm text-text-secondary">Loading…</p>
        ) : companies.length === 0 ? (
          <EmptyState title="No pending company signups" description="New requests will appear here." />
        ) : (
          <DataTable
            columns={[
              { key: 'company', header: 'Company', render: (r) => r.company_name },
              {
                key: 'admin',
                header: 'Admin',
                render: (r) => (
                  <div>
                    <div>{r.admin_name}</div>
                    <div className="text-xs text-text-secondary">{r.admin_email}</div>
                  </div>
                ),
              },
              {
                key: 'status',
                header: 'Status',
                render: (r) => <Badge variant="warning">{r.status}</Badge>,
              },
              {
                key: 'actions',
                header: '',
                render: (r) => (
                  <div className="flex gap-2">
                    <Button
                      size="sm"
                      loading={acting === `c-${r.id}-approve`}
                      onClick={() => actCompany(r.id, 'approve')}
                    >
                      Approve
                    </Button>
                    <Button
                      size="sm"
                      variant="secondary"
                      loading={acting === `c-${r.id}-reject`}
                      onClick={() => actCompany(r.id, 'reject')}
                    >
                      Reject
                    </Button>
                  </div>
                ),
              },
            ]}
            rows={companies}
          />
        )}
      </Card>

      <Card>
        <h2 className="font-display m-0 mb-4 text-lg text-text-primary">Reviewer applications</h2>
        {loading ? (
          <p className="text-sm text-text-secondary">Loading…</p>
        ) : reviewers.length === 0 ? (
          <EmptyState title="No pending reviewer applications" description="New applications will appear here." />
        ) : (
          <DataTable
            columns={[
              { key: 'name', header: 'Name', render: (r) => r.name },
              { key: 'email', header: 'Email', render: (r) => r.email },
              {
                key: 'expertise',
                header: 'Expertise',
                render: (r) => r.expertise_summary || r.headline || '—',
              },
              {
                key: 'actions',
                header: '',
                render: (r) => (
                  <div className="flex gap-2">
                    <Button
                      size="sm"
                      loading={acting === `r-${r.id}-approve`}
                      onClick={() => actReviewer(r.id, 'approve')}
                    >
                      Approve
                    </Button>
                    <Button
                      size="sm"
                      variant="secondary"
                      loading={acting === `r-${r.id}-reject`}
                      onClick={() => actReviewer(r.id, 'reject')}
                    >
                      Reject
                    </Button>
                  </div>
                ),
              },
            ]}
            rows={reviewers}
          />
        )}
      </Card>
    </div>
  );
}
