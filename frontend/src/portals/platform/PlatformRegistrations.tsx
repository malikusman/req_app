import { useEffect, useState } from 'react';
import { api, type CompanyRegistrationRow, type ReviewerApplicationRow } from '../../lib/api';
import { usePlatformToken } from '../../lib/auth';
import { PageHeader, Card, DataTable, Badge, Button, EmptyState, Textarea, Modal } from '../../components/ui';

type PendingAction =
  | { kind: 'company'; id: number; action: 'approve' | 'reject'; label: string }
  | { kind: 'reviewer'; id: number; action: 'approve' | 'reject'; label: string };

export function PlatformRegistrations() {
  const token = usePlatformToken();
  const [companies, setCompanies] = useState<CompanyRegistrationRow[]>([]);
  const [reviewers, setReviewers] = useState<ReviewerApplicationRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [pending, setPending] = useState<PendingAction | null>(null);
  const [note, setNote] = useState('');
  const [acting, setActing] = useState(false);

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

  const openAction = (next: PendingAction) => {
    setPending(next);
    setNote('');
    setError('');
  };

  const closeModal = () => {
    if (acting) return;
    setPending(null);
    setNote('');
  };

  const confirmAction = async () => {
    if (!token || !pending) return;
    setActing(true);
    setError('');
    try {
      if (pending.kind === 'company') {
        if (pending.action === 'approve') await api.approveCompanyRegistration(token, pending.id, note || undefined);
        else await api.rejectCompanyRegistration(token, pending.id, note || undefined);
      } else {
        if (pending.action === 'approve') await api.approveReviewerApplication(token, pending.id, note || undefined);
        else await api.rejectReviewerApplication(token, pending.id, note || undefined);
      }
      setPending(null);
      setNote('');
      load();
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Action failed');
    } finally {
      setActing(false);
    }
  };

  const confirmLabel = pending?.action === 'approve' ? 'Approve' : 'Reject';

  return (
    <div className="space-y-6">
      <PageHeader
        title="Registrations"
        description="Approve or reject company signups and reviewer applications."
      />

      {error && !pending ? (
        <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
          {error}
        </div>
      ) : null}

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
                    {r.role_title ? <div className="text-xs text-text-secondary">{r.role_title}</div> : null}
                  </div>
                ),
              },
              {
                key: 'profile',
                header: 'Profile',
                render: (r) => {
                  const industry = r.company_profile?.industry;
                  const size = r.company_profile?.size_band;
                  if (!industry && !size) return <span className="text-text-secondary">—</span>;
                  return (
                    <div className="text-sm">
                      {industry ? <div className="capitalize">{String(industry).replace(/_/g, ' ')}</div> : null}
                      {size ? <div className="text-xs text-text-secondary">{size}</div> : null}
                    </div>
                  );
                },
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
                      onClick={() =>
                        openAction({ kind: 'company', id: r.id, action: 'approve', label: r.company_name })
                      }
                    >
                      Approve
                    </Button>
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() =>
                        openAction({ kind: 'company', id: r.id, action: 'reject', label: r.company_name })
                      }
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
                      onClick={() =>
                        openAction({ kind: 'reviewer', id: r.id, action: 'approve', label: r.name })
                      }
                    >
                      Approve
                    </Button>
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() =>
                        openAction({ kind: 'reviewer', id: r.id, action: 'reject', label: r.name })
                      }
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

      <Modal
        open={Boolean(pending)}
        onClose={closeModal}
        title={pending ? `${confirmLabel} ${pending.kind === 'company' ? 'company' : 'reviewer'}` : ''}
        footer={
          <>
            <Button variant="secondary" onClick={closeModal} disabled={acting}>
              Cancel
            </Button>
            <Button
              variant={pending?.action === 'reject' ? 'danger' : 'primary'}
              onClick={confirmAction}
              loading={acting}
            >
              {confirmLabel}
            </Button>
          </>
        }
      >
        {pending ? (
          <div className="space-y-4">
            <p className="m-0 text-sm text-text-secondary">
              {pending.action === 'approve' ? 'Approve' : 'Reject'} <strong>{pending.label}</strong>
              {pending.action === 'approve' ? ' and send a set-password email.' : '.'}
            </p>
            {error ? (
              <div className="rounded-button border border-status-error/30 bg-status-errorBg px-3 py-2 text-sm text-status-error">
                {error}
              </div>
            ) : null}
            <Textarea
              label="Review note (optional)"
              rows={3}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              placeholder="Optional note for the audit trail"
            />
          </div>
        ) : null}
      </Modal>
    </div>
  );
}
